#!/bin/sh
# PaperTerminal - on-device network / HTTPS self-test.
# Proves the bundled TLS stack works before you blame the feed.

. "$(dirname "$0")/common.sh"

load_conf
cls

say 1 1 "PAPERTERMINAL $PT_VERSION - NETWORK SELF-TEST"
say 1 2 "$HRULE"

say 1 4 "HTTPS STACK"
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

say 1 9 "TEST 1: HTTPS TO THE INTERNET"
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

say 1 13 "TEST 2: CONFIGURED FEED"
rm -f "$PT_TMP"
if pt_fetch "$FEED_URL?airport=$AIRPORT&dir=arr&limit=3" "$PT_TMP" \
   && grep -q '^[AD]|' "$PT_TMP" 2>/dev/null; then
    NFL="$(grep -c '^[AD]|' "$PT_TMP")"
    say 1 14 "  FEED OK - $NFL FLIGHTS FOR $AIRPORT"
    say 1 15 "  $(grep '^[AD]|' "$PT_TMP" | head -n 1 | cut -c1-44)"
else
    say 1 14 "  FEED FAILED: $(printf '%.32s' "$FEED_URL")"
    say 1 15 "  CHECK FEED_URL IN paperterminal.conf AND"
    say 1 16 "  THAT server/feed_proxy.py IS RUNNING"
fi

say 1 18 "$LRULE"
say 1 19 "PRESS ANY KEY TO GET THE MENU BACK"
exit 0
