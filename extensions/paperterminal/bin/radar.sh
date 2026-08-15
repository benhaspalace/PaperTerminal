#!/bin/sh
# PaperTerminal - live traffic map: plots the ADS-B positions of the ROWS
# flights before and after now (feed window=split) around the airport.
# v = arrival, ^ = departure, + = the airport. RANGE (nm) sets the scale.

. "$(dirname "$0")/common.sh"

load_conf

# Map geometry: rows 3..27, centre at col 25 / row 15. A char cell is
# 12x20 px, so vertical cells cover ~5/3 the distance of horizontal ones:
# col = 25 + dx*24/RANGE, row = 15 - dy*9/RANGE keeps north/east to scale.
CX=25; CY=15

draw_map() {
    cls
    say 1 1 "PAPERTERMINAL"
    say_r 1 "$AIRPORT LIVE TRAFFIC"
    say 1 2 "$HRULE"

    # compass + centre
    say 25 3  "N"
    say 25 27 "S"
    say 1 15  "W"
    say 48 15 "E"
    say $CX $CY "+$AIRPORT"

    n=0; nopos=0; faroff=0
    while IFS='|' read -r D T FL AL TY RW AP DX DY; do
        case "$D" in
            ''|\#*) continue ;;
            A) SYM="v" ;;
            D) SYM="^" ;;
            *) continue ;;
        esac
        DY="$(echo "$DY" | tr -d '\r')"
        DY="${DY%%|*}"
        if [ -z "$DX" ] || [ -z "$DY" ]; then
            nopos=$(( nopos + 1 ))
            continue
        fi
        col=$(( CX + DX * 24 / RANGE ))
        row=$(( CY - DY * 9 / RANGE ))
        if [ $col -lt 1 ] || [ $col -gt 47 ] || [ $row -lt 3 ] || [ $row -gt 27 ]; then
            faroff=$(( faroff + 1 ))
            continue
        fi
        n=$(( n + 1 ))
        say $col $row "$SYM$n"
        if [ $n -le 7 ]; then
            # octagonal distance approximation: max + 0.41*min (no sqrt in sh)
            adx=$DX; [ $adx -lt 0 ] && adx=$(( -adx ))
            ady=$DY; [ $ady -lt 0 ] && ady=$(( -ady ))
            if [ $adx -ge $ady ]; then big=$adx; small=$ady; else big=$ady; small=$adx; fi
            dist=$(( big + small * 41 / 100 ))
            say 1 $(( 28 + n )) "$(printf ' %s%-2d %-5.5s %-7.7s %-4.4s %3dNM' \
                "$SYM" "$n" "$T" "$FL" "$AP" "$dist")"
        fi
    done < "$PT_TMP"

    say 1 28 "$(printf ' %d AIRBORNE SHOWN, %d BEYOND RANGE, %d NO POS' \
        "$n" "$faroff" "$nopos")"
    say 1 36 "$LRULE"
    SRC="RANGE ${RANGE}NM"
    [ "$PT_FEED_USED" -gt 1 ] && SRC="RANGE ${RANGE}NM (BACKUP FEED $PT_FEED_USED)"
    say 1 37 "$SRC"
    say_r 37 "UPD $(date +%H:%M)"
}

draw_error() {
    cls
    say 1 1 "PAPERTERMINAL"
    say_r 1 "$AIRPORT LIVE TRAFFIC"
    say 1 2 "$HRULE"
    say 1 6 "  NO FEED - SEE THE BOARD SCREENS OR RUN"
    say 1 7 "  KUAL > NETWORK SELF-TEST (HTTPS)"
    say 1 36 "$LRULE"
    say 1 37 "FEED DOWN"
    say_r 37 "UPD $(date +%H:%M)"
}

get_feed() {
    FEED_OK=0
    if pt_fetch_feed "airport=$AIRPORT&dir=all&limit=$ROWS&window=split" "$PT_TMP"; then
        FEED_OK=1
    fi
}

get_feed
if [ "$FEED_OK" = 1 ]; then draw_map; else draw_error; fi

if [ "$REFRESH" -gt 0 ]; then
    i=0
    while [ $i -lt 30 ]; do
        sleep "$REFRESH"
        get_feed
        if [ "$FEED_OK" = 1 ]; then draw_map; else draw_error; fi
        i=$(( i + 1 ))
    done
fi

exit 0
