#!/usr/bin/env python3
"""Regenerate the on-device airport database from OurAirports.

Fetches the public-domain OurAirports dataset and distills it into
extensions/paperterminal/data/airports.txt (IATA|ICAO|LAT|LON|CITY|NAME):
scheduled-service large and medium airports with an IATA code, ASCII-only
so the Kindle's eips font can render every character.

Usage: python3 build/update-airports.py
"""

import csv
import io
import pathlib
import unicodedata
import urllib.request

URL = "https://davidmegginson.github.io/ourairports-data/airports.csv"
OUT = (pathlib.Path(__file__).resolve().parent.parent
       / "extensions" / "paperterminal" / "data" / "airports.txt")


def ascii_clean(s):
    s = unicodedata.normalize("NFKD", s or "")
    return s.encode("ascii", "ignore").decode().replace("|", "/").strip()


def main():
    with urllib.request.urlopen(URL, timeout=60) as resp:
        text = resp.read().decode("utf-8")

    rows = []
    for r in csv.DictReader(io.StringIO(text)):
        if r["scheduled_service"] != "yes":
            continue
        if r["type"] not in ("large_airport", "medium_airport"):
            continue
        iata = (r["iata_code"] or "").strip().upper()
        if len(iata) != 3:
            continue
        icao = (r["icao_code"] or r["ident"] or "").strip().upper()
        try:
            lat = round(float(r["latitude_deg"]), 4)
            lon = round(float(r["longitude_deg"]), 4)
        except ValueError:
            continue
        rows.append((iata, icao, lat, lon,
                     ascii_clean(r["municipality"]), ascii_clean(r["name"])))

    rows.sort()
    with open(OUT, "w") as f:
        f.write("# Airport database: IATA|ICAO|LAT|LON|CITY|NAME\n")
        f.write("# Source: OurAirports (public domain), scheduled-service\n")
        f.write("# large+medium airports. Add your own as extra lines.\n")
        for t in rows:
            f.write("|".join(str(x) for x in t) + "\n")
    print(f"{len(rows)} airports -> {OUT}")


if __name__ == "__main__":
    main()
