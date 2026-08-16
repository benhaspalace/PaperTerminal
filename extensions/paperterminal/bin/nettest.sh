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

say 1 9 "TEST 2: CONNECTION"
NETIF="$(awk '$2 == "00000000" { print $1; exit }' /proc/net/route 2>/dev/null)"
NS="$(grep -c '^nameserver' /etc/resolv.conf 2>/dev/null)"
case "$NETIF" in
    wlan*|eth*)
        say 1 10 "  DEFAULT ROUTE: $NETIF (WI-FI) - GOOD" ;;
    ppp*|wan*|usb*)
        say 1 10 "  DEFAULT ROUTE: $NETIF - THIS IS 3G!"
        say 1 11 "  3G ONLY REACHES AMAZON. TURN WI-FI ON." ;;
    '')
        say 1 10 "  NO DEFAULT ROUTE - NO NETWORK AT ALL"
        say 1 11 "  CONNECT WI-FI IN THE KINDLE SETTINGS" ;;
    *)
        say 1 10 "  DEFAULT ROUTE: $NETIF" ;;
esac
say 1 12 "  DNS SERVERS: ${NS:-0}   CLOCK: $(date '+%Y-%m-%d %H:%M')"
say 1 13 "  (TLS NEEDS A ROUGHLY CORRECT CLOCK)"
MF="$(awk '/^MemFree/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
MC="$(awk '/^Cached/ {print $2; exit}' /proc/meminfo 2>/dev/null)"
UV="$(ulimit -v 2>/dev/null)"
case "$UV" in unlimited) UV=max;; '') UV='?';; esac
say 1 14 "  RAM FREE ${MF:-?}K CACHE ${MC:-?}K ULIM-V $UV"

say 1 15 "TEST 3: INTERNET (RAW IP, THEN DNS + TLS)"
if [ -n "$CURLBIN" ]; then
    # Raw-IP probe first: succeeds even when DNS is broken.
    IPC="$("$CURLBIN" -sS --connect-timeout 8 -m 15 --cacert "$PT_CACERT" \
        -o /dev/null -w '%{http_code}' https://1.1.1.1/ 2>"$PT_TMP.err")"
    if [ -n "$IPC" ] && [ "$IPC" != "000" ]; then
        say 1 16 "  IP 1.1.1.1 HTTPS: OK (REACHES INTERNET)"
    else
        say 1 16 "  IP 1.1.1.1 HTTPS: $(head -n 2 "$PT_TMP.err" | tr -d '\r\n' | cut -c8-33)"
    fi
    CODE="$("$CURLBIN" -sS --connect-timeout 10 -m 20 --cacert "$PT_CACERT" \
        -o /dev/null -w '%{http_code}' https://example.com/ 2>"$PT_TMP.err")"
    if [ "$CODE" = "200" ]; then
        say 1 17 "  example.com: OK (HTTP 200, CERT VERIFIED)"
    else
        say 1 17 "  example.com: FAILED (${CODE:-no reply})"
        say 1 18 "  $(head -n 2 "$PT_TMP.err" | tr -d '\r\n' | cut -c8-52)"
        cat "$PT_TMP.err" >> "$PT_LOG" 2>/dev/null
    fi
    # TLS cross-check with the bundled openssl CLI: if this works where
    # curl reports out-of-memory, the problem is curl-specific; if both
    # fail the same way, it's the environment (RAM/limits/network).
    OSSL="$(pt_openssl_bin)"
    if [ -n "$OSSL" ]; then
        ( echo | "$OSSL" s_client -connect example.com:443 \
            -CAfile "$PT_CACERT" -verify_return_error -quiet \
            >/dev/null 2>"$PT_TMP.err" ) &
        SCPID=$!
        n=0
        while kill -0 "$SCPID" 2>/dev/null; do
            n=$(( n + 1 ))
            [ $n -gt 12 ] && kill "$SCPID" 2>/dev/null
            sleep 1
        done
        wait "$SCPID" 2>/dev/null
        if [ $? -eq 0 ]; then
            say 1 19 "  openssl s_client: OK (TLS CROSS-CHECK)"
        else
            say 1 19 "  openssl s_client: $(head -n 1 "$PT_TMP.err" | cut -c1-27)"
            cat "$PT_TMP.err" >> "$PT_LOG" 2>/dev/null
        fi
    fi
    rm -f "$PT_TMP.err"
else
    say 1 16 "  SKIPPED - NO RUNNABLE lib/curl"
fi

say 1 20 "TEST 4: FLIGHT DATA SOURCES (EACH IN TURN)"
row=21
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
    say 1 $row "  NO WORKING SOURCE - SEE TESTS 2 AND 3;"
    row=$(( row + 1 ))
    say 1 $row "  KEYED SOURCES ALSO NEED VALID API KEYS"
    row=$(( row + 1 ))
fi
aero_load_usage
say 1 $row "  AEROAPI BUDGET: $UDC/$AERO_DAY TODAY, $UMC/$AERO_MONTH MONTH"
row=$(( row + 2 ))

say 1 $row "TEST 5: ADS-B POSITIONS (TRAFFIC MAP)"
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
