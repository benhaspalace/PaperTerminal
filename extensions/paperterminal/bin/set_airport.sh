#!/bin/sh
# PaperTerminal - set the default airport.
# usage: set_airport.sh <IATA-or-ICAO-code>

. "$(dirname "$0")/common.sh"

AP="$(printf '%s' "$1" | tr 'abcdefghijklmnopqrstuvwxyz' 'ABCDEFGHIJKLMNOPQRSTUVWXYZ')"

case "$AP" in
    [A-Z0-9][A-Z0-9][A-Z0-9]|[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]) ;;
    *)
        splash "INVALID AIRPORT CODE: $AP" \
               "USE A 3-LETTER IATA OR 4-LETTER ICAO CODE" \
               "OR EDIT paperterminal.conf OVER USB"
        exit 1
        ;;
esac

load_conf
AIRPORT="$AP"
save_conf

splash "DEFAULT AIRPORT SET TO: $AP" \
       "OPEN ARRIVALS OR DEPARTURES FROM THE MENU" \
       "ANY CODE CAN BE SET IN paperterminal.conf"
exit 0
