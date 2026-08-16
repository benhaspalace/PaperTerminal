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

**Everything works out of the box with no API key**: the default data
source derives a live board from free, keyless ADS-B feeds. Keyed APIs
(FlightAware AeroAPI, aviationstack) are used **only if you explicitly
configure them** and add true schedules, origins/destinations, and actual
runway data — see [Data sources](#data-sources) for exactly what each
provides and costs.

## Features

- **Works with zero configuration**: the default data source is free and
  keyless — a live board derived from ADS-B; API keys are optional
  upgrades for true schedules and actual runway data
- Arrivals board, departures board, and a combined board that interleaves
  both directions sorted by time
- Origin airport shown for arrivals, destination for departures (with
  keyed schedule sources)
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
  first, aviationstack, then keyless adsb), and four keyless feeds behind
  the adsb source (adsb.fi, adsb.lol, adsb.one, OpenSky)
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
- Wi-Fi. **No API key is required** — the default source is keyless
  ADS-B. Optionally add a free key from
  [FlightAware AeroAPI](https://www.flightaware.com/aeroapi) and/or
  [aviationstack](https://aviationstack.com) for true schedule data
  (see [Data sources](#data-sources))

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

3. Eject, open KUAL from your books list, and pick
   **PaperTerminal Flight Board > Open PaperTerminal**. It works
   immediately — no account, no key. Run the **Network self-test**
   (N key, or from KUAL) to confirm each layer.
4. Optional: for true schedules, origins/destinations and actual runway
   data, add an API key in `extensions/paperterminal/paperterminal.conf`:

   ```
   SOURCE1=aeroapi,YOUR_AEROAPI_KEY
   SOURCE2=adsb
   ```

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
SOURCE1=adsb       # free keyless default; keyed APIs only if you
SOURCE2=           # explicitly configure them, e.g.:
SOURCE3=           #   SOURCE1=aeroapi,YOUR_KEY
                   #   SOURCE2=aviationstack,YOUR_KEY
                   #   SOURCE3=adsb
ROWS=12            # flights per board; per-side count on the map
REFRESH=5          # update interval in seconds (0 = draw once);
                   # repaints only when the content changed
RANGE=32           # live traffic map radius in nautical miles
CACHE=300          # seconds to reuse fetched data (protects API quota)
AERO_DAY=6         # AeroAPI budget: max queries per day...
AERO_MONTH=190     # ...and per calendar month (free-tier fit)
AVSTACK_MONTH=90   # aviationstack requests/month (free tier ~100)
OPENSKY_DAY=300    # anonymous OpenSky queries/day (last-resort
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

## Data sources

`bin/sources.sh` fetches straight from the configured APIs with the
bundled curl and parses everything on-device with a small awk parser (no
key-order or formatting assumptions). `SOURCE1..3` are tried in order
until one delivers; the board footer names what you're looking at
(`LIVE AIR ZRH (ADS-B EST.)`, `[SRC2]` for a backup source,
`DATA 25MIN OLD` for stale cache). Every keyed or limited API is
**budgeted client-side with persistent counters**, so PaperTerminal can't
run past a free tier by itself.

| Source | Key | Board data | Runway | FR/TO | Positions |
|---|---|---|---|---|---|
| `adsb` (default) | none | derived live | estimated on final/climb-out | — | yes |
| `aeroapi` | required | true schedules | actual, after landing/takeoff | yes | — |
| `aviationstack` | required | true schedules | — | yes | — |
| OpenSky (built-in fallback) | none | derived live | estimated | — | yes |

### `adsb` — free, keyless, the default (`SOURCE1=adsb`)

Derives a live board from ADS-B transponder data: what is actually in
the air around your airport right now. Aircraft are classified as
arrivals or departures from their track relative to the airport; the
TIME column is an **estimate** (arrival ETA or minutes-ago departure,
from distance ÷ groundspeed); on low final approach or climb-out the
runway is **estimated from the aircraft's heading** (runway numbers are
headings/10); airline names resolve from the ICAO callsign prefix via
`data/airlines.txt`. Peculiarities to know: origin/destination is
unknown (`FR/TO` shows `-`), flights not yet airborne don't appear, and
callsigns can differ from marketed flight numbers (SWR4TH vs LX318).
Data comes from adsb.fi, then adsb.lol, then adsb.one — all keyless and
speaking the same readsb "re-api" (`ADSB_URLS` reorders or extends the
list) — then OpenSky; raw responses are cached for 10 seconds. Needs the
airport's coordinates in `data/airports.txt` (3,270 bundled) and
`lib/curl`.

### `aeroapi` — FlightAware AeroAPI (`SOURCE1=aeroapi,KEY`)

True schedules: arrivals, scheduled arrivals, departures and scheduled
departures, with origin/destination airports, ICAO aircraft types, and
the **actual runway used** on flights that have landed or departed
(scheduled flights show `-` until then). Key from
flightaware.com/aeroapi; the Personal tier is a monthly usage credit
(~USD 5, roughly USD 0.025 per airport-flights query ≈ 200/month).
PaperTerminal fits that by design: one combined `/flights` query (billed
once) serves all three boards from cached raw JSON, and a persistent
counter caps calls at `AERO_DAY`/day (default 6) and `AERO_MONTH`/month
(default 190) — covering airport-search lookups too. Usage shows on the
help screen and self-test. Requires `lib/curl` (HTTPS + API-key header).
Accepts IATA and ICAO airport codes.

### `aviationstack` (`SOURCE2=aviationstack,KEY`)

True schedules with full airline names and IATA aircraft types; **no
runway data** (always `-`). Key from aviationstack.com; the free tier
allows about 100 requests per month and only plain HTTP — which is also
its unique strength here: it works even without `lib/curl` (busybox wget
fallback). Budgeted at `AVSTACK_MONTH`/month (default 90, persistent
counter). Note each combined-board refresh costs 2 requests (arrivals +
departures are separate calls), so it fits best as a backup source.

### OpenSky Network — built-in last resort, keyless

Used automatically (never configured as a SOURCE) when all three ADS-B
aggregators are unreachable: positions for the traffic map and the same
derived board, from `/states/all` with a bounding box around the
airport. Anonymous peculiarities are respected: ~400 credits/day
(budgeted at `OPENSKY_DAY`, default 300, persistent counter; 0 disables),
10-second data resolution (matched by the raw cache), metric units
(converted), and array-shaped responses (own parser, tolerant of
comma-containing country names).

All flight data is additionally cached for `CACHE` seconds (default
300), and when everything fails the last data is shown with an honest
footer (`ZRH - DATA 25MIN OLD`) instead of an empty board.

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
