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

PT_VERSION="3.2.1"

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
    [ -n "$SOURCE1$SOURCE2$SOURCE3" ] || SOURCE1="aeroapi,PUT_YOUR_KEY_HERE"
    ROWS="$(cfg ROWS)"
    case "$ROWS" in ''|*[!0-9]*) ROWS=12;; esac
    [ "$ROWS" -gt 14 ] && ROWS=14
    [ "$ROWS" -lt 1 ]  && ROWS=1
    REFRESH="$(cfg REFRESH)"
    case "$REFRESH" in ''|*[!0-9]*) REFRESH=0;; esac
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
    ADSB_URLS="$(cfg ADSB_URLS)"
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
# SOURCE1-3: public flight-data APIs, tried in order until one answers.
#            Format TYPE,APIKEY with TYPE one of:
#              aeroapi        FlightAware AeroAPI (runway data; needs lib/curl)
#              aviationstack  aviationstack.com (no runway data)
# ROWS     : flights per board, 1..14; also the per-side count for the
#            live traffic map (ROWS before + ROWS after now)
# REFRESH  : auto-redraw interval in seconds, 0 = draw once
# RANGE    : live traffic map radius in nautical miles, 8..200
# CACHE    : seconds to reuse fetched data (protects your API quota)
# AERO_DAY / AERO_MONTH : max AeroAPI queries per day / calendar month.
#            The free Personal tier is a ~USD 5 monthly credit at roughly
#            USD 0.025 per airport-flights query (~200/month); defaults
#            6/day and 190/month keep a safety margin. When the budget is
#            spent, backup sources or clearly-marked stale data are shown.
# ADSB_URLS: space-separated ADS-B API bases for the traffic map, tried
#            in order. Empty = built-in default (adsb.fi, then adsb.lol).
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
ADSB_URLS=$ADSB_URLS
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
    SOURCE1="aeroapi,PUT_YOUR_KEY_HERE"
    SOURCE2=""
    SOURCE3=""
    ROWS=12
    REFRESH=0
    RANGE=32
    CACHE=300
    AERO_DAY=6
    AERO_MONTH=190
    ADSB_URLS=""
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

# pt_fetch <url> <outfile> - 0 on success. Prefers the bundled curl with
# the bundled CA certificates (http and https alike); falls back to
# busybox wget, which can only manage plain http.
pt_fetch() {
    CURLBIN="$(pt_curl_bin)"
    if [ -n "$CURLBIN" ]; then
        "$CURLBIN" -sS --connect-timeout 15 -m 40 \
            --cacert "$PT_CACERT" -A "PaperTerminal/$PT_VERSION" \
            -o "$2" "$1" 2>/dev/null
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
