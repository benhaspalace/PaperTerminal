# PaperTerminal

A lightweight airport arrival/departure board for the **Kindle 3 Keyboard**
(K3, including the 3G EU model), running as a [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326)
extension. It turns the 600x800 e-ink screen into a classic flight board:

```
 PAPERTERMINAL                    ZRH \v ARRIVALS
 ================================================
     TIME  FLIGHT   AIRLINE           TYPE RWY
 ------------------------------------------------
 \v  13:41 LX 1073  SWISS             A20N 14
 \v  13:46 BA 710   BRITISH AIRWAYS   A320 14
 \v  13:51 WK 205   EDELWEISS         A343 16
 \v  13:54 LH 1186  LUFTHANSA         A21N 14
 \v  13:58 KL 1955  KLM               E195 16
 \v  14:02 AF 1114  AIR FRANCE        A319 14
 ------------------------------------------------
 DEMO DATA                              UPD 13:55
```

Each row shows the **time, airline, flight number, aircraft type, runway
used**, and an arrival/departure **pictogram** (`\v` = arriving,
`/^` = departing).

Everything on the device is plain POSIX shell drawn with `eips` — no Python,
no Java, no extra binaries — so it runs comfortably on the K3's 256 MB of
RAM and ancient busybox.

## Features

- Arrivals board and departures board, launched from the KUAL menu
- Default airport: pick from a preset menu, or set **any** IATA/ICAO code by
  editing a config file over USB
- Demo mode that works fully offline (sample flights with times generated
  around the current clock), enabled out of the box
- Live mode that fetches real flights over plain HTTP from a tiny feed
  proxy (`server/feed_proxy.py`) with real runway data via FlightAware
- Optional auto-refresh in live mode
- Graceful fallback: if the live feed is unreachable, the board still draws
  with demo data and says `FEED DOWN - DEMO`

## Requirements

- Kindle 3 Keyboard (Wi-Fi or 3G model), **jailbroken**
  (see the [MobileRead K3 jailbreak thread](https://www.mobileread.com/forums/showthread.php?t=122519))
- **KUAL** installed. On the K3 that is the *KUAL Kindlet* (`KUAL-*.azw2`
  placed in the `documents` folder), which also requires the kindlet
  jailbreak key from the same MobileRead resources
- For live mode only: Wi-Fi, plus any always-on machine on your LAN
  (laptop, Raspberry Pi, NAS) running Python 3 for the feed proxy

> **Note on 3G:** the K3's free 3G (Whispernet) only reaches Amazon
> services — it cannot reach your LAN or arbitrary HTTP servers. Live mode
> therefore needs Wi-Fi. Demo mode works anywhere with no network at all.

## Install

1. Plug the Kindle in over USB.
2. Copy the `extensions/paperterminal` folder from this repo into the
   Kindle's `extensions` folder, so you end up with:

   ```
   /mnt/us/extensions/paperterminal/config.xml
   /mnt/us/extensions/paperterminal/menu.json
   /mnt/us/extensions/paperterminal/bin/...
   /mnt/us/extensions/paperterminal/data/...
   ```

3. Eject, open KUAL from your books list, and you'll see
   **PaperTerminal Flight Board**.

## Usage

From the KUAL menu:

- **Arrivals board** / **Departures board** — draws the board for the
  default airport. The board stays on screen until you press a key (the
  keypress makes the Kindle repaint its normal UI — that's expected).
- **Set default airport** — pick from common airports (ZRH, GVA, LHR, LGW,
  AMS, CDG, FRA, MUC, VIE, BUD, JFK).
- **Switch demo / live mode** — toggles the data source.
- **Help + current settings** — shows the active configuration on screen.

### Configuration file

On first run the extension creates `extensions/paperterminal/paperterminal.conf`,
which you can edit over USB with any text editor:

```
AIRPORT=ZRH      # any IATA (ZRH) or, for AeroAPI, ICAO (LSZH) code
MODE=demo        # demo | live
FEED_URL=http://192.168.0.10:8091/feed
ROWS=12          # flights per board, 1..14
REFRESH=0        # live mode: redraw every N seconds (0 = draw once)
```

This is also how you set an airport that isn't in the preset menu.

## Live data

The Kindle 3's TLS stack is too old for today's HTTPS-only flight APIs, so
live mode uses a minimal plain-HTTP feed served by `server/feed_proxy.py`
on your LAN. The proxy needs only the Python 3 standard library:

```sh
# With FlightAware AeroAPI (has real runway + aircraft type data;
# personal tier is free within limits):
python3 server/feed_proxy.py --backend aeroapi --key YOUR_AEROAPI_KEY

# Or with aviationstack (free key; no runway data, shown as '-'):
python3 server/feed_proxy.py --backend aviationstack --key YOUR_KEY
```

Then set on the Kindle:

```
MODE=live
FEED_URL=http://<proxy-machine-LAN-IP>:8091/feed
```

Upstream responses are cached (default 5 minutes) so refreshing the board
doesn't burn your API quota. Runway information comes from AeroAPI's
`actual_runway_on/off` fields, so it appears on flights that have already
landed or departed; not-yet-departed scheduled flights show `-`.

### Feed protocol

Anything that can serve this trivial format over plain HTTP works as a
backend — the proxy is just a convenience:

```
GET /feed?airport=ZRH&dir=arr&limit=12

#PAPERTERMINAL 1 OK ZRH ARR
13:41|LX1073|SWISS|A20N|14
13:46|BA710|BRITISH AIRWAYS|A320|14
```

One flight per line: `TIME|FLIGHT|AIRLINE|TYPE|RUNWAY`. Lines starting with
`#` are ignored by the device.

## Repository layout

```
extensions/paperterminal/   the KUAL extension (copy this to the Kindle)
  config.xml                KUAL extension descriptor
  menu.json                 KUAL menu entries
  bin/common.sh             shared helpers (config, eips drawing)
  bin/board.sh              fetches data and draws the board
  bin/set_airport.sh        writes the default airport
  bin/set_mode.sh           demo/live toggle
  bin/help.sh               on-device help screen
  data/demo_*.txt           offline sample flights
server/feed_proxy.py        optional LAN proxy for live data
```

## Troubleshooting

- **Board flashes and disappears** — you pressed a key; the Kindle UI
  repaints over the board. Just relaunch it from KUAL.
- **`FEED DOWN - DEMO` in the footer** — the Kindle couldn't fetch
  `FEED_URL`. Check Wi-Fi is on, the proxy is running, and the IP/port are
  right. The last error is written to
  `extensions/paperterminal/paperterminal.log`.
- **Live mode shows `-` for runway** — expected for flights that haven't
  landed/departed yet, and for the aviationstack backend always.
- **Nothing appears in KUAL** — make sure the folder is
  `extensions/paperterminal` (lowercase) directly under the Kindle's
  `extensions` directory.

## License

See [LICENSE](LICENSE).
