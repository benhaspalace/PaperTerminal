#!/bin/sh
# PaperTerminal - draw the arrival/departure board.
# usage: board.sh arr|dep

. "$(dirname "$0")/common.sh"

DIR="$1"
[ "$DIR" = "dep" ] || DIR="arr"

load_conf

if [ "$DIR" = "arr" ]; then
    TITLE="ARRIVALS"
    PICT='\v'
else
    TITLE="DEPARTURES"
    PICT='/^'
fi

# ------------------------------------------------------------------ time ---
# Demo data stores times as offsets in minutes from "now" (+12 / -4) so the
# board always looks alive. Live feed lines carry ready-made HH:MM.

now_minutes() {
    h="$(date +%H)"; m="$(date +%M)"
    h="${h#0}"; m="${m#0}"
    echo $(( h * 60 + m ))
}

fmt_time() {
    case "$1" in
        [+-]*)
            n="${1#?}"
            case "$n" in ''|*[!0-9]*) echo "--:--"; return;; esac
            case "$1" in
                -*) t=$(( NOWM - n ));;
                *)  t=$(( NOWM + n ));;
            esac
            t=$(( (t + 2880) % 1440 ))
            printf '%02d:%02d\n' $(( t / 60 )) $(( t % 60 ))
            ;;
        '') echo "--:--" ;;
        *)  echo "$1" ;;
    esac
}

# ------------------------------------------------------------------ feed ---
# Feed line format:  TIME|FLIGHT|AIRLINE|TYPE|RUNWAY
# Lines starting with # are comments. In demo mode (or when the live feed
# is unreachable) the bundled demo files are used instead.

get_feed() {
    SOURCE="DEMO DATA"
    FEED_FILE="$PT_DATA/demo_${DIR}.txt"
    [ "$MODE" = "live" ] || return 0

    url="$FEED_URL?airport=$AIRPORT&dir=$DIR&limit=$ROWS"
    rm -f "$PT_TMP"

    # The K3 busybox wget has no timeout option, so babysit it ourselves
    # to keep a dead network from freezing the board for minutes.
    wget -q -O "$PT_TMP" "$url" 2>/dev/null &
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

    if [ -s "$PT_TMP" ] && grep -q '|.*|.*|.*|' "$PT_TMP"; then
        SOURCE="LIVE $AIRPORT"
        FEED_FILE="$PT_TMP"
    else
        SOURCE="FEED DOWN - DEMO"
        log "feed fetch failed: $url"
    fi
}

# ------------------------------------------------------------------ draw ---

draw_board() {
    NOWM=$(now_minutes)
    cls
    say 1 1 "PAPERTERMINAL"
    say_r 1 "$AIRPORT $PICT $TITLE"
    say 1 2 "$HRULE"
    say 1 3 "$(printf '%-2s %-5s %-8s %-17s %-4s %-3s' '' 'TIME' 'FLIGHT' 'AIRLINE' 'TYPE' 'RWY')"
    say 1 4 "$LRULE"

    row=6
    count=0
    while IFS='|' read -r T FL AL TY RW; do
        case "$T" in ''|\#*) continue;; esac
        [ $count -ge "$ROWS" ] && break
        RW="${RW%%|*}"
        RW="$(echo "$RW" | tr -d '\r')"
        [ -n "$RW" ] || RW="-"
        [ -n "$TY" ] || TY="-"
        line="$(printf '%-2s %-5.5s %-8.8s %-17.17s %-4.4s %-3.3s' \
            "$PICT" "$(fmt_time "$T")" "$FL" "$AL" "$TY" "$RW")"
        say 1 $row "$line"
        row=$(( row + 2 ))
        count=$(( count + 1 ))
    done < "$FEED_FILE"

    [ $count -eq 0 ] && say 1 10 "NO FLIGHTS IN FEED"

    say 1 36 "$LRULE"
    say 1 37 "$SOURCE"
    say_r 37 "UPD $(date +%H:%M)"
}

# ------------------------------------------------------------------ main ---

get_feed
draw_board

# Optional live auto-refresh, bounded so KUAL never hangs forever.
if [ "$REFRESH" -gt 0 ] && [ "$MODE" = "live" ]; then
    i=0
    while [ $i -lt 30 ]; do
        sleep "$REFRESH"
        get_feed
        draw_board
        i=$(( i + 1 ))
    done
fi

exit 0
