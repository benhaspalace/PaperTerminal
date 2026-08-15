#!/bin/sh
# PaperTerminal - help screen with current settings.

. "$(dirname "$0")/common.sh"

load_conf
cls

if [ -n "$(pt_curl_bin)" ]; then
    HTTPS_STATE="OK (BUNDLED curl + CA CERTS)"
else
    HTTPS_STATE="WGET FALLBACK (PLAIN http ONLY)"
fi

say 1 1  "PAPERTERMINAL $PT_VERSION - HELP"
say 1 2  "$HRULE"
say 1 4  "CURRENT SETTINGS"
say 1 5  "  AIRPORT : $AIRPORT"
say 1 6  "  HTTPS   : $HTTPS_STATE"
say 1 7  "  ROWS    : $ROWS   REFRESH: ${REFRESH}s"
say 1 8  "  FEED    : $(printf '%.38s' "$FEED_URL")"
say 1 10 "$LRULE"
say 1 12 "BOARDS: ARRIVALS, DEPARTURES, OR COMBINED"
say 1 13 "(BOTH MIXED, SORTED BY TIME). A BOARD STAYS"
say 1 14 "ON SCREEN UNTIL A KEY REDRAWS THE KINDLE UI."
say 1 16 "ROW FORMAT:"
say 1 17 "  PIC TIME FLIGHT FR/TO AIRLINE  TYPE RWY"
say 1 18 "  \v = ARRIVAL (FROM)   /^ = DEPARTURE (TO)"
say 1 20 "ALL DATA COMES FROM YOUR FEED (FEED_URL IN"
say 1 21 "paperterminal.conf); RUN server/feed_proxy.py"
say 1 22 "ANYWHERE. http:// AND https:// BOTH WORK -"
say 1 23 "https USES THE BUNDLED MODERN curl + CA"
say 1 24 "CERTS IN lib/. 3G ONLY REACHES AMAZON, SO"
say 1 25 "USE WI-FI. IF THE FEED IS DOWN THE BOARD"
say 1 26 "SHOWS A DIAGNOSTIC SCREEN INSTEAD."
say 1 28 "TO SET ANY AIRPORT NOT IN THE MENU, PLUG IN"
say 1 29 "USB AND EDIT extensions/paperterminal/"
say 1 30 "paperterminal.conf (AIRPORT=XXX)."
say 1 32 "$LRULE"
say 1 33 "PRESS ANY KEY TO GET THE MENU BACK"
exit 0
