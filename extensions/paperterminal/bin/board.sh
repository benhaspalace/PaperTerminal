#!/bin/sh
# PaperTerminal - draw the arrival/departure board from the live feed.
# usage: board.sh arr|dep|all

. "$(dirname "$0")/common.sh"

DIR="$1"
case "$DIR" in arr|dep|all) ;; *) DIR="arr" ;; esac

load_conf

case "$DIR" in
    arr) TITLE="ARRIVALS";    PICT='\v';   DCOL="FROM"  ;;
    dep) TITLE="DEPARTURES";  PICT='/^';   DCOL="TO"    ;;
    all) TITLE="ALL FLIGHTS"; PICT='\v/^'; DCOL="FR/TO" ;;
esac

# ------------------------------------------------------------------ feed ---
# Feed line format (v2):  DIR|TIME|FLIGHT|AIRLINE|TYPE|RUNWAY|AIRPORT
# DIR is A (arrival) or D (departure); AIRPORT is the origin for arrivals
# and the destination for departures. Lines starting with # are comments.

get_feed() {
    FEED_OK=0
    if pt_fetch_feed "airport=$AIRPORT&dir=$DIR&limit=$ROWS" "$PT_TMP"; then
        FEED_OK=1
    fi
}

# ------------------------------------------------------------------ draw ---

draw_header() {
    cls
    say 1 1 "PAPERTERMINAL"
    say_r 1 "$AIRPORT $PICT $TITLE"
    say 1 2 "$HRULE"
}

draw_footer() { # draw_footer <left-text>
    say 1 36 "$LRULE"
    say 1 37 "$1"
    say_r 37 "UPD $(date +%H:%M)"
}

draw_board() {
    draw_header
    say 1 3 "$(printf '%-2s %-5s %-7s %-5s %-16s %-4s %-3s' '' 'TIME' 'FLIGHT' "$DCOL" 'AIRLINE' 'TYPE' 'RWY')"
    say 1 4 "$LRULE"

    row=6
    count=0
    while IFS='|' read -r D T FL AL TY RW AP; do
        case "$D" in
            ''|\#*) continue ;;
            A) RP='\v' ;;
            D) RP='/^' ;;
            *) continue ;;
        esac
        [ $count -ge "$ROWS" ] && break
        AP="${AP%%|*}"
        AP="$(echo "$AP" | tr -d '\r')"
        [ -n "$AP" ] || AP="-"
        [ -n "$RW" ] || RW="-"
        [ -n "$TY" ] || TY="-"
        [ -n "$T"  ] || T="--:--"
        line="$(printf '%-2s %-5.5s %-7.7s %-5.5s %-16.16s %-4.4s %-3.3s' \
            "$RP" "$T" "$FL" "$AP" "$AL" "$TY" "$RW")"
        say 1 $row "$line"
        row=$(( row + 2 ))
        count=$(( count + 1 ))
    done < "$PT_TMP"

    [ $count -eq 0 ] && say 1 10 "NO FLIGHTS REPORTED FOR $AIRPORT RIGHT NOW"

    SRC="LIVE $AIRPORT"
    [ "$PT_FEED_USED" -gt 1 ] && SRC="LIVE $AIRPORT (BACKUP FEED $PT_FEED_USED)"
    draw_footer "$SRC"
}

draw_error() {
    draw_header
    NFEEDS="$(pt_feed_count)"
    if [ "$NFEEDS" -gt 1 ]; then
        say 1 6 "  ALL $NFEEDS CONFIGURED FEEDS FAILED"
    else
        say 1 6 "  FEED UNREACHABLE OR INVALID"
    fi
    say 1 8  "  URL: $(printf '%.41s' "$FEED_URL")"
    say 1 10 "  CHECK:"
    say 1 11 "  - WI-FI IS CONNECTED (3G ONLY REACHES"
    say 1 12 "    AMAZON, IT CANNOT REACH YOUR FEED)"
    say 1 13 "  - YOUR FEED PROXY IS RUNNING"
    say 1 14 "    (server/feed_proxy.py IN THE REPO)"
    say 1 15 "  - FEED_URL / FEED_URL2 / FEED_URL3 IN"
    say 1 16 "    paperterminal.conf"
    say 1 18 "  RUN KUAL > NETWORK SELF-TEST (HTTPS)"
    say 1 19 "  TO PINPOINT THE FAILING STEP."
    say 1 21 "  DETAILS: paperterminal.log"
    draw_footer "FEED DOWN"
}

# ------------------------------------------------------------------ main ---

get_feed
if [ "$FEED_OK" = 1 ]; then draw_board; else draw_error; fi

# Optional auto-refresh, bounded so KUAL never hangs forever.
if [ "$REFRESH" -gt 0 ]; then
    i=0
    while [ $i -lt 30 ]; do
        sleep "$REFRESH"
        get_feed
        if [ "$FEED_OK" = 1 ]; then draw_board; else draw_error; fi
        i=$(( i + 1 ))
    done
fi

exit 0
