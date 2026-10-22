#!/usr/bin/env python3
"""Downloads the LotroCompanion data build_routes.py needs into cache/.

Usage: python3 -I tools/fetch_data.py [--force]
"""

import argparse
import sys
import urllib.request
from pathlib import Path

CACHE = Path(__file__).resolve().parent.parent / "cache"
RAW = "https://raw.githubusercontent.com/LotroCompanion/{repo}/master/{path}"

FILES = [
    ("lotro-data", "lore/deeds.xml", "lotro-data/deeds.xml"),
    ("lotro-data", "lore/labels/de/deeds.xml", "lotro-data/labels/de/deeds.xml"),
    ("lotro-data", "lore/parchmentMaps.xml", "lotro-data/parchmentMaps.xml"),
    ("lotro-maps-db", "maps/maps.xml", "maps-db/maps/maps.xml"),
    ("lotro-maps-db", "labels/de/basemaps.xml", "maps-db/labels/de/basemaps.xml"),
    ("lotro-maps-db", "labels/de/markers.xml", "maps-db/labels/de/markers.xml"),
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="download even if present")
    args = parser.parse_args()
    for repo, path, target in FILES:
        dest = CACHE / target
        if dest.exists() and not args.force:
            print(f"vorhanden: {target}")
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        url = RAW.format(repo=repo, path=path)
        print(f"lade {url}")
        with urllib.request.urlopen(url, timeout=60) as response:
            data = response.read()
        tmp = dest.with_suffix(dest.suffix + ".part")
        tmp.write_bytes(data)
        tmp.replace(dest)
    return 0


if __name__ == "__main__":
    sys.exit(main())
