#!/bin/sh
# PaperTerminal - live traffic map: plots the ADS-B positions of the ROWS
# flights before and after now (window=split) around the airport.
# v = arrival, ^ = departure, + = the airport. RANGE (nm) sets the scale.

. "$(dirname "$0")/common.sh"
. "$(dirname "$0")/sources.sh"

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
    [ "$PT_SRC_USED" -gt 1 ] && SRC="RANGE ${RANGE}NM (BACKUP SOURCE $PT_SRC_USED)"
    [ "$PT_SRC_STALE" -gt 0 ] && SRC="RANGE ${RANGE}NM - DATA ${PT_SRC_STALE}MIN OLD"
    say 1 37 "$SRC"
    say_r 37 "UPD $(date +%H:%M)"
}

draw_error() {
    cls
    say 1 1 "PAPERTERMINAL"
    say_r 1 "$AIRPORT LIVE TRAFFIC"
    say 1 2 "$HRULE"
    say 1 6 "  NO DATA - ALL SOURCES FAILED. RUN THE"
    say 1 7 "  NETWORK SELF-TEST TO PINPOINT WHY."
    say 1 36 "$LRULE"
    say 1 37 "NO DATA"
    say_r 37 "UPD $(date +%H:%M)"
}

# Fetch the split window of flights, then fill in DX/DY from a direct
# ADS-B lookup, matching by callsign (field 10).
get_feed() {
    FEED_OK=0
    src_fetch all split "$ROWS" "$PT_TMP" || return 1
    if src_positions "$PT_TMP.pos"; then
        awk -F'|' '
            NR == FNR { if (NF >= 3 && $1 != "") { dx[$1] = $2; dy[$1] = $3 } next }
            /^[AD]\|/ {
                d8 = $8; d9 = $9
                if ((d8 == "" || d9 == "") && $10 != "" && ($10 in dx)) {
                    d8 = dx[$10]; d9 = dy[$10]
                }
                print $1"|"$2"|"$3"|"$4"|"$5"|"$6"|"$7"|"d8"|"d9
            }' "$PT_TMP.pos" "$PT_TMP" > "$PT_TMP.m" \
            && mv "$PT_TMP.m" "$PT_TMP"
    fi
    rm -f "$PT_TMP.pos"
    FEED_OK=1
}

get_feed
if [ "$FEED_OK" = 1 ]; then draw_map; else draw_error; fi

# Auto-update loop: repaint only when flights or positions changed.
# Position fetches are keyless and light (one area query per cycle).
sig() { { cat "$PT_TMP" 2>/dev/null; echo "S:$FEED_OK:$PT_SRC_USED:$PT_SRC_STALE"; } > "$1"; }

if [ "$REFRESH" -gt 0 ] && [ "$PT_ONCE" != "1" ]; then
    sig "$PT_TMP.sig"
    i=0
    while [ $i -lt 7200 ]; do
        sleep "$REFRESH"
        get_feed
        sig "$PT_TMP.sig2"
        if ! cmp -s "$PT_TMP.sig" "$PT_TMP.sig2" 2>/dev/null; then
            if [ "$FEED_OK" = 1 ]; then draw_map; else draw_error; fi
            mv "$PT_TMP.sig2" "$PT_TMP.sig"
        fi
        i=$(( i + 1 ))
    done
fi

exit 0
