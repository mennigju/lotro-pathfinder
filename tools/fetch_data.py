#!/usr/bin/env python3
"""Downloads the LotroCompanion data build_routes.py needs into cache/.

With --markers it also loads the map markers of lotro-maps-db (~650 MB, every
spawn of every monster), which build_routes.py needs for the slayer areas.

Usage: python3 -I tools/fetch_data.py [--force] [--markers]
"""

import argparse
import json
import sys
import urllib.request
from pathlib import Path

CACHE = Path(__file__).resolve().parent.parent / "cache"
RAW = "https://raw.githubusercontent.com/LotroCompanion/{repo}/master/{path}"
TREE = "https://api.github.com/repos/LotroCompanion/lotro-maps-db/git/trees/master?recursive=1"

FILES = [
    ("lotro-data", "lore/deeds.xml", "lotro-data/deeds.xml"),
    ("lotro-data", "lore/mobs.xml", "lotro-data/mobs.xml"),
    ("lotro-data", "lore/geoAreas.xml", "lotro-data/geoAreas.xml"),
    ("lotro-data", "lore/labels/de/deeds.xml", "lotro-data/labels/de/deeds.xml"),
    ("lotro-data", "lore/parchmentMaps.xml", "lotro-data/parchmentMaps.xml"),
    ("lotro-maps-db", "maps/maps.xml", "maps-db/maps/maps.xml"),
    ("lotro-maps-db", "labels/de/basemaps.xml", "maps-db/labels/de/basemaps.xml"),
    ("lotro-maps-db", "labels/de/markers.xml", "maps-db/labels/de/markers.xml"),
]


def download(repo, path, target, force, quiet=False):
    dest = CACHE / target
    if dest.exists() and not force:
        if not quiet:
            print(f"vorhanden: {target}")
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    url = RAW.format(repo=repo, path=path)
    print(f"lade {url}")
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    tmp = dest.with_suffix(dest.suffix + ".part")
    tmp.write_bytes(data)
    tmp.replace(dest)


def marker_files():
    with urllib.request.urlopen(TREE, timeout=60) as response:
        tree = json.load(response)["tree"]
    return [e["path"] for e in tree
            if e["type"] == "blob" and e["path"].startswith("markers/") and e["path"].endswith(".xml")]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--force", action="store_true", help="download even if present")
    parser.add_argument("--markers", action="store_true", help="also load the map markers (~650 MB)")
    args = parser.parse_args()
    for repo, path, target in FILES:
        download(repo, path, target, args.force)
    if args.markers:
        paths = marker_files()
        for path in paths:
            download("lotro-maps-db", path, "maps-db/" + path, args.force, quiet=True)
        print(f"{len(paths)} Markerdateien in {CACHE / 'maps-db' / 'markers'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
