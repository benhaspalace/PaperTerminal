#!/bin/sh
# PaperTerminal - on-device network / HTTPS / data-source self-test.

. "$(dirname "$0")/common.sh"
. "$(dirname "$0")/sources.sh"

load_conf
cls

say 1 1 "PAPERTERMINAL $PT_VERSION - NETWORK SELF-TEST"
say 1 2 "$HRULE"

say 1 4 "TEST 1: HTTPS STACK"
CURLBIN="$(pt_curl_bin)"
if [ -n "$CURLBIN" ]; then
    if [ "$CURLBIN" = "$PT_CURL" ]; then WHERE="IN PLACE"; else WHERE="RAM COPY"; fi
    say 1 5 "  lib/curl: OK - RUNS $WHERE"
    say 1 6 "  $("$CURLBIN" --version 2>/dev/null | head -n 1 | cut -c1-44)"
    NCERT="$(grep -c 'BEGIN CERTIFICATE' "$PT_CACERT" 2>/dev/null)"
    say 1 7 "  CA BUNDLE: ${NCERT:-0} ROOT CERTS (cacert.pem)"
else
    say 1 5 "  lib/curl: MISSING OR NOT RUNNABLE"
    say 1 6 "  ONLY aviationstack (PLAIN http) CAN WORK"
fi

say 1 9 "TEST 2: HTTPS TO THE INTERNET"
if [ -n "$CURLBIN" ]; then
    CODE="$("$CURLBIN" -sS --connect-timeout 15 -m 30 --cacert "$PT_CACERT" \
        -o /dev/null -w '%{http_code}' https://example.com/ 2>/dev/null)"
    if [ "$CODE" = "200" ]; then
        say 1 10 "  GET https://example.com -> OK (HTTP 200)"
        say 1 11 "  CERTIFICATE VERIFIED WITH BUNDLED CA FILE"
    else
        say 1 10 "  GET https://example.com -> FAILED (${CODE:-no reply})"
        say 1 11 "  CHECK WI-FI IS CONNECTED AND TRY AGAIN"
    fi
else
    say 1 10 "  SKIPPED - NO RUNNABLE lib/curl"
fi

say 1 13 "TEST 3: FLIGHT DATA SOURCES (EACH IN TURN)"
row=14
NOK=0
i=0
while [ $i -lt 3 ]; do
    i=$(( i + 1 ))
    eval "spec=\$SOURCE$i"
    [ -n "$spec" ] || continue
    rm -f "$PT_TMP"
    if src_try $i arr ahead 3 "$PT_TMP"; then
        NFL="$(grep -c '^[AD]|' "$PT_TMP")"
        say 1 $row "  SOURCE $i ($PT_SRC_TYPE): OK, $NFL FLIGHTS"
        NOK=$(( NOK + 1 ))
    else
        say 1 $row "  SOURCE $i (${spec%%,*}): FAILED"
    fi
    row=$(( row + 1 ))
done
if [ "$NOK" -eq 0 ]; then
    say 1 $row "  NO WORKING SOURCE - PUT YOUR API KEY IN"
    row=$(( row + 1 ))
    say 1 $row "  SOURCE1= IN paperterminal.conf"
    row=$(( row + 1 ))
fi
aero_load_usage
say 1 $row "  AEROAPI BUDGET: $UDC/$AERO_DAY TODAY, $UMC/$AERO_MONTH MONTH"
row=$(( row + 2 ))

say 1 $row "TEST 4: ADS-B POSITIONS (TRAFFIC MAP)"
row=$(( row + 1 ))
if src_positions "$PT_TMP.pos"; then
    NAC="$(grep -c '|' "$PT_TMP.pos" 2>/dev/null)"
    say 1 $row "  OK - $NAC AIRCRAFT SEEN NEAR $AIRPORT"
else
    say 1 $row "  FAILED - MAP WILL SHOW NO POSITIONS"
    row=$(( row + 1 ))
    say 1 $row "  (NEEDS lib/curl, WI-FI, AND $AIRPORT IN"
    row=$(( row + 1 ))
    say 1 $row "  data/airports.txt)"
fi
rm -f "$PT_TMP.pos"
row=$(( row + 2 ))

say 1 $row "$LRULE"
row=$(( row + 1 ))
say 1 $row "PRESS ANY KEY TO GO BACK"
exit 0
