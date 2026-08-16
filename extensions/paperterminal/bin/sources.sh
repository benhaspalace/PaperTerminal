#!/bin/sh
# PaperTerminal - direct public-API flight data, no proxy involved.
# Sourced by board.sh / radar.sh / nettest.sh after common.sh.
#
# Sources (paperterminal.conf, tried in order until one delivers):
#   SOURCE1=aeroapi,YOUR_KEY        FlightAware AeroAPI v4 (runway data)
#   SOURCE2=aviationstack,YOUR_KEY  aviationstack (no runway data)
#
# Live positions for the traffic map come straight from open ADS-B
# aggregators (adsb.fi -> adsb.lol -> adsb.one -> airplanes.live, all
# speaking the same readsb re-api, with the OpenSky Network as a last
# resort) - no key needed. OpenSky's anonymous API is limited (~400
# credits/day, 10 s data resolution), so its calls are budgeted
# (OPENSKY_DAY) and all raw responses are cached for 10 s.
#
# All JSON is parsed on-device by a small awk object scanner that tracks
# brace depth and string state, so it does not depend on key order or
# formatting. Responses are cached in /tmp to protect API quotas.

PT_AIRPORTS="$PT_HOME/data/airports.txt"
PT_AIRLINES="$PT_HOME/data/airlines.txt"
PT_CACHE_DIR="/tmp/paperterminal.cache"

AEROAPI_BASE="${PT_AEROAPI_BASE:-https://aeroapi.flightaware.com/aeroapi}"
AVSTACK_BASE="${PT_AVSTACK_BASE:-http://api.aviationstack.com/v1}"
ADSB_DEFAULT="https://opendata.adsb.fi/api/v2 https://api.adsb.lol/v2 https://api.adsb.one/v2 https://api.airplanes.live/v2"
OPENSKY_BASE="${PT_OPENSKY_BASE:-https://opensky-network.org/api}"

# --------------------------------------------------------------- time ------

# UTC offset of the device clock in minutes (handles half-hour zones).
tz_offset_min() {
    uh=$(date -u +%H); um=$(date -u +%M)
    lh=$(date +%H);    lm=$(date +%M)
    uh=${uh#0}; um=${um#0}; lh=${lh#0}; lm=${lm#0}
    d=$(( lh * 60 + lm - uh * 60 - um ))
    [ $d -gt 720 ]  && d=$(( d - 1440 ))
    [ $d -lt -720 ] && d=$(( d + 1440 ))
    echo $d
}

# Absolute minutes (julian day * 1440 + h*60 + m) of "now" in UTC.
now_abs_min() {
    set -- $(date -u '+%Y %m %d %H %M')
    awk -v y="$1" -v m="${2#0}" -v d="${3#0}" -v h="${4#0}" -v mi="${5#0}" 'BEGIN {
        a = int((14 - m) / 12); y2 = y + 4800 - a; m2 = m + 12 * a - 3
        j = d + int((153 * m2 + 2) / 5) + 365 * y2 + int(y2 / 4) \
            - int(y2 / 100) + int(y2 / 400) - 32045
        print j * 1440 + h * 60 + mi }'
}

# Airport database format: IATA|ICAO|LAT|LON|CITY|NAME
apt_coords() { # apt_coords CODE -> "LAT LON", fails if unknown
    [ -f "$PT_AIRPORTS" ] || return 1
    line="$(awk -F'|' -v c="$1" \
        'toupper($1) == c || toupper($2) == c { print $3, $4; exit }' \
        "$PT_AIRPORTS" 2>/dev/null)"
    [ -n "$line" ] || return 1
    echo "$line"
}

# ---------------------------------------------------- awk json helpers -----
# jstr:  string value of a top-level key in an object snippet
# jnum:  numeric value
# jobj:  a nested object value, extracted with balanced-brace scanning
# tmin:  ISO-8601 UTC timestamp -> absolute minutes (-1 if absent)

PT_AWK_JSON='
function jstr(o, k,   r) {
    if (match(o, "\"" k "\" *: *\"")) {
        r = substr(o, RSTART + RLENGTH)
        if (match(r, /^[^"]*/)) return substr(r, 1, RLENGTH)
    }
    return ""
}
function jnum(o, k,   r) {
    if (match(o, "\"" k "\" *: *")) {
        r = substr(o, RSTART + RLENGTH)
        if (match(r, /^-?[0-9.]+/)) return substr(r, 1, RLENGTH) + 0
    }
    return ""
}
function jobj(o, k,   i, c, dep, ins, esc, st) {
    if (!match(o, "\"" k "\" *: *\\{")) return ""
    i = RSTART + RLENGTH - 1
    st = i; dep = 0; ins = 0; esc = 0
    for (; i <= length(o); i++) {
        c = substr(o, i, 1)
        if (ins) {
            if (esc) esc = 0
            else if (c == "\\") esc = 1
            else if (c == "\"") ins = 0
            continue
        }
        if (c == "\"") { ins = 1; continue }
        if (c == "{") dep++
        else if (c == "}") { dep--; if (dep == 0) return substr(o, st, i - st + 1) }
    }
    return ""
}
function tmin(t,   y, m, d, h, mi, a, y2, m2, j) {
    if (length(t) < 16) return -1
    y = substr(t, 1, 4) + 0; m = substr(t, 6, 2) + 0; d = substr(t, 9, 2) + 0
    h = substr(t, 12, 2) + 0; mi = substr(t, 15, 2) + 0
    if (y < 2000) return -1
    a = int((14 - m) / 12); y2 = y + 4800 - a; m2 = m + 12 * a - 3
    j = d + int((153 * m2 + 2) / 5) + 365 * y2 + int(y2 / 4) \
        - int(y2 / 100) + int(y2 / 400) - 32045
    return j * 1440 + h * 60 + mi
}
'

# ------------------------------------------------------- aeroapi budget ----
# FlightAware's free Personal tier is a monthly usage credit (about $5,
# roughly 200 airport-flights queries at ~$0.025 each). These counters
# persist across reboots and gate every AeroAPI call; when a cap is hit
# the code fails over to the next source or serves stale cache instead.

PT_AERO_USAGE="$PT_HOME/aeroapi.usage"

aero_load_usage() {
    AERO_MKEY="$(date +%Y-%m)"
    AERO_DKEY="$(date +%Y-%m-%d)"
    UMON=""; UMC=""; UDAY=""; UDC=""
    if [ -f "$PT_AERO_USAGE" ]; then
        read -r UMON UMC UDAY UDC < "$PT_AERO_USAGE" 2>/dev/null
    fi
    [ "$UMON" = "$AERO_MKEY" ] || UMC=0
    [ "$UDAY" = "$AERO_DKEY" ] || UDC=0
    case "$UMC" in ''|*[!0-9]*) UMC=0;; esac
    case "$UDC" in ''|*[!0-9]*) UDC=0;; esac
}

aero_allow() {
    aero_load_usage
    if [ "$UDC" -ge "$AERO_DAY" ] || [ "$UMC" -ge "$AERO_MONTH" ]; then
        log "aeroapi budget reached (day $UDC/$AERO_DAY, month $UMC/$AERO_MONTH)"
        return 1
    fi
    return 0
}

aero_count() {
    aero_load_usage
    UMC=$(( UMC + 1 ))
    UDC=$(( UDC + 1 ))
    echo "$AERO_MKEY $UMC $AERO_DKEY $UDC" > "$PT_AERO_USAGE" 2>/dev/null
}

# Object scanner main: feeds every depth-2 object (array members of the
# root object) to emit().
PT_AWK_SCAN='
{ buf = buf $0 }
END {
    n = length(buf); dep = 0; ins = 0; esc = 0; st = 0
    for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (ins) {
            if (esc) esc = 0
            else if (c == "\\") esc = 1
            else if (c == "\"") ins = 0
            continue
        }
        if (c == "\"") { ins = 1; continue }
        if (c == "{") { dep++; if (dep == 2) st = i; continue }
        if (c == "}") { if (dep == 2 && st) emit(substr(buf, st, i - st + 1)); dep--; continue }
    }
}
'

# Loader rule for the ICAO-callsign-prefix airline map (nmi[]); pass
# data/airlines.txt as the FIRST file, ahead of the JSON payload.
PT_AWK_NMI='
NR == FNR { if ($0 !~ /^#/) { split($0, aa, "|"); if (aa[2] != "") nmi[aa[2]] = aa[3] } next }
'

# Group-aware scanner for AeroAPI's combined /flights response: the root
# object holds four arrays (arrivals, scheduled_arrivals, departures,
# scheduled_departures); the current array key is tracked so one billed
# query serves every board direction.
PT_AWK_SCAN_GROUPED='
{ buf = buf $0 }
END {
    n = length(buf); dep = 0; ins = 0; esc = 0; st = 0; grp = ""; s = ""
    for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (ins) {
            if (esc) esc = 0
            else if (c == "\\") esc = 1
            else if (c == "\"") { ins = 0; if (dep == 1) lastkey = s }
            else if (dep == 1) s = s c
            continue
        }
        if (c == "\"") { ins = 1; s = ""; continue }
        if (c == "[") { if (dep == 1) grp = lastkey; continue }
        if (c == "{") { dep++; if (dep == 2) st = i; continue }
        if (c == "}") { if (dep == 2 && st) emit(substr(buf, st, i - st + 1), grp); dep--; continue }
    }
}
'

# Raw parser output: SORTKEY|DIR|FLIGHT|AIRLINE|TYPE|RWY|APT|CALLSIGN
# DIRQ filters: arr -> arrivals only, dep -> departures only, all -> both.
PT_AWK_AEROAPI='
function emit(o, g,   tag, k1, k2, k3, rk, okey, t, mn, fl, cs, al, ty, rw, ob, ap) {
    if (g == "arrivals" || g == "scheduled_arrivals") {
        if (DIRQ == "dep") return
        tag = "A"; k1 = "actual_on"; k2 = "estimated_on"; k3 = "scheduled_on"
        rk = "actual_runway_on"; okey = "origin"
    } else if (g == "departures" || g == "scheduled_departures") {
        if (DIRQ == "arr") return
        tag = "D"; k1 = "actual_off"; k2 = "estimated_off"; k3 = "scheduled_off"
        rk = "actual_runway_off"; okey = "destination"
    } else return
    t = jstr(o, k1); if (t == "") t = jstr(o, k2); if (t == "") t = jstr(o, k3)
    mn = tmin(t); if (mn < 0) return
    fl = jstr(o, "ident_iata"); if (fl == "") fl = jstr(o, "ident"); if (fl == "") return
    cs = jstr(o, "ident")
    al = jstr(o, "operator_iata"); if (al == "") al = jstr(o, "operator")
    if (al == "") al = substr(fl, 1, 2)
    ty = jstr(o, "aircraft_type"); if (ty == "") ty = "-"
    rw = jstr(o, rk); if (rw == "") rw = "-"
    ob = jobj(o, okey)
    ap = jstr(ob, "code_iata"); if (ap == "") ap = jstr(ob, "code"); if (ap == "") ap = "-"
    printf "%09d|%s|%s|%s|%s|%s|%s|%s\n", mn, tag, fl, al, ty, rw, ap, cs
}
'

PT_AWK_AVSTACK='
function emit(o,   st, seg, oth, t, mn, fo, fl, cs, ao, al, aco, ty, ap) {
    st = jstr(o, "flight_status")
    if (st == "" || st == "cancelled") return
    seg = jobj(o, SEG); if (seg == "") return
    t = jstr(seg, "actual"); if (t == "") t = jstr(seg, "estimated")
    if (t == "") t = jstr(seg, "scheduled")
    mn = tmin(t); if (mn < 0) return
    fo = jobj(o, "flight")
    fl = jstr(fo, "iata"); if (fl == "") fl = jstr(fo, "icao"); if (fl == "") return
    cs = jstr(fo, "icao")
    ao = jobj(o, "airline"); al = jstr(ao, "name"); if (al == "") al = "-"
    aco = jobj(o, "aircraft"); ty = jstr(aco, "iata"); if (ty == "") ty = "-"
    oth = jobj(o, OTH)
    ap = jstr(oth, "iata"); if (ap == "") ap = jstr(oth, "icao"); if (ap == "") ap = "-"
    printf "%09d|%s|%s|%s|%s|%s|%s|%s\n", mn, TAG, fl, al, ty, "-", ap, cs
}
'

# OpenSky /states/all returns arrays, not objects: {"states":[[icao24,
# callsign, origin_country, t_pos, t_contact, lon, lat, ...], ...]}.
# Elements are comma-split with string awareness (country names may
# contain commas); callsign is field 2, lon 6, lat 7.
PT_AWK_OPENSKY='
function rnd(x) { return x >= 0 ? int(x + 0.5) : -int(-x + 0.5) }
function state(s,   m, j, c2, el, k, cs, lon, lat) {
    k = 0; el = ""; ins2 = 0; esc2 = 0
    m = length(s)
    for (j = 1; j <= m; j++) {
        c2 = substr(s, j, 1)
        if (ins2) {
            if (esc2) esc2 = 0
            else if (c2 == "\\") esc2 = 1
            else if (c2 == "\"") ins2 = 0
            else el = el c2
            continue
        }
        if (c2 == "\"") { ins2 = 1; continue }
        if (c2 == ",") { k++; f[k] = el; el = ""; continue }
        el = el c2
    }
    k++; f[k] = el
    if (k < 7) return
    cs = f[2]; gsub(/^ +/, "", cs); gsub(/ +$/, "", cs)
    if (cs == "" || f[6] !~ /[0-9]/ || f[7] !~ /[0-9]/) return
    lon = f[6] + 0; lat = f[7] + 0
    printf "%s|%d|%d\n", toupper(cs), \
        rnd((lon - LO) * 60 * cos(LA * 3.141592653589793 / 180)), \
        rnd((lat - LA) * 60)
}
{ buf = buf $0 }
END {
    n = length(buf); adep = 0; ins = 0; esc = 0; st = 0
    for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (ins) {
            if (esc) esc = 0
            else if (c == "\\") esc = 1
            else if (c == "\"") ins = 0
            continue
        }
        if (c == "\"") { ins = 1; continue }
        if (c == "[") { adep++; if (adep == 2) st = i + 1; continue }
        if (c == "]") { if (adep == 2 && st) state(substr(buf, st, i - st)); adep--; continue }
    }
}
'

PT_AWK_ADSB='
function rnd(x) { return x >= 0 ? int(x + 0.5) : -int(-x + 0.5) }
function emit(o,   cs, la, lo, dx, dy) {
    cs = jstr(o, "flight"); gsub(/^ +/, "", cs); gsub(/ +$/, "", cs)
    la = jnum(o, "lat"); lo = jnum(o, "lon")
    if (cs == "" || la == "" || lo == "") return
    dy = (la - LA) * 60
    dx = (lo - LO) * 60 * cos(LA * 3.141592653589793 / 180)
    printf "%s|%d|%d\n", toupper(cs), rnd(dx), rnd(dy)
}
'

# The FREE keyless board: derive arrivals/departures from live ADS-B.
# Geometry decides direction (track vs bearing to the airport), times are
# distance/groundspeed estimates, and on low final/climbout the runway is
# estimated from the track (runway numbers are headings / 10). Airline
# names resolve from the ICAO callsign prefix. FR/TO stays unknown ("-").
PT_AWK_ADSB_BOARD='
function rnd(x) { return x >= 0 ? int(x + 0.5) : -int(-x + 0.5) }
function emit(o,   cs, la, lo, gs, tr, ab, dx, dy, dist, brg, d, tag, mn, rw, al, ty) {
    if (jstr(o, "alt_baro") == "ground") return
    cs = jstr(o, "flight"); gsub(/^ +/, "", cs); gsub(/ +$/, "", cs)
    if (cs == "") return
    la = jnum(o, "lat"); lo = jnum(o, "lon")
    gs = jnum(o, "gs");  tr = jnum(o, "track")
    ab = jnum(o, "alt_baro")
    if (la == "" || lo == "" || gs == "" || tr == "" || gs < 50) return
    dy = (la - LA) * 60
    dx = (lo - LO) * 60 * cos(LA * 3.141592653589793 / 180)
    dist = sqrt(dx * dx + dy * dy)
    if (dist < 0.5) return
    brg = atan2(-dx, -dy) * 57.29577951308232
    if (brg < 0) brg += 360
    d = tr - brg
    while (d > 180) d -= 360
    while (d < -180) d += 360
    if (d < 0) d = -d
    if (d < 70) tag = "A"
    else if (d > 110) tag = "D"
    else return
    if (DIRQ == "arr" && tag != "A") return
    if (DIRQ == "dep" && tag != "D") return
    mn = dist / gs * 60
    if (mn > 240) return
    mn = (tag == "A") ? NOW + rnd(mn) : NOW - rnd(mn)
    rw = "-"
    if (ab != "" && ab < 5000 && dist < 12) {
        rw = int((tr + 5) / 10) % 36
        if (rw == 0) rw = 36
        rw = sprintf("%02d", rw)
    }
    if (match(cs, /^[A-Z]+/)) al = substr(cs, 1, RLENGTH); else al = cs
    if (al in nmi) al = nmi[al]
    ty = jstr(o, "t"); if (ty == "") ty = "-"
    printf "%09d|%s|%s|%s|%s|%s|-|%s|%d|%d\n", \
        mn, tag, cs, al, ty, rw, cs, rnd(dx), rnd(dy)
}
'

# Same derivation from OpenSky state arrays (metric units: m, m/s).
PT_AWK_OSKY_BOARD='
function rnd(x) { return x >= 0 ? int(x + 0.5) : -int(-x + 0.5) }
function state(s,   m, j, c2, el, k, cs, la, lo, gs, tr, ab, dx, dy, dist, brg, d, tag, mn, rw, al) {
    k = 0; el = ""; ins2 = 0; esc2 = 0
    m = length(s)
    for (j = 1; j <= m; j++) {
        c2 = substr(s, j, 1)
        if (ins2) {
            if (esc2) esc2 = 0
            else if (c2 == "\\") esc2 = 1
            else if (c2 == "\"") ins2 = 0
            else el = el c2
            continue
        }
        if (c2 == "\"") { ins2 = 1; continue }
        if (c2 == ",") { k++; f[k] = el; el = ""; continue }
        el = el c2
    }
    k++; f[k] = el
    if (k < 12) return
    if (f[9] ~ /true/) return
    cs = f[2]; gsub(/^ +/, "", cs); gsub(/ +$/, "", cs)
    if (cs == "" || f[6] !~ /[0-9]/ || f[7] !~ /[0-9]/) return
    if (f[10] !~ /[0-9]/ || f[11] !~ /[0-9]/) return
    lo = f[6] + 0; la = f[7] + 0
    gs = f[10] * 1.94384
    tr = f[11] + 0
    ab = (f[8] ~ /[0-9]/) ? f[8] * 3.28084 : ""
    if (gs < 50) return
    dy = (la - LA) * 60
    dx = (lo - LO) * 60 * cos(LA * 3.141592653589793 / 180)
    dist = sqrt(dx * dx + dy * dy)
    if (dist < 0.5) return
    brg = atan2(-dx, -dy) * 57.29577951308232
    if (brg < 0) brg += 360
    d = tr - brg
    while (d > 180) d -= 360
    while (d < -180) d += 360
    if (d < 0) d = -d
    if (d < 70) tag = "A"
    else if (d > 110) tag = "D"
    else return
    if (DIRQ == "arr" && tag != "A") return
    if (DIRQ == "dep" && tag != "D") return
    mn = dist / gs * 60
    if (mn > 240) return
    mn = (tag == "A") ? NOW + rnd(mn) : NOW - rnd(mn)
    rw = "-"
    if (ab != "" && ab < 5000 && dist < 12) {
        rw = int((tr + 5) / 10) % 36
        if (rw == 0) rw = 36
        rw = sprintf("%02d", rw)
    }
    if (match(cs, /^[A-Z]+/)) al = substr(cs, 1, RLENGTH); else al = cs
    if (al in nmi) al = nmi[al]
    printf "%09d|%s|%s|%s|%s|%s|-|%s|%d|%d\n", \
        mn, tag, cs, al, "-", rw, cs, rnd(dx), rnd(dy)
}
{ buf = buf $0 }
END {
    n = length(buf); adep = 0; ins = 0; esc = 0; st = 0
    for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (ins) {
            if (esc) esc = 0
            else if (c == "\\") esc = 1
            else if (c == "\"") ins = 0
            continue
        }
        if (c == "\"") { ins = 1; continue }
        if (c == "[") { adep++; if (adep == 2) st = i + 1; continue }
        if (c == "]") { if (adep == 2 && st) state(substr(buf, st, i - st)); adep--; continue }
    }
}
'

# Windowing/dedupe/format: raw sorted lines
# (MIN|DIR|FLIGHT|AIRLINE|TYPE|RWY|APT|CALLSIGN[|DX|DY]) ->
# DIR|HH:MM|FLIGHT|AIRLINE|TYPE|RWY|APT|DX|DY|CALLSIGN
PT_AWK_POST='
NR == FNR { if ($0 !~ /^#/ && $1 != "") nm[$1] = $3; next }
{
    key = $2 "|" $3
    if (seen[key]++) next
    mn = $1 + 0
    lo = (WIN == "split") ? NOW - 180 : NOW - 45
    hi = NOW + 720
    if (mn < lo || mn > hi) next
    al = $4; if (al in nm) al = nm[al]
    lm = (mn + TZ) % 1440; if (lm < 0) lm += 1440
    line = sprintf("%s|%02d:%02d|%s|%s|%s|%s|%s|%s|%s|%s", \
        $2, int(lm / 60), lm % 60, $3, toupper(al), $5, $6, $7, $9, $10, $8)
    if (WIN == "split") {
        if (mn < NOW) pa[++pn] = line
        else if (fn < LIM) fu[++fn] = line
    } else if (on < LIM) out[++on] = line
}
END {
    if (WIN == "split") {
        s = pn - LIM + 1; if (s < 1) s = 1
        for (i = s; i <= pn; i++) print pa[i]
        for (i = 1; i <= fn; i++) print fu[i]
    } else for (i = 1; i <= on; i++) print out[i]
}
'

src_finish_raw() { # RAWFILE WINDOW LIMIT OUT
    sort "$1" > "$1.s"
    awk -F'|' -v NOW="$(now_abs_min)" -v WIN="$2" -v LIM="$3" \
        -v TZ="$(tz_offset_min)" "$PT_AWK_POST" "$PT_AIRLINES" "$1.s" > "$4"
    rm -f "$1" "$1.s"
    [ -s "$4" ]
}

# ------------------------------------------------------------ sources ------

src_aeroapi() { # KEY DIR WINDOW LIMIT OUT
    # One combined /flights query is billed once and carries all four
    # groups, so its raw JSON is cached per airport and reused for every
    # board direction. When the budget is spent or the network is down,
    # a stale copy is served instead (PT_SRC_STALE = age in minutes).
    JC="$PT_CACHE_DIR/$AIRPORT.aeroapi.json"
    now="$(date +%s)"
    jts="$(cat "$JC.t" 2>/dev/null)"
    case "$jts" in ''|*[!0-9]*) jts=0 ;; esac
    age=$(( now - jts ))

    if [ ! -s "$JC" ] || [ $age -ge "$CACHE" ]; then
        if aero_allow; then
            if pt_https_get \
                "$AEROAPI_BASE/airports/$AIRPORT/flights?max_pages=1" \
                "$PT_TMP.json" "x-apikey: $1" \
               && grep -q '"ident' "$PT_TMP.json"; then
                aero_count
                mv "$PT_TMP.json" "$JC"
                echo "$now" > "$JC.t"
                age=0
            else
                rm -f "$PT_TMP.json"
                log "aeroapi fetch failed for $AIRPORT"
            fi
        fi
    fi
    [ -s "$JC" ] || return 1
    [ $age -gt "$CACHE" ] && PT_SRC_STALE=$(( age / 60 ))

    RAW="$PT_TMP.raw"
    awk -v DIRQ="$2" \
        "$PT_AWK_JSON $PT_AWK_SCAN_GROUPED $PT_AWK_AEROAPI" "$JC" > "$RAW"
    src_finish_raw "$RAW" "$3" "$4" "$5"
}

# ------------------------------------------------- aviationstack budget ----
# The aviationstack free tier allows roughly 100 requests per month.

PT_AVS_USAGE="$PT_HOME/avstack.usage"

avstack_allow() {
    AVS_MKEY="$(date +%Y-%m)"
    AMON=""; AMC=""
    if [ -f "$PT_AVS_USAGE" ]; then
        read -r AMON AMC < "$PT_AVS_USAGE" 2>/dev/null
    fi
    [ "$AMON" = "$AVS_MKEY" ] || AMC=0
    case "$AMC" in ''|*[!0-9]*) AMC=0;; esac
    if [ "$AMC" -ge "$AVSTACK_MONTH" ]; then
        log "aviationstack budget reached ($AMC/$AVSTACK_MONTH this month)"
        return 1
    fi
    return 0
}

avstack_count() {
    echo "$AVS_MKEY $(( AMC + 1 ))" > "$PT_AVS_USAGE" 2>/dev/null
}

src_avstack() { # KEY DIR WINDOW LIMIT OUT
    case "$2" in
        arr) SIDES="arr" ;;
        dep) SIDES="dep" ;;
        *)   SIDES="arr dep" ;;
    esac
    RAW="$PT_TMP.raw"; : > "$RAW"
    for s in $SIDES; do
        if [ "$s" = "arr" ]; then
            TAG=A; SEG=arrival; OTH=departure; FK=arr_iata
        else
            TAG=D; SEG=departure; OTH=arrival; FK=dep_iata
        fi
        avstack_allow || break
        pt_fetch "$AVSTACK_BASE/flights?access_key=$1&limit=100&$FK=$AIRPORT" \
            "$PT_TMP.json" || continue
        avstack_count
        awk -v TAG=$TAG -v SEG=$SEG -v OTH=$OTH \
            "$PT_AWK_JSON $PT_AWK_SCAN $PT_AWK_AVSTACK" "$PT_TMP.json" >> "$RAW"
    done
    rm -f "$PT_TMP.json"
    src_finish_raw "$RAW" "$3" "$4" "$5"
}

# ------------------------------------------------ keyless raw fetchers -----
# Both hold a 10-second raw-response cache: polite to the aggregators,
# matches OpenSky's anonymous data resolution, and lets the derived board
# and the traffic map share one download.

adsb_fetch_raw() { # LAT LON OUT
    mkdir -p "$PT_CACHE_DIR" 2>/dev/null
    RC="$PT_CACHE_DIR/$AIRPORT.adsb.json"
    rts="$(cat "$RC.t" 2>/dev/null)"
    case "$rts" in ''|*[!0-9]*) rts=0 ;; esac
    if [ -s "$RC" ] && [ $(( $(date +%s) - rts )) -lt 10 ]; then
        cp "$RC" "$3"
        return 0
    fi
    R=$(( RANGE * 2 ))
    [ $R -lt 60 ]  && R=60
    [ $R -gt 250 ] && R=250
    # Resolution order: test override, then the config file, then default.
    for base in ${PT_ADSB_BASES:-${ADSB_URLS:-$ADSB_DEFAULT}}; do
        if pt_https_get "$base/point/$1/$2/$R" "$3" \
           && grep -q '"ac"' "$3"; then
            cp "$3" "$RC" 2>/dev/null && date +%s > "$RC.t"
            return 0
        fi
        log "adsb source failed: $base"
    done
    return 1
}

opensky_fetch_raw() { # LAT LON OUT
    [ "$OPENSKY_DAY" -gt 0 ] || return 1
    mkdir -p "$PT_CACHE_DIR" 2>/dev/null
    RC="$PT_CACHE_DIR/$AIRPORT.osky.json"
    rts="$(cat "$RC.t" 2>/dev/null)"
    case "$rts" in ''|*[!0-9]*) rts=0 ;; esac
    if [ -s "$RC" ] && [ $(( $(date +%s) - rts )) -lt 10 ]; then
        cp "$RC" "$3"
        return 0
    fi
    opensky_allow || return 1
    R=$(( RANGE * 2 ))
    [ $R -lt 60 ]  && R=60
    [ $R -gt 250 ] && R=250
    BBOX="$(awk -v la="$1" -v lo="$2" -v r="$R" 'BEGIN {
        dla = r / 60.0
        c = cos(la * 3.141592653589793 / 180); if (c < 0.1) c = 0.1
        dlo = r / (60.0 * c)
        printf "lamin=%.4f&lomin=%.4f&lamax=%.4f&lomax=%.4f", \
            la - dla, lo - dlo, la + dla, lo + dlo }')"
    if pt_https_get "$OPENSKY_BASE/states/all?$BBOX" "$3" \
       && grep -q '"states"' "$3"; then
        opensky_count
        cp "$3" "$RC" 2>/dev/null && date +%s > "$RC.t"
        return 0
    fi
    log "opensky source failed"
    return 1
}

# The free keyless flight source: a live board derived from ADS-B.
src_adsb_flights() { # _ DIR WINDOW LIMIT OUT
    coords="$(apt_coords "$AIRPORT")" || {
        log "adsb source needs $AIRPORT in data/airports.txt"; return 1; }
    set -- "$coords" "$2" "$3" "$4" "$5"
    LATLON="$1"
    NOWMIN="$(now_abs_min)"
    RAW="$PT_TMP.raw"; : > "$RAW"
    if adsb_fetch_raw $LATLON "$PT_TMP.acjson"; then
        awk -v DIRQ="$2" -v NOW="$NOWMIN" \
            -v LA="${LATLON% *}" -v LO="${LATLON#* }" \
            "$PT_AWK_JSON $PT_AWK_NMI $PT_AWK_SCAN $PT_AWK_ADSB_BOARD" \
            "$PT_AIRLINES" "$PT_TMP.acjson" > "$RAW"
    elif opensky_fetch_raw $LATLON "$PT_TMP.acjson"; then
        awk -v DIRQ="$2" -v NOW="$NOWMIN" \
            -v LA="${LATLON% *}" -v LO="${LATLON#* }" \
            "$PT_AWK_NMI $PT_AWK_OSKY_BOARD" \
            "$PT_AIRLINES" "$PT_TMP.acjson" > "$RAW"
    else
        rm -f "$PT_TMP.acjson"
        return 1
    fi
    rm -f "$PT_TMP.acjson"
    src_finish_raw "$RAW" "$3" "$4" "$5"
}

src_try() { # IDX DIR WINDOW LIMIT OUT - run one configured source
    eval "spec=\$SOURCE$1"
    [ -n "$spec" ] || return 1
    PT_SRC_TYPE="${spec%%,*}"
    arg="${spec#*,}"; [ "$arg" = "$spec" ] && arg=""
    case "$PT_SRC_TYPE" in
        adsb)          src_adsb_flights "" "$2" "$3" "$4" "$5" ;;
        aeroapi)       src_aeroapi "$arg" "$2" "$3" "$4" "$5" ;;
        aviationstack) src_avstack "$arg" "$2" "$3" "$4" "$5" ;;
        *) log "unknown source type: $PT_SRC_TYPE"; return 1 ;;
    esac && [ -s "$5" ] && grep -q '^[AD]|' "$5"
}

# src_fetch DIR WINDOW LIMIT OUT - cached, failing over across sources.
# Sets PT_SRC_USED (1..3, 0 = none worked) and PT_SRC_STALE (minutes, when
# only outdated data could be served - better than an empty board).
src_fetch() {
    PT_SRC_USED=0
    PT_SRC_STALE=0
    mkdir -p "$PT_CACHE_DIR" 2>/dev/null
    CF="$PT_CACHE_DIR/$AIRPORT.$1.$2.$3"
    cts="$(sed -n 's/^#T //p' "$CF" 2>/dev/null | head -n 1)"
    case "$cts" in ''|*[!0-9]*) cts=0 ;; esac
    cage=$(( $(date +%s) - cts ))
    if [ -f "$CF" ] && [ $cage -lt "$CACHE" ]; then
        grep -v '^#' "$CF" > "$4"
        PT_SRC_USED="$(sed -n 's/^#S //p' "$CF" | head -n 1)"
        case "$PT_SRC_USED" in ''|*[!0-9]*) PT_SRC_USED=1 ;; esac
        [ -s "$4" ] && return 0
    fi
    i=0
    while [ $i -lt 3 ]; do
        i=$(( i + 1 ))
        if src_try $i "$1" "$2" "$3" "$4"; then
            PT_SRC_USED=$i
            if [ "$PT_SRC_STALE" -eq 0 ]; then
                { echo "#T $(date +%s)"; echo "#S $i"; cat "$4"; } > "$CF" 2>/dev/null
            fi
            return 0
        fi
        eval "spec=\$SOURCE$i"
        [ -n "$spec" ] && log "source $i (${spec%%,*}) failed for $AIRPORT/$1"
    done
    # Every source failed: serve the expired line cache rather than nothing.
    if [ -f "$CF" ] && grep -q '^[AD]|' "$CF"; then
        grep -v '^#' "$CF" > "$4"
        PT_SRC_USED="$(sed -n 's/^#S //p' "$CF" | head -n 1)"
        case "$PT_SRC_USED" in ''|*[!0-9]*) PT_SRC_USED=1 ;; esac
        PT_SRC_STALE=$(( cage / 60 ))
        log "all sources failed - serving ${PT_SRC_STALE}min old cache"
        return 0
    fi
    return 1
}

src_count() { # number of configured sources
    _n=0
    for _s in "$SOURCE1" "$SOURCE2" "$SOURCE3"; do
        [ -n "$_s" ] && _n=$(( _n + 1 ))
    done
    echo $_n
}

# apt_lookup_api CODE - resolve an airport missing from the local database
# via AeroAPI (needs an aeroapi source configured) and append it to
# data/airports.txt so the traffic map gets coordinates. Prints the line.
apt_lookup_api() {
    key=""
    i=0
    while [ $i -lt 3 ]; do
        i=$(( i + 1 ))
        eval "spec=\$SOURCE$i"
        case "$spec" in aeroapi,*) key="${spec#aeroapi,}"; break ;; esac
    done
    [ -n "$key" ] || return 1
    aero_allow || return 1
    pt_https_get "$AEROAPI_BASE/airports/$1" "$PT_TMP.apt" \
        "x-apikey: $key" || { rm -f "$PT_TMP.apt"; return 1; }
    aero_count
    line="$(awk "$PT_AWK_JSON"'
        { buf = buf $0 }
        END {
            ia = jstr(buf, "code_iata"); ic = jstr(buf, "code_icao")
            la = jnum(buf, "latitude");  lo = jnum(buf, "longitude")
            ci = jstr(buf, "city");      na = jstr(buf, "name")
            if ((ia == "" && ic == "") || la == "" || lo == "") exit
            printf "%s|%s|%s|%s|%s|%s\n", ia, ic, la, lo, ci, na
        }' "$PT_TMP.apt")"
    rm -f "$PT_TMP.apt"
    [ -n "$line" ] || return 1
    echo "$line" >> "$PT_AIRPORTS"
    echo "$line"
}

# --------------------------------------------------- opensky budget --------
# OpenSky's anonymous REST API allows roughly 400 credits per day (a
# small bounding box costs 1 credit per query). Calls are capped at
# OPENSKY_DAY per day via a persistent counter.

PT_OSKY_USAGE="$PT_HOME/opensky.usage"

opensky_allow() {
    OSKY_DKEY="$(date +%Y-%m-%d)"
    ODAY=""; ODC=""
    if [ -f "$PT_OSKY_USAGE" ]; then
        read -r ODAY ODC < "$PT_OSKY_USAGE" 2>/dev/null
    fi
    [ "$ODAY" = "$OSKY_DKEY" ] || ODC=0
    case "$ODC" in ''|*[!0-9]*) ODC=0;; esac
    if [ "$ODC" -ge "$OPENSKY_DAY" ]; then
        log "opensky budget reached ($ODC/$OPENSKY_DAY today)"
        return 1
    fi
    return 0
}

opensky_count() {
    echo "$OSKY_DKEY $(( ODC + 1 ))" > "$PT_OSKY_USAGE" 2>/dev/null
}

# src_positions OUT - live positions near AIRPORT as CS|DX|DY lines.
# Sources: the re-api aggregators (adsb.fi, adsb.lol) first, then the
# OpenSky Network. The raw fetchers hold a shared 10-second cache.
src_positions() {
    OUTPOS="$1"
    : > "$OUTPOS"
    coords="$(apt_coords "$AIRPORT")" || { log "no coords for $AIRPORT (data/airports.txt)"; return 1; }
    set -- $coords
    if adsb_fetch_raw "$1" "$2" "$PT_TMP.acjson"; then
        awk -v LA="$1" -v LO="$2" \
            "$PT_AWK_JSON $PT_AWK_SCAN $PT_AWK_ADSB" "$PT_TMP.acjson" > "$OUTPOS"
        rm -f "$PT_TMP.acjson"
        return 0
    fi
    if opensky_fetch_raw "$1" "$2" "$PT_TMP.acjson"; then
        awk -v LA="$1" -v LO="$2" "$PT_AWK_OPENSKY" "$PT_TMP.acjson" > "$OUTPOS"
        rm -f "$PT_TMP.acjson"
        return 0
    fi
    rm -f "$PT_TMP.acjson"
    return 1
}
