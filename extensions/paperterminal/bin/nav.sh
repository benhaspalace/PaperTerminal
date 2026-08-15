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

load_conf
pt_capture_errors
log "nav start: ${1:-menu}"

PT_KEYPIPE="/tmp/paperterminal.keys"
READER_PIDS=""
WATCHDOG_PID=""

cleanup() {
    [ -n "$READER_PIDS" ] && kill $READER_PIDS 2>/dev/null
    [ -n "$WATCHDOG_PID" ] && kill $WATCHDOG_PID 2>/dev/null
    rm -f "$PT_KEYPIPE"
}
trap cleanup EXIT
trap 'exit 0' INT TERM

# --------------------------------------------------------------- input -----

start_input() {
    rm -f "$PT_KEYPIPE"
    mkfifo "$PT_KEYPIPE" 2>/dev/null || return 1
    for d in $INPUT_DEVS; do
        if [ -r "$d" ]; then
            cat "$d" > "$PT_KEYPIPE" &
            READER_PIDS="$READER_PIDS $!"
        fi
    done
    [ -n "$READER_PIDS" ] || return 1
    exec 3< "$PT_KEYPIPE"
}

# Print the keycode of the next key-down event (blocks). Empty output for
# non-key events; callers loop.
getkey() {
    dd bs=16 count=1 <&3 2>/dev/null | od -An -tu1 | awk '
        { for (i = 1; i <= NF; i++) b[++n] = $i }
        END {
            if (n >= 16 && b[9] + b[10] * 256 == 1 && b[13] == 1)
                print b[11] + b[12] * 256
        }'
}

# 10 minutes without a keypress ends the session so no readers linger.
arm_watchdog() {
    [ -n "$WATCHDOG_PID" ] && kill $WATCHDOG_PID 2>/dev/null
    ( sleep 600; kill -TERM $$ 2>/dev/null ) &
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
    say 3 19 "P   AIRPORT: $AIRPORT  (PRESS TO CYCLE)"
    say 1 22 "$LRULE"
    say 1 24 "PRESS A LETTER TO OPEN A SCREEN."
    say 1 25 "BACK = EXIT   MENU = THIS MENU   ON ANY"
    say 1 26 "SCREEN: BACK = MENU, OTHER KEY = REDRAW."
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

show() { # show <screen>
    CUR="$1"
    case "$1" in
        arr|dep|all) PT_ONCE=1 sh "$PT_BIN/board.sh" "$1" ;;
        map)     PT_ONCE=1 sh "$PT_BIN/radar.sh" ;;
        rwy)     sh "$PT_BIN/runways.sh" ;;
        net)     sh "$PT_BIN/nettest.sh" ;;
        help)    sh "$PT_BIN/help.sh" ;;
        keytest) draw_keytest ;;
        *)       CUR=menu; draw_menu ;;
    esac
}

# ---------------------------------------------------------------- main -----

SCREEN="${1:-menu}"

# Let KUAL/the framework finish repainting before the first draw, so the
# board isn't immediately painted over.
sleep 2

show "$SCREEN"

if ! start_input; then
    log "no readable input devices - drew once, exiting"
    exit 0
fi
arm_watchdog

KEYCOUNT=0
while :; do
    k="$(getkey)"
    [ -n "$k" ] || continue
    arm_watchdog

    if [ "$CUR" = "keytest" ]; then
        KEYCOUNT=$(( KEYCOUNT + 1 ))
        say 1 $(( 10 + KEYCOUNT % 24 )) "KEY $KEYCOUNT: CODE $k        "
        [ $KEYCOUNT -ge 20 ] && break
        continue
    fi

    case "$k" in
        "$KEY_HOME") break ;;
        "$KEY_BACK")
            if [ "$CUR" = "menu" ]; then break; else show menu; fi ;;
        "$KEY_MENU") show menu ;;
        *)
            if [ "$CUR" = "menu" ]; then
                case "$k" in
                    30) show arr ;;   # A
                    32) show dep ;;   # D
                    46) show all ;;   # C
                    50) show map ;;   # M
                    19) show rwy ;;   # R
                    49) show net ;;   # N
                    35) show help ;;  # H
                    25) cycle_airport; show menu ;;  # P
                esac
            else
                # framework may have repainted on this key - take it back
                show "$CUR"
            fi ;;
    esac
done

log "nav exit"
cls
exit 0
