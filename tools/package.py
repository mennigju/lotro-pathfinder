#!/usr/bin/env python3
"""Packs the plugin into dist/Pathfinder-<version>.zip for sharing.

The ZIP contains the folder Pathfinder/ so it can be unpacked straight into
the LOTRO Plugins folder.

Usage: python3 -I tools/package.py
"""

import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugin" / "Pathfinder"
DIST = ROOT / "dist"


def main():
    descriptor = (PLUGIN / "Route.plugin").read_text(encoding="utf-8")
    version = re.search(r"<Version>([^<]+)</Version>", descriptor).group(1).strip()
    DIST.mkdir(exist_ok=True)
    target = DIST / f"Pathfinder-{version}.zip"
    files = sorted(p for p in PLUGIN.rglob("*") if p.is_file())
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            archive.write(path, Path("Pathfinder") / path.relative_to(PLUGIN))
    size = target.stat().st_size / 1e6
    print(f"{target} ({len(files)} Dateien, {size:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
