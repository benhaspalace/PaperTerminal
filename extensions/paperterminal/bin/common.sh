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

PT_VERSION="2.1.0"

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
    AIRPORT="$(cfg AIRPORT)";   [ -n "$AIRPORT" ]  || AIRPORT="ZRH"
    FEED_URL="$(cfg FEED_URL)"; [ -n "$FEED_URL" ] || FEED_URL="http://192.168.0.10:8091/feed"
    FEED_URL2="$(cfg FEED_URL2)"
    FEED_URL3="$(cfg FEED_URL3)"
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
}

save_conf() {
    cat > "$PT_CONF" <<EOF
# PaperTerminal settings - safe to edit over USB.
# AIRPORT  : default airport code (IATA like ZRH; ICAO also fine for AeroAPI)
# FEED_URL : your feed endpoint (see server/feed_proxy.py in the repo).
#            https:// works via the bundled lib/curl and is verified with
#            lib/cacert.pem; plain http:// works even without lib/
#            (busybox wget fallback).
# FEED_URL2/FEED_URL3 : optional backup feeds, tried in order when the
#            previous one fails (leave empty if unused)
# ROWS     : flights per board, 1..14; also the per-side count for the
#            live traffic map (ROWS before + ROWS after now)
# REFRESH  : auto-redraw interval in seconds, 0 = draw once
# RANGE    : live traffic map radius in nautical miles, 8..200
AIRPORT=$AIRPORT
FEED_URL=$FEED_URL
FEED_URL2=$FEED_URL2
FEED_URL3=$FEED_URL3
ROWS=$ROWS
REFRESH=$REFRESH
RANGE=$RANGE
EOF
}

save_conf_defaults() {
    AIRPORT="ZRH"
    FEED_URL="http://192.168.0.10:8091/feed"
    FEED_URL2=""
    FEED_URL3=""
    ROWS=12
    REFRESH=0
    RANGE=32
    save_conf
}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" > "$PT_LOG" 2>/dev/null; }

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

# pt_fetch_feed <query-string> <outfile> - failover fetch: try FEED_URL,
# FEED_URL2, FEED_URL3 in order until one returns valid flight lines.
# Sets PT_FEED_USED to the index of the feed that answered (1..3).
pt_fetch_feed() {
    PT_FEED_USED=0
    _idx=0
    for _u in "$FEED_URL" "$FEED_URL2" "$FEED_URL3"; do
        _idx=$(( _idx + 1 ))
        [ -n "$_u" ] || continue
        rm -f "$2"
        if pt_fetch "$_u?$1" "$2" && [ -s "$2" ] \
           && grep -q '^[AD]|.*|.*|.*|.*|.*|' "$2"; then
            PT_FEED_USED=$_idx
            return 0
        fi
        log "feed $_idx failed: $_u?$1"
    done
    return 1
}

# Number of configured feed URLs (for messages).
pt_feed_count() {
    _n=0
    for _u in "$FEED_URL" "$FEED_URL2" "$FEED_URL3"; do
        [ -n "$_u" ] && _n=$(( _n + 1 ))
    done
    echo $_n
}
