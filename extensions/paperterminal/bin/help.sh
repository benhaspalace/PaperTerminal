#!/bin/sh
# PaperTerminal - help screen with current settings.

. "$(dirname "$0")/common.sh"
. "$(dirname "$0")/sources.sh"

load_conf
cls

if [ -n "$(pt_curl_bin)" ]; then
    HTTPS_STATE="OK (BUNDLED curl + CA CERTS)"
else
    HTTPS_STATE="MISSING - COPY lib/ TO THE KINDLE"
fi

mask_src() { # mask_src <spec> - never print API keys on screen
    [ -n "$1" ] || { echo "-"; return; }
    t="${1%%,*}"
    k="${1#*,}"
    if [ "$k" = "$1" ] || [ -z "$k" ]; then
        echo "$t (NO KEY SET)"
    elif [ "$k" = "PUT_YOUR_KEY_HERE" ]; then
        echo "$t (PUT YOUR KEY IN THE CONF)"
    else
        echo "$t (KEY $(printf '%.4s' "$k")***)"
    fi
}

say 1 1  "PAPERTERMINAL $PT_VERSION - HELP"
say 1 2  "$HRULE"
say 1 4  "CURRENT SETTINGS"
say 1 5  "  AIRPORT : $AIRPORT"
say 1 6  "  HTTPS   : $HTTPS_STATE"
say 1 7  "  ROWS: $ROWS  REFRESH: ${REFRESH}s  RANGE: ${RANGE}NM"
say 1 8  "  SOURCE1 : $(mask_src "$SOURCE1")"
say 1 9  "  SOURCE2 : $(mask_src "$SOURCE2")"
say 1 10 "  SOURCE3 : $(mask_src "$SOURCE3")"
aero_load_usage
say 1 11 "  AEROAPI : $UDC/$AERO_DAY TODAY, $UMC/$AERO_MONTH THIS MONTH"
say 1 12 "$LRULE"
say 1 14 "SCREENS: ARRIVAL/DEPARTURE/COMBINED BOARDS,"
say 1 15 "LIVE TRAFFIC MAP (ADS-B), RUNWAY DIAGRAMS."
say 1 17 "NAVIGATION (FROM ANY SCREEN):"
say 1 18 "  MENU = PAPERTERMINAL MENU   BACK = MENU/"
say 1 19 "  EXIT   HOME = KINDLE UI   OTHER = REDRAW"
say 1 20 "  KEYS WRONG? RUN THE KEY TEST AND SET THE"
say 1 21 "  KEY_* CODES IN paperterminal.conf."
say 1 23 "DATA COMES STRAIGHT FROM PUBLIC FLIGHT APIS"
say 1 24 "(AeroAPI / aviationstack, SOURCE1-3 TRIED IN"
say 1 25 "ORDER) AND OPEN ADS-B FOR THE MAP. PUT YOUR"
say 1 26 "API KEY IN paperterminal.conf OVER USB."
say 1 27 "3G ONLY REACHES AMAZON - USE WI-FI."
say 1 29 "ANY AIRPORT: PRESS S IN THE MENU AND TYPE A"
say 1 30 "CODE, CITY, OR NAME (THOUSANDS ON BOARD;"
say 1 31 "UNKNOWN CODES ARE LOOKED UP VIA AEROAPI)."
say 1 33 "$LRULE"
say 1 34 "PRESS ANY KEY TO GO BACK"
exit 0
