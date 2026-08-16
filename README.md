# PaperTerminal

A lightweight airport arrival/departure board for the **Kindle 3 Keyboard**
(K3, including the 3G EU model), running as a [KUAL](https://www.mobileread.com/forums/showthread.php?t=203326)
extension. It turns the 600x800 e-ink screen into a classic flight board:

```
 PAPERTERMINAL                ZRH \v/^ ALL FLIGHTS
 ================================================
    TIME  FLIGHT  FR/TO AIRLINE          TYPE RWY
 ------------------------------------------------
 \v 13:41 LX318   BUD   SWISS            A20N 14
 /^ 13:44 LX316   LCY   SWISS            BCS3 28
 \v 13:46 BA710   LHR   BRITISH AIRWAYS  A320 14
 /^ 13:48 LH1187  FRA   LUFTHANSA        A21N 28
 \v 13:51 WK205   PMI   EDELWEISS        A343 16
 /^ 13:54 BA711   LHR   BRITISH AIRWAYS  A320 28
 ------------------------------------------------
 LIVE ZRH                               UPD 13:55
```

Each row shows the **time, airline, flight number, origin/destination
airport, aircraft type, runway used**, and an arrival/departure
**pictogram** (`\v` = arriving from, `/^` = departing to).

The Kindle talks **directly to public flight-data APIs** — there is no
proxy, server, or companion app. That works because the extension bundles
a statically linked **modern curl + OpenSSL + Mozilla CA bundle** (`lib/`),
so the K3 can speak today's HTTPS; its 2010-era stock curl/openssl/wget
are deliberately never used for TLS. All JSON parsing happens on-device
in a small busybox-awk parser.

## Features

- Arrivals board, departures board, and a combined board that interleaves
  both directions sorted by time
- Origin airport shown for arrivals, destination for departures
- **Live traffic map**: plots live ADS-B positions of the ROWS flights
  before and after now around your airport (`v` arriving, `^` departing,
  `+` the airport), with a distance legend — positions come straight from
  open ADS-B aggregators, no API key needed
- **Runway diagrams**: simple line drawings for ZRH, BUD, AMS and STR
  (plain-text files — add your own airport in minutes)
- **Real on-device navigation**: MENU opens the PaperTerminal menu, BACK
  returns to it (or exits), letter keys jump between screens, any other
  key redraws — no trips back to KUAL needed
- **Airport search on the keyboard**: type a code, city, or name and pick
  from ranked matches — 3,270 scheduled-service airports are bundled
  (OurAirports data), and unknown codes are looked up via AeroAPI once
  and remembered
- **Failover**: up to three data sources tried in order (e.g. AeroAPI
  first, aviationstack as backup), and multiple ADS-B sources for positions
- Boards and map auto-update every 5 seconds (configurable), with change
  detection so the e-ink only repaints when something actually changed —
  the Kindle works as a set-and-forget wall display
- Response caching on-device to protect your API quota
- Bundled HTTPS stack: static curl 8.21 with OpenSSL 3.5 LTS inside and an
  up-to-date Mozilla CA root bundle, built for the K3's ARMv6 CPU and 2.6
  kernel, verifying real certificates
- On-device network self-test that checks each layer separately
- When every source fails, the board shows a diagnostic screen naming the
  failing step instead of stale or fake data

## Requirements

- Kindle 3 Keyboard (Wi-Fi or 3G model), **jailbroken**
  (see the [MobileRead K3 jailbreak thread](https://www.mobileread.com/forums/showthread.php?t=122519))
- **KUAL** installed. On the K3 that is the *KUAL Kindlet* (`KUAL-*.azw2`
  placed in the `documents` folder), which also requires the kindlet
  jailbreak key from the same MobileRead resources
- Wi-Fi and a **free API key** from one (or both, for failover) of:
  - [FlightAware AeroAPI](https://www.flightaware.com/aeroapi) — has real
    runway-used data and ICAO aircraft types; personal tier is free within
    monthly limits
  - [aviationstack](https://aviationstack.com) — free key; no runway data
    (shown as `-`)

> **Note on 3G:** the K3's free 3G (Whispernet) only reaches Amazon
> services — it cannot reach the flight APIs. PaperTerminal needs Wi-Fi.

## Install

The easiest way: download `paperterminal-<version>.zip` from the
[Releases page](../../releases) and unzip it onto the Kindle's USB drive
root — it contains `extensions/paperterminal/…` and merges into any
existing `extensions` folder. Then continue at step 3.

From a checkout instead:

1. Plug the Kindle in over USB.
2. Copy the `extensions/paperterminal` folder from this repo into the
   Kindle's `extensions` folder, so you end up with:

   ```
   /mnt/us/extensions/paperterminal/config.xml
   /mnt/us/extensions/paperterminal/menu.json
   /mnt/us/extensions/paperterminal/bin/...
   /mnt/us/extensions/paperterminal/data/...
   /mnt/us/extensions/paperterminal/lib/...
   ```

3. Put your API key in `extensions/paperterminal/paperterminal.conf`
   (created with defaults on first run, or create it yourself):

   ```
   SOURCE1=aeroapi,YOUR_AEROAPI_KEY
   ```

4. Eject, open KUAL from your books list, and pick
   **PaperTerminal Flight Board > Open PaperTerminal**. Run the
   **Network self-test** first (N key, or from KUAL) to confirm each
   layer works.

## Usage and navigation

Open any screen from KUAL, or use **Open PaperTerminal (menu)** and
navigate entirely on the device:

| Key | Action |
|-----|--------|
| `MENU` | open the PaperTerminal menu (from any screen) |
| `BACK` | back to the menu; from the menu: exit |
| `HOME` | exit to the Kindle UI |
| `A` `D` `C` | arrivals / departures / combined board |
| `M` `R` | live traffic map / runway diagram |
| `N` `H` | network self-test / help |
| `S` | **airport search**: type a code, city, or name; five-way up/down (or arrow keys) picks a match, Enter/centre sets it as the default airport, DEL erases |
| `P` | cycle the default airport through the presets |
| any other key | redraw the current screen (re-fetches data) |

Boards and the traffic map keep updating themselves every `REFRESH`
seconds (default 5) while shown — data is re-read from the cache layer
(so the API budget is untouched) and the screen only repaints when
something actually changed. A keypress always interrupts the updater
immediately. When a screen is auto-updating, the navigation session's
idle timeout is extended from 10 minutes to 4 hours, so a board can run
as a wall display.

In the search screen, matches are ranked exact code → code prefix → city
prefix → any substring, over the bundled 3,270-airport database. A code
that isn't in the database can still be selected with Enter: it is looked
up once via AeroAPI and appended to `data/airports.txt`, so the traffic
map gets its coordinates too.

Two Kindle quirks are handled for you: KUAL repaints its own menu right
after launching an action (racing whatever the action draws), so screens
draw after a short settle delay; and because the Kindle framework still
sees your keypresses underneath, the current screen simply redraws over
whatever the framework painted. If the navigation keys don't respond,
run **Key test (navigation setup)** from KUAL and put the codes it shows
into `KEY_MENU`/`KEY_BACK`/`KEY_HOME` in the config file.

### Configuration file

`extensions/paperterminal/paperterminal.conf`, editable over USB:

```
AIRPORT=ZRH        # any IATA (ZRH) or ICAO (LSZH) code
SOURCE1=aeroapi,YOUR_KEY         # tried first
SOURCE2=aviationstack,YOUR_KEY   # optional backup source
SOURCE3=                         # optional third source
ROWS=12            # flights per board; per-side count on the map
REFRESH=5          # update interval in seconds (0 = draw once);
                   # repaints only when the content changed
RANGE=32           # live traffic map radius in nautical miles
CACHE=300          # seconds to reuse fetched data (protects API quota)
AERO_DAY=6         # AeroAPI budget: max queries per day...
AERO_MONTH=190     # ...and per calendar month (free-tier fit)
OPENSKY_DAY=300    # anonymous OpenSky queries/day (last position
                   # fallback; ~400 allowed, 0 disables)
KEY_MENU=139       # navigation keycodes - see the key test screen
KEY_BACK=158
KEY_HOME=102
KEY_UP=103         # five-way, used in the search screen
KEY_DOWN=108
KEY_SELECT=194
```

Airports can also be set here directly (`AIRPORT=XXX`), but the search
screen (`S`) is the comfortable way. The traffic map needs the airport's
coordinates from `data/airports.txt` (format
`IATA|ICAO|LAT|LON|CITY|NAME`) — 3,270 airports are bundled, unknown
codes are auto-added via AeroAPI on selection, and the **Refresh airport
database** GitHub Actions workflow regenerates the file from the
public-domain OurAirports dataset.

## Flight data — direct from public APIs

`bin/sources.sh` fetches straight from the configured APIs with the
bundled curl and parses the JSON on-device with a small awk object
scanner (no key-order or formatting assumptions):

- **AeroAPI** (`SOURCE1=aeroapi,KEY`): arrivals, scheduled arrivals,
  departures and scheduled departures per airport, with **actual runway
  used** on flights that have landed/departed and ICAO aircraft types.
  Requires the bundled curl (HTTPS + API-key header). One combined
  `/flights` query (billed once) carries all four groups, and its raw
  JSON is cached, so switching between the arrivals, departures and
  combined boards costs nothing extra.
- **aviationstack** (`SOURCE2=aviationstack,KEY`): full airline names and
  IATA aircraft types, no runway data. Works over plain HTTP, so it even
  functions without `lib/curl`.
- **ADS-B positions** (no key): the traffic map asks adsb.fi (then
  adsb.lol as fallback; order configurable via `ADSB_URLS`, and the
  OpenSky Network as a last resort) for all aircraft around the airport
  in one call, matches them to flights by callsign, and plots east/north
  offsets computed in awk. Position results are cached for 10 seconds.
  OpenSky's anonymous API allows roughly 400 credits per day at 10-second
  data resolution, so its calls are capped client-side (`OPENSKY_DAY`,
  default 300, persistent counter) — the same budget pattern used for
  AeroAPI.

Sources are tried in order until one delivers; the board footer notes
when a backup source answered (`BACKUP SOURCE 2`). Responses are cached
in `/tmp` for `CACHE` seconds, so redraws don't burn API quota. Airline
codes are mapped to display names via `data/airlines.txt`.

### Staying inside the AeroAPI free tier

FlightAware's Personal tier is a monthly usage credit (about USD 5, at
roughly USD 0.025 per airport-flights query — around 200 queries a
month). PaperTerminal enforces that **client-side**: a persistent
counter (`aeroapi.usage`) caps AeroAPI calls at `AERO_DAY` per day
(default 6) and `AERO_MONTH` per calendar month (default 190, leaving a
margin), covering board fetches and airport lookups alike. When the
budget is spent, the next source takes over; if none is configured, the
last data is shown with an honest footer like `ZRH - DATA 25MIN OLD`
instead of an empty board. Current usage is shown on the help screen and
in the network self-test. If FlightAware changes their pricing, adjust
the two caps in the config.

## Bundled HTTPS stack

`extensions/paperterminal/lib/` ships three files that replace the
Kindle's stock TLS tooling:

| File         | What it is |
|--------------|------------|
| `curl`       | curl 8.21.0, statically linked (musl), OpenSSL 3.5.7 LTS inside, http/https only |
| `openssl`    | OpenSSL 3.5.7 CLI (`s_client` etc.), statically linked, for debugging |
| `cacert.pem` | Mozilla CA root bundle from <https://curl.se/ca/cacert.pem> |

All fetches go through the bundled curl with `--cacert lib/cacert.pem`,
so certificates are properly verified against current roots. The binaries
target ARMv5 soft-float musl, so they run on the K3's ARMv6 CPU and
2.6.26 kernel with no firmware dependencies (OpenSSL is built with
`--with-rand-seed=devrandom` because that kernel predates `getrandom()`).
Some firmwares mount `/mnt/us` noexec; the extension detects that and
runs a copy of curl from `/var/tmp` automatically.

Provenance: `lib/BUILDINFO.txt` records source versions and checksums,
`lib/SHA256SUMS` the shipped binaries. Rebuild reproducibly with
`build/build-https-stack.sh` on any Linux host, or run the **HTTPS stack**
GitHub Actions workflow, which rebuilds from upstream sources (pinned or
`latest`), verifies publisher checksums, runs TLS handshake smoke tests
under qemu-arm, uploads the bundle as an artifact, and can commit the
refreshed bundle back to the branch. Use the same workflow to refresh
`cacert.pem` periodically.

## Repository layout

```
extensions/paperterminal/   the KUAL extension (copy this to the Kindle)
  config.xml                KUAL extension descriptor
  menu.json                 KUAL menu entries
  bin/nav.sh                navigation hub: hardware keys, menu, key test
  bin/sources.sh            direct API clients + awk JSON parser + cache
  bin/board.sh              arrival/departure/combined boards
  bin/radar.sh              live traffic map from ADS-B positions
  bin/runways.sh            runway diagram viewer
  bin/set_airport.sh        writes the default airport (KUAL submenu)
  bin/nettest.sh            network / HTTPS / sources self-test
  bin/help.sh               help + current settings screen
  bin/common.sh             shared helpers (config, eips drawing, fetching)
  data/airports.txt         searchable airport database (3,270 airports)
  data/airlines.txt         IATA airline code -> display name
  data/runways/*.txt        runway line drawings (ZRH, BUD, AMS, STR)
  lib/curl                  static modern curl + OpenSSL for the K3
  lib/openssl               static OpenSSL CLI for debugging
  lib/cacert.pem            Mozilla CA root bundle
  lib/BUILDINFO.txt         provenance: versions, checksums, target
build/build-https-stack.sh  reproducible cross-build of lib/ from source
build/update-airports.py    regenerate the airport database (OurAirports)
.github/workflows/          CI: HTTPS-stack rebuild, airport-db refresh,
                            and release packaging (tag v* or manual run
                            publishes the ready-to-copy zip)
```

## Troubleshooting

- **The KUAL menu pops back over my screen** — launch screens through
  `nav.sh` entries (all bundled menu items do this). The hub waits out
  KUAL's repaint and then re-takes the screen on every keypress. If you
  still lose the screen, press any letter key — the current screen
  redraws.
- **Navigation keys do nothing** — your firmware may use different
  keycodes. Run **Key test (navigation setup)** from KUAL, press the
  Menu/Back/Home keys, and put the codes shown into `KEY_MENU`,
  `KEY_BACK`, `KEY_HOME` in `paperterminal.conf`.
- **`ALL CONFIGURED DATA SOURCES FAILED` screen** — run the network
  self-test: it checks the TLS stack, internet reachability, each source,
  and ADS-B separately. The most common cause is a missing API key in
  `SOURCE1=`. Errors are appended to
  `extensions/paperterminal/paperterminal.log`.
- **Suspected crash** — the same log captures stderr of the navigation
  hub; check its tail. The hub also exits by itself after 10 minutes of
  inactivity, so stray processes don't linger.
- **`-` shown for runway** — expected for flights that haven't
  landed/departed yet, and for the aviationstack source always.
- **Map shows `NO POS` for most flights** — normal for flights not
  currently airborne; also check the airport has coordinates in
  `data/airports.txt` and that ADS-B passes in the self-test.
- **Nothing appears in KUAL** — make sure the folder is
  `extensions/paperterminal` (lowercase) directly under the Kindle's
  `extensions` directory.

## License

See [LICENSE](LICENSE).
