#!/bin/sh
# PaperTerminal - switch between demo and live data.
# usage: set_mode.sh [demo|live|toggle]

. "$(dirname "$0")/common.sh"

load_conf

case "$1" in
    demo) MODE="demo" ;;
    live) MODE="live" ;;
    *)    if [ "$MODE" = "demo" ]; then MODE="live"; else MODE="demo"; fi ;;
esac

save_conf

if [ "$MODE" = "live" ]; then
    splash "MODE SET TO: LIVE" \
           "FEED: $FEED_URL" \
           "NEEDS WI-FI + A RUNNING FEED PROXY"
else
    splash "MODE SET TO: DEMO" \
           "BUNDLED SAMPLE FLIGHTS, WORKS OFFLINE" \
           "TIMES ARE GENERATED AROUND THE CLOCK"
fi
exit 0
