#!/usr/bin/env python3
"""PaperTerminal feed proxy.

The Kindle 3 cannot speak modern HTTPS, so it fetches its flight data as a
tiny plain-text feed over plain HTTP. This proxy runs on any machine on your
LAN (laptop, Raspberry Pi, NAS) and converts a real flight-data API into
that feed.

Feed protocol (what the Kindle requests):

    GET /feed?airport=ZRH&dir=arr&limit=12

    200 OK, text/plain, one flight per line:

        #PAPERTERMINAL 1 OK ZRH ARR
        13:41|LX1073|SWISS|A20N|14
        13:46|BA710|BRITISH AIRWAYS|A320|14
        ...

    Fields: TIME|FLIGHT|AIRLINE|TYPE|RUNWAY. Lines starting with '#' are
    comments. Runway is '-' when the backend does not provide one.

Backends:

    aeroapi        FlightAware AeroAPI v4 (https://www.flightaware.com/aeroapi)
                   Has actual runway used (on landed/departed flights) and
                   ICAO aircraft types. Personal tier is free within limits.
                   ICAO airport codes (LSZH) are safest; IATA usually works.

    aviationstack  https://aviationstack.com - free key, plain airline names
                   and IATA aircraft types, but no runway data ('-').

Usage:

    python3 feed_proxy.py --backend aeroapi --key YOUR_KEY
    python3 feed_proxy.py --backend aviationstack --key YOUR_KEY --port 8091

Then on the Kindle set in paperterminal.conf:

    MODE=live
    FEED_URL=http://<this-machine's-LAN-IP>:8091/feed

Only the Python standard library is used. Responses are cached (default
300 s) so the Kindle can refresh freely without burning API quota.
"""

import argparse
import json
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

WINDOW_PAST = timedelta(minutes=45)   # keep recently landed/departed flights
WINDOW_FUTURE = timedelta(hours=12)


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

def rows_aeroapi(key, airport, direction, limit):
    url = ("https://aeroapi.flightaware.com/aeroapi/airports/"
           f"{urllib.parse.quote(airport)}/flights?max_pages=1")
    data = http_get_json(url, {"x-apikey": key})

    if direction == "arr":
        groups = ("arrivals", "scheduled_arrivals")
        time_keys = ("actual_on", "estimated_on", "scheduled_on")
        runway_key = "actual_runway_on"
    else:
        groups = ("departures", "scheduled_departures")
        time_keys = ("actual_off", "estimated_off", "scheduled_off")
        runway_key = "actual_runway_off"

    rows = []
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
            rows.append({
                "ts": ts,
                "flight": flight,
                "airline": airline_name(carrier, f.get("operator")),
                "actype": f.get("aircraft_type") or "-",
                "runway": f.get(runway_key) or "-",
            })
    return finish_rows(rows, limit)


def rows_aviationstack(key, airport, direction, limit):
    side = "arrival" if direction == "arr" else "departure"
    params = urllib.parse.urlencode({
        "access_key": key,
        "limit": 100,
        ("arr_iata" if direction == "arr" else "dep_iata"): airport,
    })
    data = http_get_json(f"http://api.aviationstack.com/v1/flights?{params}")

    rows = []
    for f in data.get("data") or []:
        if (f.get("flight_status") or "") == "cancelled":
            continue
        seg = f.get(side) or {}
        ts = (parse_ts(seg.get("actual"))
              or parse_ts(seg.get("estimated"))
              or parse_ts(seg.get("scheduled")))
        if ts is None:
            continue
        flight_info = f.get("flight") or {}
        aircraft = f.get("aircraft") or {}
        rows.append({
            "ts": ts,
            "flight": flight_info.get("iata") or flight_info.get("icao") or "-",
            "airline": (f.get("airline") or {}).get("name") or "-",
            "actype": aircraft.get("iata") or "-",
            "runway": "-",  # aviationstack has no runway data
        })
    return finish_rows(rows, limit)


def finish_rows(rows, limit):
    """Window around now, sort, dedupe, format as feed lines."""
    now = datetime.now(timezone.utc)
    rows = [r for r in rows if now - WINDOW_PAST <= r["ts"] <= now + WINDOW_FUTURE]
    rows.sort(key=lambda r: r["ts"])

    lines, seen = [], set()
    for r in rows:
        if r["flight"] in seen:
            continue
        seen.add(r["flight"])
        local = r["ts"].astimezone()  # server's local time zone
        lines.append("|".join((
            local.strftime("%H:%M"),
            str(r["flight"])[:8],
            str(r["airline"]).upper()[:17],
            str(r["actype"]).upper()[:4],
            str(r["runway"]).upper()[:3],
        )))
        if len(lines) >= limit:
            break
    return lines


BACKENDS = {"aeroapi": rows_aeroapi, "aviationstack": rows_aviationstack}


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
    server_version = "PaperTerminalFeed/1.0"
    args = None
    cache = None

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path.rstrip("/") not in ("", "/feed"):
            self.send_text(404, "#ERR unknown path, use /feed\n")
            return

        qs = urllib.parse.parse_qs(parsed.query)
        airport = (qs.get("airport", [self.args.default_airport])[0] or "").upper()
        direction = qs.get("dir", ["arr"])[0].lower()
        direction = direction if direction in ("arr", "dep") else "arr"
        try:
            limit = max(1, min(20, int(qs.get("limit", ["12"])[0])))
        except ValueError:
            limit = 12

        if not airport.isalnum() or not 3 <= len(airport) <= 4:
            self.send_text(400, "#ERR bad airport code\n")
            return

        key = (airport, direction)
        lines = self.cache.get(key)
        if lines is None:
            try:
                lines = BACKENDS[self.args.backend](
                    self.args.key, airport, direction, 20)
                self.cache.put(key, lines)
            except (urllib.error.URLError, OSError, ValueError, KeyError) as exc:
                self.send_text(502, f"#ERR upstream: {exc}\n")
                return

        header = f"#PAPERTERMINAL 1 OK {airport} {direction.upper()}\n"
        self.send_text(200, header + "\n".join(lines[:limit]) + "\n")

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
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("--port", type=int, default=8091)
    ap.add_argument("--cache", type=int, default=300,
                    help="seconds to cache upstream responses (default 300)")
    ap.add_argument("--default-airport", default="ZRH")
    args = ap.parse_args()

    FeedHandler.args = args
    FeedHandler.cache = FeedCache(max(60, args.cache))

    server = ThreadingHTTPServer((args.host, args.port), FeedHandler)
    print(f"PaperTerminal feed proxy on http://{args.host}:{args.port}/feed "
          f"(backend={args.backend}, cache={args.cache}s)")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
