#!/bin/sh
# PaperTerminal - help screen with current settings.

. "$(dirname "$0")/common.sh"

load_conf
cls

say 1 1  "PAPERTERMINAL $PT_VERSION - HELP"
say 1 2  "$HRULE"
say 1 4  "CURRENT SETTINGS"
say 1 5  "  AIRPORT : $AIRPORT"
say 1 6  "  MODE    : $MODE"
say 1 7  "  ROWS    : $ROWS   REFRESH: ${REFRESH}s"
say 1 8  "  FEED    : $(printf '%.38s' "$FEED_URL")"
say 1 10 "$LRULE"
say 1 12 "BOARDS: ARRIVALS, DEPARTURES, OR COMBINED"
say 1 13 "(BOTH MIXED, SORTED BY TIME). A BOARD STAYS"
say 1 14 "ON SCREEN UNTIL A KEY REDRAWS THE KINDLE UI."
say 1 16 "ROW FORMAT:"
say 1 17 "  PIC TIME FLIGHT FR/TO AIRLINE  TYPE RWY"
say 1 18 "  \v = ARRIVAL (FROM)   /^ = DEPARTURE (TO)"
say 1 20 "DEMO MODE WORKS OFFLINE WITH SAMPLE DATA."
say 1 21 "LIVE MODE FETCHES THE FEED WITH THE BUNDLED"
say 1 22 "MODERN curl + CA CERTS (lib/), SO https://"
say 1 23 "FEED URLS WORK. RUN THE NETWORK SELF-TEST TO"
say 1 24 "CHECK. 3G ONLY REACHES AMAZON - USE WI-FI."
say 1 26 "TO SET ANY AIRPORT NOT IN THE MENU, PLUG IN"
say 1 27 "USB AND EDIT extensions/paperterminal/"
say 1 28 "paperterminal.conf (AIRPORT=XXX)."
say 1 30 "$LRULE"
say 1 31 "PRESS ANY KEY TO GET THE MENU BACK"
exit 0
