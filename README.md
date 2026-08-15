# PaperTerminal

A lightweight airport arrival/departure board for the **Kindle 3 Keyboard**
(K3, including the 3G EU model), running as a [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326)
extension. It turns the 600x800 e-ink screen into a classic flight board:

```
 PAPERTERMINAL                ZRH \v/^ ALL FLIGHTS
 ================================================
    TIME  FLIGHT  FR/TO AIRLINE          TYPE RWY
 ------------------------------------------------
 \v 13:41 LX 1073 BUD   SWISS            A20N 14
 /^ 13:44 LX 316  LCY   SWISS            BCS3 28
 \v 13:46 BA 710  LHR   BRITISH AIRWAYS  A320 14
 /^ 13:48 LH 1187 FRA   LUFTHANSA        A21N 28
 \v 13:51 WK 205  PMI   EDELWEISS        A343 16
 /^ 13:54 BA 711  LHR   BRITISH AIRWAYS  A320 28
 ------------------------------------------------
 LIVE ZRH                               UPD 13:55
```

Each row shows the **time, airline, flight number, origin/destination
airport, aircraft type, runway used**, and an arrival/departure
**pictogram** (`\v` = arriving from, `/^` = departing to).

Everything on the device is plain POSIX shell drawn with `eips`, plus a
bundled, statically linked **modern curl + OpenSSL + Mozilla CA bundle**
(`lib/`) so the Kindle can speak today's HTTPS — the K3's stock
curl/openssl/wget are 2010-era and deliberately never used for TLS.

## Features

- Arrivals board, departures board, and a combined board that interleaves
  both directions sorted by time, launched from the KUAL menu
- Origin airport shown for arrivals, destination for departures
- Default airport: pick from a preset menu, or set **any** IATA/ICAO code by
  editing a config file over USB
- Live flight data from a tiny feed proxy (`server/feed_proxy.py`) with
  real runway data via FlightAware
- Bundled HTTPS stack: static curl 8.21 with OpenSSL 3.5 LTS inside and an
  up-to-date Mozilla CA root bundle, built for the K3's ARMv6 CPU and 2.6
  kernel — `https://` feed URLs work, verified against real certificates,
  so the proxy can live anywhere on the internet, not just your LAN
- On-device network self-test screen (checks the TLS stack, then the feed)
- Optional auto-refresh
- When the feed is unreachable, the board shows a diagnostic screen that
  points at the failing step instead of stale or fake data

## Requirements

- Kindle 3 Keyboard (Wi-Fi or 3G model), **jailbroken**
  (see the [MobileRead K3 jailbreak thread](https://www.mobileread.com/forums/showthread.php?t=122519))
- **KUAL** installed. On the K3 that is the *KUAL Kindlet* (`KUAL-*.azw2`
  placed in the `documents` folder), which also requires the kindlet
  jailbreak key from the same MobileRead resources
- Wi-Fi, plus any machine running Python 3 for the feed proxy — on your
  LAN or anywhere on the internet behind HTTPS

> **Note on 3G:** the K3's free 3G (Whispernet) only reaches Amazon
> services — it cannot reach your feed. PaperTerminal needs Wi-Fi.

## Install

1. Plug the Kindle in over USB.
2. Copy the `extensions/paperterminal` folder from this repo into the
   Kindle's `extensions` folder, so you end up with:

   ```
   /mnt/us/extensions/paperterminal/config.xml
   /mnt/us/extensions/paperterminal/menu.json
   /mnt/us/extensions/paperterminal/bin/...
   /mnt/us/extensions/paperterminal/lib/...
   ```

3. Start the feed proxy somewhere (see [Flight data](#flight-data)) and put
   its address in `paperterminal.conf` as `FEED_URL` — the file is created
   with defaults on first run, or create it yourself over USB.
4. Eject, open KUAL from your books list, and you'll see
   **PaperTerminal Flight Board**. Run **Network self-test (HTTPS)** first
   to confirm the Kindle can reach your feed.

## Usage

From the KUAL menu:

- **Arrivals board** / **Departures board** / **Combined board** — draws
  the board for the default airport (the combined board mixes arrivals and
  departures, sorted by time). The board stays on screen until you press a
  key (the keypress makes the Kindle repaint its normal UI — that's
  expected).
- **Set default airport** — pick from common airports (ZRH, GVA, LHR, LGW,
  AMS, CDG, FRA, MUC, VIE, BUD, JFK).
- **Network self-test (HTTPS)** — checks the bundled TLS stack, then an
  HTTPS fetch from the internet, then your configured feed.
- **Help + current settings** — shows the active configuration on screen.

If the feed can't be reached, the board draws a diagnostic screen naming
the URL it tried and the usual causes, instead of showing stale data.

### Configuration file

On first run the extension creates `extensions/paperterminal/paperterminal.conf`,
which you can edit over USB with any text editor:

```
AIRPORT=ZRH      # any IATA (ZRH) or, for AeroAPI, ICAO (LSZH) code
FEED_URL=http://192.168.0.10:8091/feed   # or https://... (bundled curl)
ROWS=12          # flights per board, 1..14
REFRESH=0        # redraw every N seconds (0 = draw once)
```

This is also how you set an airport that isn't in the preset menu.

## Bundled HTTPS stack

`extensions/paperterminal/lib/` ships three files that replace the
Kindle's stock TLS tooling:

| File         | What it is |
|--------------|------------|
| `curl`       | curl 8.21.0, statically linked (musl), OpenSSL 3.5.7 LTS inside, http/https only |
| `openssl`    | OpenSSL 3.5.7 CLI (`s_client` etc.), statically linked, for debugging |
| `cacert.pem` | Mozilla CA root bundle from <https://curl.se/ca/cacert.pem> |

All fetches go through the bundled curl with `--cacert lib/cacert.pem`, so
certificates are properly verified against current roots. The binaries
target ARMv5 soft-float musl, so they run on the K3's ARMv6 CPU and 2.6.26
kernel with no firmware dependencies (OpenSSL is built with
`--with-rand-seed=devrandom` because that kernel predates `getrandom()`).
If `lib/curl` is missing or not runnable, the extension quietly falls back
to busybox wget, which limits `FEED_URL` to plain `http://`.

Provenance: `lib/BUILDINFO.txt` records source versions and checksums,
`lib/SHA256SUMS` the shipped binaries. Rebuild reproducibly with
`build/build-https-stack.sh` on any Linux host, or run the **HTTPS stack**
GitHub Actions workflow, which rebuilds from upstream sources (pinned or
`latest`), verifies publisher checksums, runs TLS handshake smoke tests
under qemu-arm, uploads the bundle as an artifact, and can commit the
refreshed bundle back to the branch. Use the same workflow to refresh
`cacert.pem` periodically.

Use the KUAL menu's **Network self-test (HTTPS)** to verify the stack on
the device: it checks `lib/curl` runs, fetches an HTTPS page with
certificate verification, then tests your configured feed.

## Flight data

The board reads a minimal text feed served by `server/feed_proxy.py`. The
proxy needs only the Python 3 standard library:

```sh
# With FlightAware AeroAPI (has real runway + aircraft type data;
# personal tier is free within limits):
python3 server/feed_proxy.py --backend aeroapi --key YOUR_AEROAPI_KEY

# Or with aviationstack (free key; no runway data, shown as '-'):
python3 server/feed_proxy.py --backend aviationstack --key YOUR_KEY
```

Then set on the Kindle:

```
FEED_URL=http://<proxy-machine-LAN-IP>:8091/feed
```

or, with the proxy hosted anywhere behind a TLS reverse proxy or tunnel
(the bundled curl verifies the certificate against `lib/cacert.pem`):

```
FEED_URL=https://your-host.example.com/feed
```

Upstream responses are cached (default 5 minutes) so refreshing the board
doesn't burn your API quota. Runway information comes from AeroAPI's
`actual_runway_on/off` fields, so it appears on flights that have already
landed or departed; not-yet-departed scheduled flights show `-`.

### Feed protocol

Anything that can serve this trivial format over plain HTTP works as a
backend — the proxy is just a convenience:

```
GET /feed?airport=ZRH&dir=all&limit=12      dir: arr | dep | all

#PAPERTERMINAL 2 OK ZRH ALL
A|13:41|LX1073|SWISS|A20N|14|BUD
D|13:44|LX316|SWISS|BCS3|28|LCY
```

One flight per line: `DIR|TIME|FLIGHT|AIRLINE|TYPE|RUNWAY|AIRPORT`, where
`DIR` is `A` (arrival) or `D` (departure) and `AIRPORT` is the origin for
arrivals and the destination for departures. `dir=all` returns both
directions interleaved and sorted by time. Lines starting with `#` are
ignored by the device.

## Repository layout

```
extensions/paperterminal/   the KUAL extension (copy this to the Kindle)
  config.xml                KUAL extension descriptor
  menu.json                 KUAL menu entries
  bin/common.sh             shared helpers (config, eips drawing, fetching)
  bin/board.sh              fetches the feed and draws the board
  bin/set_airport.sh        writes the default airport
  bin/nettest.sh            on-device network / HTTPS self-test
  bin/help.sh               on-device help screen
  lib/curl                  static modern curl + OpenSSL for the K3
  lib/openssl               static OpenSSL CLI for debugging
  lib/cacert.pem            Mozilla CA root bundle
  lib/BUILDINFO.txt         provenance: versions, checksums, target
build/build-https-stack.sh  reproducible cross-build of lib/ from source
.github/workflows/          CI: rebuild + test + refresh the HTTPS stack
server/feed_proxy.py        feed proxy for live data (LAN or internet)
```

## Troubleshooting

- **Board flashes and disappears** — you pressed a key; the Kindle UI
  repaints over the board. Just relaunch it from KUAL.
- **`FEED UNREACHABLE OR INVALID` screen** — the Kindle couldn't fetch or
  parse `FEED_URL`. Run the **Network self-test (HTTPS)** from the KUAL
  menu: it tells you whether the TLS stack, the internet connection, or
  the feed itself is the problem. The last error is written to
  `extensions/paperterminal/paperterminal.log`.
- **`https://` feed fails but http works** — make sure the `lib/` folder
  was copied to the Kindle along with the rest of the extension. Some
  firmwares mount `/mnt/us` noexec; the extension handles that
  automatically by running a copy of curl from `/var/tmp`.
- **`-` shown for runway** — expected for flights that haven't
  landed/departed yet, and for the aviationstack backend always.
- **Nothing appears in KUAL** — make sure the folder is
  `extensions/paperterminal` (lowercase) directly under the Kindle's
  `extensions` directory.

## License

See [LICENSE](LICENSE).
