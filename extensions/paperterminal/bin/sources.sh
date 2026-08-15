#!/bin/sh
# PaperTerminal - direct public-API flight data, no proxy involved.
# Sourced by board.sh / radar.sh / nettest.sh after common.sh.
#
# Sources (paperterminal.conf, tried in order until one delivers):
#   SOURCE1=aeroapi,YOUR_KEY        FlightAware AeroAPI v4 (runway data)
#   SOURCE2=aviationstack,YOUR_KEY  aviationstack (no runway data)
#
# Live positions for the traffic map come straight from open ADS-B
# aggregators (api.adsb.lol, opendata.adsb.fi) - no key needed.
#
# All JSON is parsed on-device by a small awk object scanner that tracks
# brace depth and string state, so it does not depend on key order or
# formatting. Responses are cached in /tmp to protect API quotas.

PT_AIRPORTS="$PT_HOME/data/airports.txt"
PT_AIRLINES="$PT_HOME/data/airlines.txt"
PT_CACHE_DIR="/tmp/paperterminal.cache"

AEROAPI_BASE="${PT_AEROAPI_BASE:-https://aeroapi.flightaware.com/aeroapi}"
AVSTACK_BASE="${PT_AVSTACK_BASE:-http://api.aviationstack.com/v1}"
ADSB_BASES="${PT_ADSB_BASES:-https://api.adsb.lol/v2 https://opendata.adsb.fi/api/v2}"

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

apt_coords() { # apt_coords CODE -> "LAT LON", fails if unknown
    [ -f "$PT_AIRPORTS" ] || return 1
    line="$(grep -i "^$1|" "$PT_AIRPORTS" 2>/dev/null | head -n 1 | tr -d '\r')"
    [ -n "$line" ] || return 1
    echo "$line" | awk -F'|' '{print $2, $3}'
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

# Raw parser output: SORTKEY|DIR|FLIGHT|AIRLINE|TYPE|RWY|APT|CALLSIGN
PT_AWK_AEROAPI='
function emit(o,   t, mn, fl, cs, al, ty, rw, ob, ap) {
    t = jstr(o, K1); if (t == "") t = jstr(o, K2); if (t == "") t = jstr(o, K3)
    mn = tmin(t); if (mn < 0) return
    fl = jstr(o, "ident_iata"); if (fl == "") fl = jstr(o, "ident"); if (fl == "") return
    cs = jstr(o, "ident")
    al = jstr(o, "operator_iata"); if (al == "") al = jstr(o, "operator")
    if (al == "") al = substr(fl, 1, 2)
    ty = jstr(o, "aircraft_type"); if (ty == "") ty = "-"
    rw = jstr(o, RK); if (rw == "") rw = "-"
    ob = jobj(o, OKEY)
    ap = jstr(ob, "code_iata"); if (ap == "") ap = jstr(ob, "code"); if (ap == "") ap = "-"
    printf "%09d|%s|%s|%s|%s|%s|%s|%s\n", mn, TAG, fl, al, ty, rw, ap, cs
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

# Windowing/dedupe/format: raw sorted lines ->
# DIR|HH:MM|FLIGHT|AIRLINE|TYPE|RWY|APT|DX|DY|CALLSIGN (DX/DY empty here)
PT_AWK_POST='
NR == FNR { if ($0 !~ /^#/) nm[$1] = $2; next }
{
    key = $2 "|" $3
    if (seen[key]++) next
    mn = $1 + 0
    lo = (WIN == "split") ? NOW - 180 : NOW - 45
    hi = NOW + 720
    if (mn < lo || mn > hi) next
    al = $4; if (al in nm) al = nm[al]
    lm = (mn + TZ) % 1440; if (lm < 0) lm += 1440
    line = sprintf("%s|%02d:%02d|%s|%s|%s|%s|%s|||%s", \
        $2, int(lm / 60), lm % 60, $3, toupper(al), $5, $6, $7, $8)
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
    CURLBIN="$(pt_curl_bin)" || { log "aeroapi needs lib/curl"; return 1; }
    case "$2" in
        arr) GROUPS="arrivals scheduled_arrivals" ;;
        dep) GROUPS="departures scheduled_departures" ;;
        *)   GROUPS="arrivals scheduled_arrivals departures scheduled_departures" ;;
    esac
    RAW="$PT_TMP.raw"; : > "$RAW"
    for g in $GROUPS; do
        case "$g" in
            arrivals|scheduled_arrivals)
                TAG=A; K1=actual_on; K2=estimated_on; K3=scheduled_on
                RK=actual_runway_on; OKEY=origin ;;
            *)
                TAG=D; K1=actual_off; K2=estimated_off; K3=scheduled_off
                RK=actual_runway_off; OKEY=destination ;;
        esac
        "$CURLBIN" -sS --connect-timeout 15 -m 40 --cacert "$PT_CACERT" \
            -H "x-apikey: $1" -A "PaperTerminal/$PT_VERSION" \
            -o "$PT_TMP.json" \
            "$AEROAPI_BASE/airports/$AIRPORT/flights/$g?max_pages=1" \
            2>/dev/null || continue
        awk -v TAG=$TAG -v K1=$K1 -v K2=$K2 -v K3=$K3 -v RK=$RK -v OKEY=$OKEY \
            "$PT_AWK_JSON $PT_AWK_SCAN $PT_AWK_AEROAPI" "$PT_TMP.json" >> "$RAW"
    done
    rm -f "$PT_TMP.json"
    src_finish_raw "$RAW" "$3" "$4" "$5"
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
        pt_fetch "$AVSTACK_BASE/flights?access_key=$1&limit=100&$FK=$AIRPORT" \
            "$PT_TMP.json" || continue
        awk -v TAG=$TAG -v SEG=$SEG -v OTH=$OTH \
            "$PT_AWK_JSON $PT_AWK_SCAN $PT_AWK_AVSTACK" "$PT_TMP.json" >> "$RAW"
    done
    rm -f "$PT_TMP.json"
    src_finish_raw "$RAW" "$3" "$4" "$5"
}

src_try() { # IDX DIR WINDOW LIMIT OUT - run one configured source
    eval "spec=\$SOURCE$1"
    [ -n "$spec" ] || return 1
    PT_SRC_TYPE="${spec%%,*}"
    arg="${spec#*,}"; [ "$arg" = "$spec" ] && arg=""
    case "$PT_SRC_TYPE" in
        aeroapi)       src_aeroapi "$arg" "$2" "$3" "$4" "$5" ;;
        aviationstack) src_avstack "$arg" "$2" "$3" "$4" "$5" ;;
        *) log "unknown source type: $PT_SRC_TYPE"; return 1 ;;
    esac && [ -s "$5" ] && grep -q '^[AD]|' "$5"
}

# src_fetch DIR WINDOW LIMIT OUT - cached, failing over across sources.
# Sets PT_SRC_USED (1..3, 0 = none worked).
src_fetch() {
    PT_SRC_USED=0
    mkdir -p "$PT_CACHE_DIR" 2>/dev/null
    CF="$PT_CACHE_DIR/$AIRPORT.$1.$2.$3"
    if [ -f "$CF" ]; then
        cts="$(sed -n 's/^#T //p' "$CF" | head -n 1)"
        case "$cts" in ''|*[!0-9]*) cts=0 ;; esac
        if [ $(( $(date +%s) - cts )) -lt "$CACHE" ]; then
            grep -v '^#' "$CF" > "$4"
            PT_SRC_USED="$(sed -n 's/^#S //p' "$CF" | head -n 1)"
            case "$PT_SRC_USED" in ''|*[!0-9]*) PT_SRC_USED=1 ;; esac
            [ -s "$4" ] && return 0
        fi
    fi
    i=0
    while [ $i -lt 3 ]; do
        i=$(( i + 1 ))
        if src_try $i "$1" "$2" "$3" "$4"; then
            PT_SRC_USED=$i
            { echo "#T $(date +%s)"; echo "#S $i"; cat "$4"; } > "$CF" 2>/dev/null
            return 0
        fi
        eval "spec=\$SOURCE$i"
        [ -n "$spec" ] && log "source $i (${spec%%,*}) failed for $AIRPORT/$1"
    done
    return 1
}

src_count() { # number of configured sources
    _n=0
    for _s in "$SOURCE1" "$SOURCE2" "$SOURCE3"; do
        [ -n "$_s" ] && _n=$(( _n + 1 ))
    done
    echo $_n
}

# src_positions OUT - live ADS-B positions near AIRPORT as CS|DX|DY lines.
src_positions() {
    OUTPOS="$1"
    : > "$OUTPOS"
    coords="$(apt_coords "$AIRPORT")" || { log "no coords for $AIRPORT (data/airports.txt)"; return 1; }
    CURLBIN="$(pt_curl_bin)" || { log "adsb needs lib/curl"; return 1; }
    set -- $coords
    R=$(( RANGE * 2 ))
    [ $R -lt 60 ]  && R=60
    [ $R -gt 250 ] && R=250
    for base in $ADSB_BASES; do
        if "$CURLBIN" -sS --connect-timeout 10 -m 25 --cacert "$PT_CACERT" \
            -A "PaperTerminal/$PT_VERSION" -o "$PT_TMP.adsb" \
            "$base/point/$1/$2/$R" 2>/dev/null \
           && grep -q '"ac"' "$PT_TMP.adsb"; then
            awk -v LA="$1" -v LO="$2" \
                "$PT_AWK_JSON $PT_AWK_SCAN $PT_AWK_ADSB" "$PT_TMP.adsb" > "$OUTPOS"
            rm -f "$PT_TMP.adsb"
            return 0
        fi
        log "adsb source failed: $base"
    done
    rm -f "$PT_TMP.adsb"
    return 1
}
