#!/usr/bin/env python3
"""Packs the plugin into dist/Pathfinder-<version>.zip for sharing.

The ZIP contains the folder Pathfinder/ so it can be unpacked straight into
the LOTRO Plugins folder. The version comes from the release tag: it is
written into the Route.plugin inside the ZIP, the file in the repository
keeps "dev". Without --version it is taken from `git describe` (v0.5 -> 0.5,
later commits -> 0.5-3-gabc1234).

Usage: python3 -I tools/package.py [--version 0.6]
"""

import argparse
import re
import subprocess
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLUGIN = ROOT / "plugin" / "Pathfinder"
DIST = ROOT / "dist"
DESCRIPTOR = "Route.plugin"


def git_version():
    try:
        out = subprocess.run(["git", "describe", "--tags", "--dirty"], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return "dev"
    return out.strip().removeprefix("v")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", help="plugin version, e.g. 0.6 (default: git describe)")
    args = parser.parse_args()
    version = (args.version or git_version()).removeprefix("v")

    descriptor = (PLUGIN / DESCRIPTOR).read_text(encoding="utf-8")
    descriptor, count = re.subn(r"<Version>[^<]*</Version>", f"<Version>{version}</Version>", descriptor)
    if count != 1:
        print(f"Kein <Version> in {DESCRIPTOR}")
        return 1

    DIST.mkdir(exist_ok=True)
    target = DIST / f"Pathfinder-{version}.zip"
    files = sorted(p for p in PLUGIN.rglob("*") if p.is_file())
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in files:
            name = Path("Pathfinder") / path.relative_to(PLUGIN)
            if path == PLUGIN / DESCRIPTOR:
                archive.writestr(str(name), descriptor)
            else:
                archive.write(path, name)
    size = target.stat().st_size / 1e6
    print(f"{target} ({len(files)} Dateien, {size:.1f} MB, Version {version})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
