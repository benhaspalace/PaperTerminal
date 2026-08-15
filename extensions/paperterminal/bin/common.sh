#!/bin/sh
# PaperTerminal - shared helpers.
# Target: Kindle 3 Keyboard (busybox ash). Strictly POSIX, no bashisms,
# no external tools beyond sed/grep/tr/head/date/wget/eips.

PATH="/usr/sbin:/usr/bin:/sbin:/bin:$PATH"

PT_BIN="$(cd "$(dirname "$0")" && pwd)"
PT_HOME="$(dirname "$PT_BIN")"
PT_CONF="$PT_HOME/paperterminal.conf"
PT_DATA="$PT_HOME/data"
PT_LOG="$PT_HOME/paperterminal.log"
PT_TMP="/tmp/paperterminal.feed"

PT_VERSION="1.1.0"

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
    MODE="$(cfg MODE)";         [ "$MODE" = "live" ] || MODE="demo"
    FEED_URL="$(cfg FEED_URL)"; [ -n "$FEED_URL" ] || FEED_URL="http://192.168.0.10:8091/feed"
    ROWS="$(cfg ROWS)"
    case "$ROWS" in ''|*[!0-9]*) ROWS=12;; esac
    [ "$ROWS" -gt 14 ] && ROWS=14
    [ "$ROWS" -lt 1 ]  && ROWS=1
    REFRESH="$(cfg REFRESH)"
    case "$REFRESH" in ''|*[!0-9]*) REFRESH=0;; esac
}

save_conf() {
    cat > "$PT_CONF" <<EOF
# PaperTerminal settings - safe to edit over USB.
# AIRPORT : default airport code (IATA like ZRH; ICAO also fine for AeroAPI)
# MODE    : demo | live
# FEED_URL: plain-http feed endpoint (see server/feed_proxy.py in the repo)
# ROWS    : flights per board, 1..14
# REFRESH : live mode auto-redraw interval in seconds, 0 = draw once
AIRPORT=$AIRPORT
MODE=$MODE
FEED_URL=$FEED_URL
ROWS=$ROWS
REFRESH=$REFRESH
EOF
}

save_conf_defaults() {
    AIRPORT="ZRH"
    MODE="demo"
    FEED_URL="http://192.168.0.10:8091/feed"
    ROWS=12
    REFRESH=0
    save_conf
}

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" > "$PT_LOG" 2>/dev/null; }
