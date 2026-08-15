#!/bin/sh
# PaperTerminal - simple runway line diagram for the default airport.
# Diagrams are plain text files in data/runways/<CODE>.txt, max 48 chars
# wide and 30 lines tall.

. "$(dirname "$0")/common.sh"

load_conf

# ICAO aliases for the bundled diagrams
case "$AIRPORT" in
    LSZH) DIA="ZRH" ;;
    LHBP) DIA="BUD" ;;
    EHAM) DIA="AMS" ;;
    EDDS) DIA="STR" ;;
    *)    DIA="$AIRPORT" ;;
esac
F="$PT_HOME/data/runways/$DIA.txt"

cls
say 1 1 "PAPERTERMINAL"
say_r 1 "$AIRPORT RUNWAYS"
say 1 2 "$HRULE"

if [ -f "$F" ]; then
    row=4
    while IFS= read -r L; do
        [ $row -gt 33 ] && break
        say 1 $row "$L"
        row=$(( row + 1 ))
    done < "$F"
else
    say 1 6  "  NO RUNWAY DIAGRAM FOR $AIRPORT"
    say 1 8  "  BUNDLED DIAGRAMS: ZRH BUD AMS STR"
    say 1 10 "  ADD YOUR OWN AS PLAIN TEXT (MAX 48"
    say 1 11 "  CHARS WIDE) IN extensions/paperterminal/"
    say 1 12 "  data/runways/$DIA.txt"
fi

say 1 36 "$LRULE"
say 1 37 "PRESS ANY KEY TO GET THE MENU BACK"
exit 0
