#!/bin/sh
# PaperTerminal - navigation hub.
# usage: nav.sh [menu|arr|dep|all|map|rwy|net|help|keytest]
#
# KUAL (a Java kindlet) repaints its own menu right after dispatching an
# action, racing whatever the action draws with eips - that is why plain
# one-shot scripts "lose" the screen. This hub waits for that repaint to
# settle, draws, and then owns the screen through a hardware-key loop:
#
#   BACK  -> back to the PaperTerminal menu (from the menu: exit)
#   MENU  -> open the PaperTerminal menu
#   HOME  -> exit to the Kindle UI
#   A/D/C/M/R/N/H/P -> menu shortcuts (see the menu screen)
#   any other key   -> redraw the current screen (also re-fetches data)
#
# Keys are read from the kernel input devices; the framework underneath
# still sees them too and may repaint - the loop simply redraws over it.
# Keycodes differ between models/firmwares: run the key test screen and
# adjust KEY_MENU/KEY_BACK/KEY_HOME in paperterminal.conf if needed.

. "$(dirname "$0")/common.sh"
. "$(dirname "$0")/sources.sh"

load_conf
pt_capture_errors

# Single instance: an older nav session (e.g. from before an update)
# would keep repainting the screen and eating keys underneath this one.
PT_NAVPIDF="/tmp/paperterminal.nav.pid"
OLDNAV="$(cat "$PT_NAVPIDF" 2>/dev/null)"
case "$OLDNAV" in
    ''|*[!0-9]*|"$$") ;;
    *)
        if [ -d "/proc/$OLDNAV" ]; then
            # TERM first; a shell blocked in read ignores traps until the
            # read returns, so escalate to KILL after a grace period.
            kill -TERM "$OLDNAV" 2>/dev/null
            sleep 1
            [ -d "/proc/$OLDNAV" ] && kill -KILL "$OLDNAV" 2>/dev/null
        fi ;;
esac
echo "$$" > "$PT_NAVPIDF"

log "nav start: ${1:-menu} (v$PT_VERSION)"

PT_KEYPIPE="/tmp/paperterminal.keys"
READER_PIDS=""
WATCHDOG_PID=""
SHOWPID=""

cleanup() {
    [ -n "$READER_PIDS" ] && kill $READER_PIDS 2>/dev/null
    [ -n "$WATCHDOG_PID" ] && kill $WATCHDOG_PID 2>/dev/null
    [ -n "$SHOWPID" ] && kill $SHOWPID 2>/dev/null
    rm -f "$PT_KEYPIPE"
    [ "$(cat "$PT_NAVPIDF" 2>/dev/null)" = "$$" ] && rm -f "$PT_NAVPIDF"
}
trap cleanup EXIT
trap 'exit 0' INT TERM

# --------------------------------------------------------------- input -----
# Preferred: the bundled static evkey binary prints one decimal keycode
# per key-down - needed on the K3, whose busybox has no od/hexdump.
# Fallback: raw event reads parsed with od, for devices that have it.

INPUT_MODE=""

start_input() {
    rm -f "$PT_KEYPIPE"
    mkfifo "$PT_KEYPIPE" 2>/dev/null || return 1
    DEVS=""
    for d in $INPUT_DEVS; do
        [ -r "$d" ] && DEVS="$DEVS $d"
    done
    [ -n "$DEVS" ] || return 1
    EVKEY="$(pt_evkey_bin)"
    if [ -n "$EVKEY" ]; then
        "$EVKEY" $DEVS > "$PT_KEYPIPE" &
        READER_PIDS="$!"
        INPUT_MODE="evkey"
    else
        for d in $DEVS; do
            cat "$d" > "$PT_KEYPIPE" &
            READER_PIDS="$READER_PIDS $!"
        done
        INPUT_MODE="raw"
        log "evkey not runnable - using od fallback for keys"
    fi
    log "input mode: $INPUT_MODE"
    exec 3< "$PT_KEYPIPE"
}

# Print the keycode of the next key-down event (blocks). Empty output for
# non-key events; callers loop.
getkey() {
    if [ "$INPUT_MODE" = "evkey" ]; then
        if ! read -r _k <&3; then
            sleep 1   # reader died; avoid a tight spin until watchdog fires
            return 0
        fi
        case "$_k" in ''|*[!0-9]*) ;; *) echo "$_k" ;; esac
    else
        dd bs=16 count=1 <&3 2>/dev/null | od -An -tu1 2>/dev/null | awk '
            { for (i = 1; i <= NF; i++) b[++n] = $i }
            END {
                if (n >= 16 && b[9] + b[10] * 256 == 1 && b[13] == 1)
                    print b[11] + b[12] * 256
            }'
    fi
}

# Idle watchdog: without keypresses the session ends so no readers
# linger - after 10 minutes normally, or 4 hours when a screen is
# auto-updating (so a board can serve as a wall display).
arm_watchdog() {
    [ -n "$WATCHDOG_PID" ] && kill $WATCHDOG_PID 2>/dev/null
    if [ "$REFRESH" -gt 0 ]; then IDLE=14400; else IDLE=600; fi
    ( sleep $IDLE
      kill -TERM $$ 2>/dev/null
      sleep 3
      kill -KILL $$ 2>/dev/null ) &
    WATCHDOG_PID=$!
}

# ------------------------------------------------------------- screens -----

PRESETS="ZRH GVA LHR LGW AMS CDG FRA MUC VIE BUD JFK STR"

draw_menu() {
    cls
    say 1 1  "PAPERTERMINAL $PT_VERSION"
    say_r 1  "MENU"
    say 1 2  "$HRULE"
    say 3 5  "A   ARRIVALS BOARD"
    say 3 7  "D   DEPARTURES BOARD"
    say 3 9  "C   COMBINED BOARD (ARR + DEP)"
    say 3 11 "M   LIVE TRAFFIC MAP"
    say 3 13 "R   RUNWAY DIAGRAM"
    say 3 15 "N   NETWORK SELF-TEST"
    say 3 17 "H   HELP + SETTINGS"
    say 3 19 "S   SEARCH AIRPORT (CODE, CITY, NAME)"
    say 3 21 "P   AIRPORT: $AIRPORT  (PRESS TO CYCLE)"
    say 1 23 "$LRULE"
    say 1 25 "PRESS A LETTER TO OPEN A SCREEN."
    say 1 26 "BACK = EXIT   MENU = THIS MENU   ON ANY"
    say 1 27 "SCREEN: BACK = MENU, OTHER KEY = REDRAW."
    say 1 36 "$LRULE"
    say 1 37 "KEYS DEAD? RUN KEY TEST FROM KUAL"
}

draw_keytest() {
    cls
    say 1 1 "PAPERTERMINAL - KEY TEST"
    say 1 2 "$HRULE"
    say 1 4 "PRESS KEYS; THEIR CODES APPEAR BELOW."
    say 1 5 "SET KEY_MENU / KEY_BACK / KEY_HOME IN"
    say 1 6 "paperterminal.conf TO THE CODES YOU SEE."
    say 1 7 "EXITS AFTER 20 KEYS OR 10 MIN IDLE."
    say 1 9 "$LRULE"
}

# ------------------------------------------------------------ search -------
# Type on the keyboard to search data/airports.txt by IATA/ICAO code,
# city, or airport name. Ranked: exact code, code prefix, city prefix,
# then any substring match.

key_to_char() { # standard qwerty keycodes -> lowercase char
    case "$1" in
        16) echo q;; 17) echo w;; 18) echo e;; 19) echo r;; 20) echo t;;
        21) echo y;; 22) echo u;; 23) echo i;; 24) echo o;; 25) echo p;;
        30) echo a;; 31) echo s;; 32) echo d;; 33) echo f;; 34) echo g;;
        35) echo h;; 36) echo j;; 37) echo k;; 38) echo l;; 44) echo z;;
        45) echo x;; 46) echo c;; 47) echo v;; 48) echo b;; 49) echo n;;
        50) echo m;; 57) echo " ";;
    esac
}

SRCH="/tmp/paperterminal.search"

draw_search() {
    Q=""
    SEL=0
    cls
    say 1 1 "PAPERTERMINAL"
    say_r 1 "AIRPORT SEARCH"
    say 1 2 "$HRULE"
    say 1 4 "TYPE A CODE, CITY, OR AIRPORT NAME:"
    say 1 22 "$LRULE"
    say 1 24 "UP/DOWN OR 5-WAY: CHOOSE   ENTER/CENTER:"
    say 1 25 "SET AS DEFAULT AIRPORT     DEL: ERASE"
    say 1 26 "BACK: MENU                 HOME: EXIT"
    update_search
}

update_search() {
    if [ -n "$Q" ]; then
        awk -F'|' -v q="$Q" '
            BEGIN { q = toupper(q) }
            /^#/ { next }
            {
                u1 = toupper($1); u2 = toupper($2)
                u5 = toupper($5); u6 = toupper($6)
                if (u1 == q || u2 == q)                    { print "0|" $0; next }
                if (index(u1, q) == 1 || index(u2, q) == 1){ print "1|" $0; next }
                if (index(u5, q) == 1)                     { print "2|" $0; next }
                if (index(u5, q) || index(u6, q))          { print "3|" $0; next }
            }' "$PT_AIRPORTS" | sort | head -n 6 | cut -d'|' -f2- > "$SRCH"
    else
        : > "$SRCH"
    fi
    NRES="$(grep -c '|' "$SRCH" 2>/dev/null)"
    [ "$SEL" -ge "$NRES" ] && SEL=$(( NRES - 1 ))
    [ "$SEL" -lt 0 ] && SEL=0

    say 1 6 "$(printf 'FIND: %-40.40s' "${Q}_")"
    row=9
    i=0
    while IFS='|' read -r IA IC LA LO CITY NAME; do
        [ $i -eq $SEL ] && mark=">" || mark=" "
        say 1 $row "$(printf '%s %-4s %-4s %-14.14s %-21.21s' \
            "$mark" "$IA" "$IC" "$CITY" "$NAME")"
        row=$(( row + 2 ))
        i=$(( i + 1 ))
    done < "$SRCH"
    while [ $row -le 19 ]; do
        say 1 $row "$(printf '%-47s' ' ')"
        row=$(( row + 2 ))
    done
    if [ -z "$Q" ]; then
        say 1 9 "$(printf '%-47.47s' '  (START TYPING - 3270 AIRPORTS ON BOARD)')"
    elif [ "$NRES" -eq 0 ]; then
        say 1 9 "$(printf '%-47.47s' '  NO MATCHES')"
    fi
}

search_key() { # one keypress on the search screen
    case "$1" in
        28|"$KEY_SELECT")
            if [ "$NRES" -gt 0 ]; then
                pick="$(sed -n "$(( SEL + 1 ))p" "$SRCH" | cut -d'|' -f1)"
                if [ -n "$pick" ]; then
                    AIRPORT="$(echo "$pick" | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')"
                    save_conf
                    show menu
                fi
                return 0
            fi
            # Unknown code: accept it anyway, and try to fetch its details
            # from AeroAPI once so the map gets coordinates.
            QU="$(echo "$Q" | tr -d ' ' | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')"
            case "$QU" in
                [A-Z0-9][A-Z0-9][A-Z0-9]|[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9])
                    say 1 9 "$(printf '%-47.47s' "  LOOKING UP $QU VIA AEROAPI...")"
                    line="$(apt_lookup_api "$QU")"
                    if [ -n "$line" ]; then
                        AIRPORT="$(echo "$line" | cut -d'|' -f1)"
                        [ -n "$AIRPORT" ] || AIRPORT="$QU"
                    else
                        AIRPORT="$QU"
                    fi
                    save_conf
                    show menu
                    ;;
            esac
            ;;
        14) Q="${Q%?}"; update_search ;;
        "$KEY_UP")   SEL=$(( SEL - 1 )); [ $SEL -lt 0 ] && SEL=0; update_search ;;
        "$KEY_DOWN") SEL=$(( SEL + 1 )); update_search ;;
        *)
            c="$(key_to_char "$1")"
            if [ -n "$c" ] && [ ${#Q} -lt 30 ]; then
                Q="$Q$c"
                update_search
            fi
            ;;
    esac
}

cycle_airport() {
    nxt=""
    take=0
    first=""
    for p in $PRESETS; do
        [ -z "$first" ] && first=$p
        [ $take = 1 ] && { nxt=$p; break; }
        [ "$p" = "$AIRPORT" ] && take=1
    done
    [ -n "$nxt" ] || nxt=$first
    AIRPORT="$nxt"
    save_conf
}

stop_refresher() {
    [ -n "$SHOWPID" ] && kill $SHOWPID 2>/dev/null
    SHOWPID=""
}

show() { # show <screen>
    stop_refresher
    CUR="$1"
    case "$1" in
        # Boards and the map run as background children so their REFRESH
        # loop keeps updating the screen; any keypress kills the child.
        arr|dep|all)
            sh "$PT_BIN/board.sh" "$1" &
            SHOWPID=$! ;;
        map)
            sh "$PT_BIN/radar.sh" &
            SHOWPID=$! ;;
        rwy)     sh "$PT_BIN/runways.sh" ;;
        net)     sh "$PT_BIN/nettest.sh" ;;
        help)    sh "$PT_BIN/help.sh" ;;
        search)  draw_search ;;
        keytest) draw_keytest ;;
        *)       CUR=menu; draw_menu ;;
    esac
}

# ---------------------------------------------------------------- main -----

SCREEN="${1:-menu}"

# Start capturing keys FIRST: the initial screen draw can take a while
# (network fetches), and keypresses during it would otherwise go only to
# the Kindle framework, which repaints its own UI over ours. Captured
# keys are processed as soon as the draw finishes and win the screen back.
INPUT_OK=1
start_input || INPUT_OK=0

# Let KUAL/the framework finish repainting before the first draw, so the
# board isn't immediately painted over.
sleep 2

show "$SCREEN"

if [ "$INPUT_OK" != 1 ]; then
    log "no readable input devices - drew once, exiting"
    exit 0
fi
arm_watchdog

KEYCOUNT=0
while :; do
    k="$(getkey)"
    [ -n "$k" ] || continue
    arm_watchdog

    case "$k" in
        "$KEY_HOME") break ;;
        "$KEY_BACK")
            if [ "$CUR" = "menu" ]; then break; else show menu; fi
            continue ;;
        "$KEY_MENU") show menu; continue ;;
    esac

    case "$CUR" in
        keytest)
            KEYCOUNT=$(( KEYCOUNT + 1 ))
            say 1 $(( 10 + KEYCOUNT % 24 )) "KEY $KEYCOUNT: CODE $k        "
            [ $KEYCOUNT -ge 20 ] && break
            ;;
        search)
            search_key "$k"
            ;;
        menu)
            case "$k" in
                30) show arr ;;     # A
                32) show dep ;;     # D
                46) show all ;;     # C
                50) show map ;;     # M
                19) show rwy ;;     # R
                49) show net ;;     # N
                35) show help ;;    # H
                31) show search ;;  # S
                25) cycle_airport; show menu ;;  # P
            esac ;;
        *)
            # framework may have repainted on this key - take it back
            show "$CUR" ;;
    esac
done

log "nav exit"
cls
exit 0
