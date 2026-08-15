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
say 1 7  "  ROWS    : $ROWS   REFRESH: ${REFRESH}s   RANGE: ${RANGE}NM"
say 1 8  "  FEED    : $(printf '%.38s' "$FEED_URL")"
say 1 10 "$LRULE"
say 1 12 "SCREENS: ARRIVAL/DEPARTURE/COMBINED BOARDS,"
say 1 13 "LIVE TRAFFIC MAP (ADS-B), RUNWAY DIAGRAMS."
say 1 14 "A SCREEN STAYS UNTIL A KEY REPAINTS THE UI."
say 1 16 "ROW FORMAT:"
say 1 17 "  PIC TIME FLIGHT FR/TO AIRLINE  TYPE RWY"
say 1 18 "  \v = ARRIVAL (FROM)   /^ = DEPARTURE (TO)"
say 1 20 "ALL DATA COMES FROM YOUR FEEDS (FEED_URL,"
say 1 21 "FEED_URL2, FEED_URL3 - TRIED IN ORDER); RUN"
say 1 22 "server/feed_proxy.py ANYWHERE. http:// AND"
say 1 23 "https:// BOTH WORK - https USES THE BUNDLED"
say 1 24 "MODERN curl + CA CERTS IN lib/. 3G ONLY"
say 1 25 "REACHES AMAZON, SO USE WI-FI. IF ALL FEEDS"
say 1 26 "FAIL, A DIAGNOSTIC SCREEN IS SHOWN INSTEAD."
say 1 28 "TO SET ANY AIRPORT NOT IN THE MENU, PLUG IN"
say 1 29 "USB AND EDIT extensions/paperterminal/"
say 1 30 "paperterminal.conf (AIRPORT=XXX)."
say 1 32 "$LRULE"
say 1 33 "PRESS ANY KEY TO GET THE MENU BACK"
exit 0
