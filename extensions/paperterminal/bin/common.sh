#!/bin/sh
# PaperTerminal - shared helpers.
# Target: Kindle 3 Keyboard (busybox ash). Strictly POSIX, no bashisms,
# no external tools beyond sed/grep/tr/head/date/wget/eips.

PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PT_BIN="$(cd "$(dirname "$0")" && pwd)"
PT_HOME="$(dirname "$PT_BIN")"
PT_CONF="$PT_HOME/paperterminal.conf"
PT_LIB="$PT_HOME/lib"
PT_LOG="$PT_HOME/paperterminal.log"
PT_TMP="/tmp/paperterminal.feed"

# Bundled HTTPS stack: statically linked modern curl (OpenSSL inside) and
# the Mozilla CA bundle. The Kindle's own curl/openssl/wget are far too
# old for today's TLS and are deliberately not used when these exist.
PT_CURL="$PT_LIB/curl"
PT_CACERT="$PT_LIB/cacert.pem"
PT_RAMCURL="/var/tmp/paperterminal-curl"
PT_EVKEY="$PT_LIB/evkey"
PT_RAMEVKEY="/var/tmp/paperterminal-evkey"

PT_VERSION="4.0.2"

# ---------------------------------------------------------------- screen ---
# Kindle 3: 600x800 e-ink. eips draws text on a 50 col x 40 row grid
# (12x20 px cells). Keep every line within columns 1..48.

HRULE="================================================"
LRULE="------------------------------------------------"

cls() {
    # double clear knocks down e-ink ghosting from the previous screen
    eips -c >/dev/null 2>&1
    eips -c >/dev/null 2>&1
}

say() { # say <col> <row> <text>
    [ -n "$3" ] && eips "$1" "$2" "$3" >/dev/null 2>&1
}

say_r() { # say_r <row> <text> - right aligned at column 48
    say $(( 49 - ${#2} )) "$1" "$2"
}

splash() { # splash <line1> [line2] [line3]
    cls
    say 1 3  "PAPERTERMINAL $PT_VERSION"
    say 1 4  "$HRULE"
    say 1 7  "$1"
    [ -n "$2" ] && say 1 9  "$2"
    [ -n "$3" ] && say 1 11 "$3"
    say 1 14 "$LRULE"
    say 1 15 "PRESS ANY KEY TO GET THE MENU BACK"
}

# ---------------------------------------------------------------- config ---
# Plain KEY=VALUE file. Read with sed instead of sourcing, and strip CR so
# the file survives being edited in Windows Notepad over USB.

cfg() { sed -n "s/^$1=//p" "$PT_CONF" 2>/dev/null | head -n 1 | tr -d '\r'; }

load_conf() {
    [ -f "$PT_CONF" ] || save_conf_defaults
    AIRPORT="$(cfg AIRPORT)"; [ -n "$AIRPORT" ] || AIRPORT="ZRH"
    SOURCE1="$(cfg SOURCE1)"
    SOURCE2="$(cfg SOURCE2)"
    SOURCE3="$(cfg SOURCE3)"
    # Keyed APIs are used only when explicitly configured; out of the box
    # everything runs on the free keyless ADS-B chain.
    [ -n "$SOURCE1$SOURCE2$SOURCE3" ] || SOURCE1="adsb"
    ROWS="$(cfg ROWS)"
    case "$ROWS" in ''|*[!0-9]*) ROWS=12;; esac
    [ "$ROWS" -gt 14 ] && ROWS=14
    [ "$ROWS" -lt 1 ]  && ROWS=1
    REFRESH="$(cfg REFRESH)"
    case "$REFRESH" in ''|*[!0-9]*) REFRESH=5;; esac
    RANGE="$(cfg RANGE)"
    case "$RANGE" in ''|*[!0-9]*) RANGE=32;; esac
    [ "$RANGE" -gt 200 ] && RANGE=200
    [ "$RANGE" -lt 8 ]   && RANGE=8
    CACHE="$(cfg CACHE)"
    case "$CACHE" in ''|*[!0-9]*) CACHE=300;; esac
    AERO_DAY="$(cfg AERO_DAY)"
    case "$AERO_DAY" in ''|*[!0-9]*) AERO_DAY=6;; esac
    AERO_MONTH="$(cfg AERO_MONTH)"
    case "$AERO_MONTH" in ''|*[!0-9]*) AERO_MONTH=190;; esac
    AVSTACK_MONTH="$(cfg AVSTACK_MONTH)"
    case "$AVSTACK_MONTH" in ''|*[!0-9]*) AVSTACK_MONTH=90;; esac
    ADSB_URLS="$(cfg ADSB_URLS)"
    OPENSKY_DAY="$(cfg OPENSKY_DAY)"
    case "$OPENSKY_DAY" in ''|*[!0-9]*) OPENSKY_DAY=300;; esac
    KEY_MENU="$(cfg KEY_MENU)"; case "$KEY_MENU" in ''|*[!0-9]*) KEY_MENU=139;; esac
    KEY_BACK="$(cfg KEY_BACK)"; case "$KEY_BACK" in ''|*[!0-9]*) KEY_BACK=158;; esac
    KEY_HOME="$(cfg KEY_HOME)"; case "$KEY_HOME" in ''|*[!0-9]*) KEY_HOME=102;; esac
    KEY_UP="$(cfg KEY_UP)";     case "$KEY_UP" in ''|*[!0-9]*) KEY_UP=103;; esac
    KEY_DOWN="$(cfg KEY_DOWN)"; case "$KEY_DOWN" in ''|*[!0-9]*) KEY_DOWN=108;; esac
    KEY_SELECT="$(cfg KEY_SELECT)"; case "$KEY_SELECT" in ''|*[!0-9]*) KEY_SELECT=194;; esac
    INPUT_DEVS="$(cfg INPUT_DEVS)"
    [ -n "$INPUT_DEVS" ] || INPUT_DEVS="/dev/input/event0 /dev/input/event1 /dev/input/event2"
}

save_conf() {
    cat > "$PT_CONF" <<EOF
# PaperTerminal settings - safe to edit over USB.
# AIRPORT  : default airport code (IATA like ZRH; ICAO like LSZH also works
#            for AeroAPI; add coordinates to data/airports.txt for the map)
# SOURCE1-3: flight-data sources, tried in order until one answers.
#            TYPE or TYPE,APIKEY with TYPE one of:
#              adsb           FREE, no key (the default): live board derived
#                             from ADS-B (adsb.fi -> adsb.lol -> OpenSky).
#                             Times are estimates, FR/TO unknown, runway
#                             estimated from final-approach heading.
#              aeroapi        FlightAware AeroAPI, key required: true
#                             schedules, origins/destinations, actual
#                             runway used (needs lib/curl; budgeted, see
#                             AERO_DAY/AERO_MONTH)
#              aviationstack  aviationstack.com, key required: schedules
#                             and airline names, no runway (plain http;
#                             budgeted, see AVSTACK_MONTH)
# ROWS     : flights per board, 1..14; also the per-side count for the
#            live traffic map (ROWS before + ROWS after now)
# REFRESH  : board/map update interval in seconds (default 5), 0 = draw
#            once. Updates re-read the cache and only repaint the e-ink
#            when the content actually changed, so this does not burn
#            API budget or flash the screen needlessly.
# RANGE    : live traffic map radius in nautical miles, 8..200
# CACHE    : seconds to reuse fetched data (protects your API quota)
# AERO_DAY / AERO_MONTH : max AeroAPI queries per day / calendar month.
#            The free Personal tier is a ~USD 5 monthly credit at roughly
#            USD 0.025 per airport-flights query (~200/month); defaults
#            6/day and 190/month keep a safety margin. When the budget is
#            spent, backup sources or clearly-marked stale data are shown.
# AVSTACK_MONTH : max aviationstack requests per calendar month; their
#            free tier allows ~100/month, default 90 keeps a margin.
# ADSB_URLS: space-separated ADS-B API bases (the free adsb source and
#            the traffic map), tried in order. Empty = built-in default
#            (adsb.fi -> adsb.lol -> adsb.one -> airplanes.live).
# OPENSKY_DAY: max anonymous OpenSky Network queries per day, used as the
#            last position fallback when the ADS-B aggregators fail.
#            Anonymous OpenSky allows ~400 credits/day; default 300
#            keeps a margin. 0 disables OpenSky entirely.
# KEY_*    : keycodes for on-device navigation (see the key test screen)
AIRPORT=$AIRPORT
SOURCE1=$SOURCE1
SOURCE2=$SOURCE2
SOURCE3=$SOURCE3
ROWS=$ROWS
REFRESH=$REFRESH
RANGE=$RANGE
CACHE=$CACHE
AERO_DAY=$AERO_DAY
AERO_MONTH=$AERO_MONTH
AVSTACK_MONTH=$AVSTACK_MONTH
ADSB_URLS=$ADSB_URLS
OPENSKY_DAY=$OPENSKY_DAY
KEY_MENU=$KEY_MENU
KEY_BACK=$KEY_BACK
KEY_HOME=$KEY_HOME
KEY_UP=$KEY_UP
KEY_DOWN=$KEY_DOWN
KEY_SELECT=$KEY_SELECT
INPUT_DEVS=$INPUT_DEVS
EOF
}

save_conf_defaults() {
    AIRPORT="ZRH"
    SOURCE1="adsb"
    SOURCE2=""
    SOURCE3=""
    ROWS=12
    REFRESH=5
    RANGE=32
    CACHE=300
    AERO_DAY=6
    AERO_MONTH=190
    AVSTACK_MONTH=90
    ADSB_URLS=""
    OPENSKY_DAY=300
    KEY_MENU=139
    KEY_BACK=158
    KEY_HOME=102
    KEY_UP=103
    KEY_DOWN=108
    KEY_SELECT=194
    INPUT_DEVS="/dev/input/event0 /dev/input/event1 /dev/input/event2"
    save_conf
}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$PT_LOG" 2>/dev/null; }

# ----------------------------------------------------------------- fetch ---

# Print the path of a runnable bundled curl, or fail. /mnt/us is a FAT
# volume that firmwares often mount noexec, so if the binary cannot be
# executed in place a copy is run from /var/tmp instead.
pt_curl_bin() {
    [ -f "$PT_CURL" ] || return 1
    if "$PT_CURL" --version >/dev/null 2>&1; then
        echo "$PT_CURL"
        return 0
    fi
    if [ ! -x "$PT_RAMCURL" ] ||
       [ "$(wc -c < "$PT_CURL")" != "$(wc -c < "$PT_RAMCURL")" ]; then
        cp "$PT_CURL" "$PT_RAMCURL" 2>/dev/null && chmod 755 "$PT_RAMCURL" \
            || return 1
    fi
    "$PT_RAMCURL" --version >/dev/null 2>&1 || return 1
    echo "$PT_RAMCURL"
}

# Runnable bundled evkey (keycode reader - the K3 busybox lacks od, so
# shell-parsing input events is impossible there). Same noexec handling
# as curl: run in place, or from a /var/tmp copy. A run with no
# arguments exits 1, which doubles as the "does it execute" probe.
pt_evkey_bin() {
    [ -f "$PT_EVKEY" ] || return 1
    "$PT_EVKEY" >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        echo "$PT_EVKEY"
        return 0
    fi
    if [ ! -x "$PT_RAMEVKEY" ] ||
       [ "$(wc -c < "$PT_EVKEY")" != "$(wc -c < "$PT_RAMEVKEY")" ]; then
        cp "$PT_EVKEY" "$PT_RAMEVKEY" 2>/dev/null && chmod 755 "$PT_RAMEVKEY" \
            || return 1
    fi
    "$PT_RAMEVKEY" >/dev/null 2>&1
    if [ $? -eq 1 ]; then
        echo "$PT_RAMEVKEY"
        return 0
    fi
    return 1
}

# pt_fetch <url> <outfile> - 0 on success. Prefers the bundled curl with
# the bundled CA certificates (http and https alike); falls back to
# busybox wget, which can only manage plain http.
pt_fetch() {
    CURLBIN="$(pt_curl_bin)"
    if [ -n "$CURLBIN" ]; then
        # curl's stderr goes to the log so real failure reasons (DNS,
        # TLS, timeouts) are diagnosable from paperterminal.log
        "$CURLBIN" -sS --connect-timeout 15 -m 40 \
            --cacert "$PT_CACERT" -A "PaperTerminal/$PT_VERSION" \
            -o "$2" "$1" 2>>"$PT_LOG"
        return $?
    fi
    case "$1" in
        https://*)
            log "https needs lib/curl (missing/unrunnable): $1"
            return 1
            ;;
    esac
    # The K3 busybox wget has no timeout option, so babysit it ourselves
    # to keep a dead network from freezing the board for minutes.
    wget -q -O "$2" "$1" 2>/dev/null &
    wpid=$!
    n=0
    while kill -0 "$wpid" 2>/dev/null; do
        n=$(( n + 1 ))
        if [ $n -gt 25 ]; then
            kill "$wpid" 2>/dev/null
            break
        fi
        sleep 1
    done
    wait "$wpid" 2>/dev/null
    [ -s "$2" ]
}

# Crash diagnosis: call from long-running entry points to capture all
# stderr into the log (kept small).
pt_capture_errors() {
    if [ -f "$PT_LOG" ] && [ "$(wc -c < "$PT_LOG")" -gt 16000 ]; then
        tail -n 40 "$PT_LOG" > "$PT_LOG.t" 2>/dev/null && mv "$PT_LOG.t" "$PT_LOG"
    fi
    exec 2>>"$PT_LOG"
}
