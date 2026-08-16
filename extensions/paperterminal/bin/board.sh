#!/bin/sh
# PaperTerminal - draw the arrival/departure board from public APIs.
# usage: board.sh arr|dep|all

. "$(dirname "$0")/common.sh"
. "$(dirname "$0")/sources.sh"

DIR="$1"
case "$DIR" in arr|dep|all) ;; *) DIR="arr" ;; esac

load_conf

case "$DIR" in
    arr) TITLE="ARRIVALS";    PICT='\v';   DCOL="FROM"  ;;
    dep) TITLE="DEPARTURES";  PICT='/^';   DCOL="TO"    ;;
    all) TITLE="ALL FLIGHTS"; PICT='\v/^'; DCOL="FR/TO" ;;
esac

# ------------------------------------------------------------------ data ---
# Line format:  DIR|TIME|FLIGHT|AIRLINE|TYPE|RUNWAY|AIRPORT|DX|DY|CALLSIGN
# DIR is A (arrival) or D (departure); AIRPORT is the origin for arrivals
# and the destination for departures. Lines starting with # are comments.

get_feed() {
    FEED_OK=0
    if src_fetch "$DIR" ahead "$ROWS" "$PT_TMP"; then
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
    stype=""
    [ "$PT_SRC_USED" -ge 1 ] && eval "stype=\$SOURCE$PT_SRC_USED"
    case "${stype%%,*}" in
        adsb) SRC="LIVE AIR $AIRPORT (ADS-B EST.)" ;;
    esac
    [ "$PT_SRC_USED" -gt 1 ] && SRC="$SRC [SRC$PT_SRC_USED]"
    [ "$PT_SRC_STALE" -gt 0 ] && SRC="$AIRPORT - DATA ${PT_SRC_STALE}MIN OLD"
    draw_footer "$SRC"
}

draw_error() {
    draw_header
    NSRC="$(src_count)"
    if [ "$NSRC" -gt 1 ]; then
        say 1 6 "  ALL $NSRC CONFIGURED DATA SOURCES FAILED"
    else
        say 1 6 "  DATA SOURCE FAILED"
    fi
    row=8
    i=0
    while [ $i -lt 3 ]; do
        i=$(( i + 1 ))
        eval "spec=\$SOURCE$i"
        [ -n "$spec" ] || continue
        say 1 $row "  SOURCE $i: ${spec%%,*}"
        row=$(( row + 1 ))
    done
    row=$(( row + 1 ))
    say 1 $row "  CHECK:"; row=$(( row + 1 ))
    say 1 $row "  - WI-FI IS CONNECTED (3G ONLY REACHES"; row=$(( row + 1 ))
    say 1 $row "    AMAZON, NOT THE FLIGHT APIS)"; row=$(( row + 1 ))
    say 1 $row "  - FREE MODE (adsb) NEEDS lib/ COPIED"; row=$(( row + 1 ))
    say 1 $row "    AND $AIRPORT IN data/airports.txt"; row=$(( row + 1 ))
    say 1 $row "  - KEYED SOURCES NEED VALID API KEYS"; row=$(( row + 1 ))
    say 1 $row "    IN paperterminal.conf (EDIT OVER USB)"; row=$(( row + 2 ))
    say 1 $row "  RUN THE NETWORK SELF-TEST (KUAL OR THE"; row=$(( row + 1 ))
    say 1 $row "  N KEY IN THE MENU) TO PINPOINT IT."; row=$(( row + 2 ))
    say 1 $row "  DETAILS: paperterminal.log"
    draw_footer "NO DATA"
}

# ------------------------------------------------------------------ main ---

get_feed
if [ "$FEED_OK" = 1 ]; then draw_board; else draw_error; fi

# Auto-update loop: every REFRESH seconds re-read the (cached) data and
# repaint ONLY when something changed - e-ink stays calm, API budget is
# untouched. Bounded at ~10h so nothing runs forever. PT_ONCE=1 draws once.
sig() { { cat "$PT_TMP" 2>/dev/null; echo "S:$FEED_OK:$PT_SRC_USED:$PT_SRC_STALE"; } > "$1"; }

if [ "$REFRESH" -gt 0 ] && [ "$PT_ONCE" != "1" ]; then
    sig "$PT_TMP.sig"
    i=0
    while [ $i -lt 7200 ]; do
        sleep "$REFRESH"
        get_feed
        sig "$PT_TMP.sig2"
        if ! cmp -s "$PT_TMP.sig" "$PT_TMP.sig2" 2>/dev/null; then
            if [ "$FEED_OK" = 1 ]; then draw_board; else draw_error; fi
            mv "$PT_TMP.sig2" "$PT_TMP.sig"
        fi
        i=$(( i + 1 ))
    done
fi

exit 0
