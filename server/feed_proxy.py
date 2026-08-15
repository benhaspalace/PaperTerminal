#!/usr/bin/env python3
"""PaperTerminal feed proxy.

The Kindle 3 cannot speak modern HTTPS, so it fetches its flight data as a
tiny plain-text feed over plain HTTP. This proxy runs on any machine on your
LAN (laptop, Raspberry Pi, NAS) and converts a real flight-data API into
that feed.

Feed protocol v3 (what the Kindle requests):

    GET /feed?airport=ZRH&dir=arr&limit=12&window=ahead
        dir:    arr | dep | all
        window: ahead (default) - recent tail + upcoming, `limit` lines
                split - `limit` flights BEFORE now and `limit` AFTER now
                        (the ones most likely to be in the air), so up to
                        2 x limit lines

    200 OK, text/plain, one flight per line:

        #PAPERTERMINAL 3 OK ZRH ALL AHEAD
        A|13:41|LX1073|SWISS|A20N|14|BUD|-12|31
        D|13:44|LX316|SWISS|BCS3|28|LCY||
        ...

    Fields: DIR|TIME|FLIGHT|AIRLINE|TYPE|RUNWAY|AIRPORT|DX|DY. DIR is A
    for an arrival or D for a departure; AIRPORT is the origin airport
    for arrivals and the destination for departures. DX/DY are the
    aircraft's live ADS-B position in whole nautical miles east/north of
    the requested airport (empty when the aircraft isn't currently seen).
    dir=all interleaves both directions sorted by time. Lines starting
    with '#' are comments. Runway/airport are '-' when the backend does
    not provide them.

Flight-data backends (primary + optional --backend2 fallback):

    aeroapi        FlightAware AeroAPI v4 (https://www.flightaware.com/aeroapi)
                   Has actual runway used (on landed/departed flights) and
                   ICAO aircraft types. Personal tier is free within limits.
                   ICAO airport codes (LSZH) are safest; IATA usually works.

    aviationstack  https://aviationstack.com - free key, plain airline names
                   and IATA aircraft types, but no runway data ('-').

Live positions come from open ADS-B aggregators (no key needed), tried in
order until one answers: api.adsb.lol, then opendata.adsb.fi. Positions
are matched to flights by callsign and only attached for airports listed
in AIRPORT_COORDS (extend the table for yours).

Usage:

    python3 feed_proxy.py --backend aeroapi --key YOUR_KEY
    python3 feed_proxy.py --backend aeroapi --key K1 \
        --backend2 aviationstack --key2 K2       # flight-data failover
    python3 feed_proxy.py --backend aviationstack --key YOUR_KEY --no-adsb

Then on the Kindle set in paperterminal.conf:

    FEED_URL=http://<this-machine's-LAN-IP>:8091/feed

Only the Python standard library is used. Responses are cached (default
300 s) so the Kindle can refresh freely without burning API quota.
"""

import argparse
import json
import math
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# Airline names for AeroAPI, which only returns carrier codes.
IATA_AIRLINES = {
    "A3": "AEGEAN", "AA": "AMERICAN", "AC": "AIR CANADA", "AF": "AIR FRANCE",
    "AY": "FINNAIR", "AZ": "ITA AIRWAYS", "BA": "BRITISH AIRWAYS",
    "DL": "DELTA", "EI": "AER LINGUS", "EK": "EMIRATES", "EW": "EUROWINGS",
    "EY": "ETIHAD", "FR": "RYANAIR", "IB": "IBERIA", "KL": "KLM",
    "KM": "KM MALTA", "LG": "LUXAIR", "LH": "LUFTHANSA", "LO": "LOT",
    "LX": "SWISS", "OS": "AUSTRIAN", "QR": "QATAR AIRWAYS",
    "SK": "SAS", "SN": "BRUSSELS AIRLINES", "SQ": "SINGAPORE AIRLINES",
    "TK": "TURKISH AIRLINES", "TP": "TAP PORTUGAL", "U2": "EASYJET",
    "UA": "UNITED", "VS": "VIRGIN ATLANTIC", "VY": "VUELING",
    "W6": "WIZZ AIR", "WK": "EDELWEISS",
}

WINDOW_PAST = timedelta(minutes=45)      # 'ahead': recent tail kept on boards
WINDOW_PAST_SPLIT = timedelta(hours=3)   # 'split': how far back "before now" reaches
WINDOW_FUTURE = timedelta(hours=12)

# Airport reference coordinates for ADS-B position lookups (lat, lon).
# Positions are only attached for airports listed here - add your own.
AIRPORT_COORDS = {
    "ZRH": (47.4647, 8.5492),  "LSZH": (47.4647, 8.5492),
    "BUD": (47.4298, 19.2611), "LHBP": (47.4298, 19.2611),
    "AMS": (52.3105, 4.7683),  "EHAM": (52.3105, 4.7683),
    "STR": (48.6899, 9.2210),  "EDDS": (48.6899, 9.2210),
    "GVA": (46.2381, 6.1090),  "LSGG": (46.2381, 6.1090),
    "LHR": (51.4700, -0.4543), "EGLL": (51.4700, -0.4543),
    "LGW": (51.1537, -0.1821), "EGKK": (51.1537, -0.1821),
    "CDG": (49.0097, 2.5479),  "LFPG": (49.0097, 2.5479),
    "FRA": (50.0379, 8.5622),  "EDDF": (50.0379, 8.5622),
    "MUC": (48.3538, 11.7861), "EDDM": (48.3538, 11.7861),
    "VIE": (48.1103, 16.5697), "LOWW": (48.1103, 16.5697),
    "JFK": (40.6413, -73.7781), "KJFK": (40.6413, -73.7781),
}


def parse_ts(value):
    """Parse an ISO-8601 timestamp from either backend; None if absent."""
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt


def http_get_json(url, headers=None):
    req = urllib.request.Request(url, headers=headers or {})
    req.add_header("User-Agent", "PaperTerminal-feed-proxy/1.0")
    with urllib.request.urlopen(req, timeout=25) as resp:
        return json.loads(resp.read().decode("utf-8"))


def airline_name(code, fallback=""):
    return IATA_AIRLINES.get((code or "").upper(), fallback or code or "-")


# ------------------------------------------------------------- backends ---

# Per-direction lookup tables: response groups, time-field preference,
# runway field, the other endpoint of the flight, and the feed DIR tag.
AEROAPI_SIDES = {
    "arr": (("arrivals", "scheduled_arrivals"),
            ("actual_on", "estimated_on", "scheduled_on"),
            "actual_runway_on", "origin", "A"),
    "dep": (("departures", "scheduled_departures"),
            ("actual_off", "estimated_off", "scheduled_off"),
            "actual_runway_off", "destination", "D"),
}


def sides_for(direction):
    return ("arr", "dep") if direction == "all" else (direction,)


def rows_aeroapi(key, airport, direction):
    # One /flights call carries arrivals and departures alike.
    url = ("https://aeroapi.flightaware.com/aeroapi/airports/"
           f"{urllib.parse.quote(airport)}/flights?max_pages=1")
    data = http_get_json(url, {"x-apikey": key})

    rows = []
    for side in sides_for(direction):
        groups, time_keys, runway_key, other_key, tag = AEROAPI_SIDES[side]
        for group in groups:
            for f in data.get(group) or []:
                ts = None
                for k in time_keys:
                    ts = parse_ts(f.get(k))
                    if ts:
                        break
                if ts is None:
                    continue
                flight = f.get("ident_iata") or f.get("ident") or "-"
                carrier = f.get("operator_iata") or f.get("operator") or flight[:2]
                other = f.get(other_key) or {}
                rows.append({
                    "ts": ts,
                    "dir": tag,
                    "flight": flight,
                    # 'ident' is the filed callsign - what ADS-B transmits
                    "callsign": f.get("ident") or "",
                    "airline": airline_name(carrier, f.get("operator")),
                    "actype": f.get("aircraft_type") or "-",
                    "runway": f.get(runway_key) or "-",
                    "airport": other.get("code_iata") or other.get("code") or "-",
                })
    return rows


def rows_aviationstack(key, airport, direction):
    rows = []
    for side in sides_for(direction):
        if side == "arr":
            seg_key, other_key, filter_key, tag = "arrival", "departure", "arr_iata", "A"
        else:
            seg_key, other_key, filter_key, tag = "departure", "arrival", "dep_iata", "D"
        params = urllib.parse.urlencode({
            "access_key": key,
            "limit": 100,
            filter_key: airport,
        })
        data = http_get_json(f"http://api.aviationstack.com/v1/flights?{params}")

        for f in data.get("data") or []:
            if (f.get("flight_status") or "") == "cancelled":
                continue
            seg = f.get(seg_key) or {}
            ts = (parse_ts(seg.get("actual"))
                  or parse_ts(seg.get("estimated"))
                  or parse_ts(seg.get("scheduled")))
            if ts is None:
                continue
            flight_info = f.get("flight") or {}
            aircraft = f.get("aircraft") or {}
            other = f.get(other_key) or {}
            rows.append({
                "ts": ts,
                "dir": tag,
                "flight": flight_info.get("iata") or flight_info.get("icao") or "-",
                "callsign": flight_info.get("icao") or "",
                "airline": (f.get("airline") or {}).get("name") or "-",
                "actype": aircraft.get("iata") or "-",
                "runway": "-",  # aviationstack has no runway data
                "airport": other.get("iata") or other.get("icao") or "-",
            })
    return rows


BACKENDS = {"aeroapi": rows_aeroapi, "aviationstack": rows_aviationstack}


def select_rows(rows, limit, window):
    """Sort, dedupe, and window the raw rows.

    window 'ahead': a short just-happened tail plus upcoming flights,
    `limit` lines in total (what a terminal board shows).
    window 'split': the `limit` flights closest before now AND the
    `limit` closest after now - the set most likely to be airborne,
    which is what the live traffic map wants.
    """
    now = datetime.now(timezone.utc)
    deduped, seen = [], set()
    for r in sorted(rows, key=lambda r: r["ts"]):
        key = (r["dir"], r["flight"])
        if key in seen:
            continue
        seen.add(key)
        deduped.append(r)

    past_reach = WINDOW_PAST_SPLIT if window == "split" else WINDOW_PAST
    rows = [r for r in deduped
            if now - past_reach <= r["ts"] <= now + WINDOW_FUTURE]
    if window == "split":
        past = [r for r in rows if r["ts"] < now][-limit:]
        future = [r for r in rows if r["ts"] >= now][:limit]
        return past + future
    return rows[:limit]


def norm_callsign(cs):
    return "".join(str(cs).split()).upper()


def get_positions(args, airport):
    """callsign -> (dx_nm, dy_nm) east/north of the airport, from the
    first ADS-B source that answers. {} when disabled or unavailable."""
    if args.no_adsb:
        return {}
    coords = AIRPORT_COORDS.get(airport.upper())
    if not coords:
        return {}
    lat0, lon0 = coords
    radius = min(max(args.adsb_radius, 10), 250)
    bases = [u.strip().rstrip("/") for u in args.adsb_urls.split(",") if u.strip()]
    for base in bases:
        try:
            data = http_get_json(f"{base}/point/{lat0}/{lon0}/{radius}")
        except (urllib.error.URLError, OSError, ValueError) as exc:
            print(f"adsb source failed, trying next: {base}: {exc}")
            continue
        out = {}
        for a in data.get("ac") or []:
            cs = norm_callsign(a.get("flight") or "")
            lat, lon = a.get("lat"), a.get("lon")
            if not cs or lat is None or lon is None:
                continue
            dy = (lat - lat0) * 60.0
            dx = (lon - lon0) * 60.0 * math.cos(math.radians(lat0))
            out[cs] = (round(dx), round(dy))
        return out
    return {}


def format_lines(rows, positions):
    lines = []
    for r in rows:
        pos = (positions.get(norm_callsign(r.get("callsign") or ""))
               or positions.get(norm_callsign(r.get("flight") or "")))
        dx, dy = (str(pos[0]), str(pos[1])) if pos else ("", "")
        local = r["ts"].astimezone()  # server's local time zone
        lines.append("|".join((
            r["dir"],
            local.strftime("%H:%M"),
            str(r["flight"])[:7],
            str(r["airline"]).upper()[:16],
            str(r["actype"]).upper()[:4],
            str(r["runway"]).upper()[:3],
            str(r["airport"]).upper()[:4],
            dx,
            dy,
        )))
    return lines


# --------------------------------------------------------------- server ---

class FeedCache:
    def __init__(self, ttl):
        self.ttl = ttl
        self.lock = threading.Lock()
        self.entries = {}

    def get(self, key):
        with self.lock:
            hit = self.entries.get(key)
            if hit and time.time() - hit[0] < self.ttl:
                return hit[1]
        return None

    def put(self, key, value):
        with self.lock:
            self.entries[key] = (time.time(), value)


class FeedHandler(BaseHTTPRequestHandler):
    server_version = "PaperTerminalFeed/2.0"
    args = None
    backends = None   # [(backend_name, api_key), ...] tried in order
    cache = None      # raw flight rows per (airport, direction)
    pos_cache = None  # ADS-B positions per airport, short TTL

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.rstrip("/") not in ("", "/feed"):
            self.send_text(404, "#ERR unknown path, use /feed\n")
            return

        qs = urllib.parse.parse_qs(parsed.query)
        airport = (qs.get("airport", [self.args.default_airport])[0] or "").upper()
        direction = qs.get("dir", ["arr"])[0].lower()
        direction = direction if direction in ("arr", "dep", "all") else "arr"
        window = qs.get("window", ["ahead"])[0].lower()
        window = window if window in ("ahead", "split") else "ahead"
        try:
            limit = max(1, min(20, int(qs.get("limit", ["12"])[0])))
        except ValueError:
            limit = 12

        if not airport.isalnum() or not 3 <= len(airport) <= 4:
            self.send_text(400, "#ERR bad airport code\n")
            return

        # Raw rows are cached per (airport, direction); windowing and
        # position enrichment happen per request so positions stay fresh.
        key = (airport, direction)
        rows = self.cache.get(key)
        if rows is None:
            errors = []
            for backend, bkey in self.backends:
                try:
                    rows = BACKENDS[backend](bkey, airport, direction)
                    break
                except (urllib.error.URLError, OSError, ValueError, KeyError) as exc:
                    errors.append(f"{backend}: {exc}")
                    print(f"backend failed, trying next: {backend}: {exc}")
            if rows is None:
                self.send_text(502, "#ERR upstream: " + "; ".join(errors) + "\n")
                return
            self.cache.put(key, rows)

        selected = select_rows(rows, limit, window)

        positions = self.pos_cache.get(airport)
        if positions is None:
            positions = get_positions(self.args, airport)
            self.pos_cache.put(airport, positions)

        header = (f"#PAPERTERMINAL 3 OK {airport} "
                  f"{direction.upper()} {window.upper()}\n")
        self.send_text(200, header + "\n".join(format_lines(selected, positions)) + "\n")

    def send_text(self, status, body):
        payload = body.encode("ascii", "replace")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=us-ascii")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} - {fmt % args}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n", 1)[0])
    ap.add_argument("--backend", required=True, choices=sorted(BACKENDS))
    ap.add_argument("--key", required=True, help="API key for the backend")
    ap.add_argument("--backend2", choices=sorted(BACKENDS),
                    help="fallback flight-data backend, used when the primary fails")
    ap.add_argument("--key2", help="API key for --backend2")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8091)
    ap.add_argument("--cache", type=int, default=300,
                    help="seconds to cache upstream responses (default 300)")
    ap.add_argument("--default-airport", default="ZRH")
    ap.add_argument("--adsb-urls",
                    default="https://api.adsb.lol/v2,https://opendata.adsb.fi/api/v2",
                    help="comma-separated ADS-B API bases, tried in order")
    ap.add_argument("--adsb-radius", type=int, default=100,
                    help="ADS-B search radius around the airport in nm (max 250)")
    ap.add_argument("--no-adsb", action="store_true",
                    help="disable live position lookups entirely")
    args = ap.parse_args()

    if args.backend2 and not args.key2:
        ap.error("--backend2 requires --key2")

    FeedHandler.args = args
    FeedHandler.backends = [(args.backend, args.key)] + (
        [(args.backend2, args.key2)] if args.backend2 else [])
    FeedHandler.cache = FeedCache(max(60, args.cache))
    FeedHandler.pos_cache = FeedCache(30)  # positions age fast

    server = ThreadingHTTPServer((args.host, args.port), FeedHandler)
    backends = "+".join(b for b, _ in FeedHandler.backends)
    print(f"PaperTerminal feed proxy on http://{args.host}:{args.port}/feed "
          f"(backends={backends}, cache={args.cache}s, "
          f"adsb={'off' if args.no_adsb else args.adsb_urls})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
