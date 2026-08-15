#!/bin/sh
# PaperTerminal - on-device network / HTTPS self-test.
# Proves the bundled TLS stack works before you blame the feed.

. "$(dirname "$0")/common.sh"

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
    say 1 6 "  FALLBACK: BUSYBOX WGET (PLAIN HTTP ONLY)"
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

say 1 13 "TEST 3: CONFIGURED FEEDS (EACH IN TURN)"
row=14
idx=0
NOK=0
for u in "$FEED_URL" "$FEED_URL2" "$FEED_URL3"; do
    idx=$(( idx + 1 ))
    [ -n "$u" ] || continue
    rm -f "$PT_TMP"
    if pt_fetch "$u?airport=$AIRPORT&dir=arr&limit=3" "$PT_TMP" \
       && grep -q '^[AD]|' "$PT_TMP" 2>/dev/null; then
        NFL="$(grep -c '^[AD]|' "$PT_TMP")"
        say 1 $row "  FEED $idx OK, $NFL FLIGHTS: $(printf '%.24s' "$u")"
        NOK=$(( NOK + 1 ))
    else
        say 1 $row "  FEED $idx FAILED: $(printf '%.28s' "$u")"
    fi
    row=$(( row + 1 ))
done
if [ "$NOK" -eq 0 ]; then
    say 1 $row "  NO WORKING FEED - CHECK FEED_URL IN"
    row=$(( row + 1 ))
    say 1 $row "  paperterminal.conf AND YOUR FEED PROXY"
    row=$(( row + 1 ))
fi

row=$(( row + 1 ))
say 1 $row "$LRULE"
row=$(( row + 1 ))
say 1 $row "PRESS ANY KEY TO GET THE MENU BACK"
exit 0
