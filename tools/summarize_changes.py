#!/usr/bin/env python3
"""Summarizes the changes of the generated routes as Markdown (PR text).

Compares the route and area files in plugin/Pathfinder/Route/Routes/ and the
map images of the working tree with HEAD. Prints nothing and exits with 1
when nothing changed.

Usage: python3 -I tools/summarize_changes.py > body.md
"""

import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROUTES = "plugin/Pathfinder/Route/Routes"
MAPS = "plugin/Pathfinder/Route/Resources/Maps"
MAPS_XML = ROOT / "cache" / "maps-db" / "maps" / "maps.xml"
# Targets that moved less than this (lon/lat units, 200 m each) count as unchanged
MOVE_MIN = 0.05
NAMES_MAX = 10

FIELD = re.compile(r'(\w+) = ("(?:[^"\\]|\\.)*"|-?[\d.]+)')


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, check=True, capture_output=True,
                          text=True, encoding="utf-8").stdout


def fields(line):
    result = {}
    for name, value in FIELD.findall(line):
        if value.startswith('"'):
            result[name] = value[1:-1].replace('\\"', '"').replace("\\\\", "\\")
        else:
            result.setdefault(name, float(value))
    return result


def parse(text):
    """{name, points: {key: point}} for a route, {areas: [area]} for an area file."""
    data = {"points": {}, "areas": []}
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("{ key ="):
            point = fields(line)
            data["points"][point["key"]] = point
        elif line.startswith("{ lon ="):
            data["areas"].append(fields(line))
        elif line.startswith("name_en ="):
            data["name"] = fields(line)["name_en"]
    return data


def load(head):
    """File stem -> parsed content, from HEAD or the working tree."""
    if head:
        names = git("ls-tree", "--name-only", "HEAD", ROUTES + "/").split()
        texts = {Path(n).stem: git("show", f"HEAD:{n}") for n in names}
    else:
        texts = {p.stem: p.read_text(encoding="utf-8") for p in (ROOT / ROUTES).glob("*.lua")}
    return {stem: parse(text) for stem, text in texts.items() if stem[0] in "RGA"}


def label(item, field):
    return item.get(field + "_en") or item.get(field) or "?"


def map_names(routes):
    """Map id -> English name, from maps.xml if cached, else from the routes."""
    names = {}
    for stem, route in routes.items():
        if stem.startswith("R") and "name" in route:
            names[stem[1:].split("_")[0]] = route["name"].rsplit(" - ", 1)[0]
    if MAPS_XML.exists():
        names.update((m.get("id"), m.get("name")) for m in ET.parse(MAPS_XML).getroot().iter("map"))
    return names


def name_list(points):
    names = sorted(label(p, "name") for p in points)
    more = len(names) - NAMES_MAX
    return ", ".join(names[:NAMES_MAX]) + (f" and {more} more" if more > 0 else "")


def moved(a, b):
    return abs(a["lon"] - b["lon"]) > MOVE_MIN or abs(a["lat"] - b["lat"]) > MOVE_MIN


def route_changes(old, new):
    old = {stem: r for stem, r in old.items() if stem[0] != "A"}
    new = {stem: r for stem, r in new.items() if stem[0] != "A"}
    lines = []
    for stem in sorted(set(new) - set(old), key=lambda s: new[s]["name"]):
        lines.append(f"- **New:** {new[stem]['name']} ({len(new[stem]['points'])} targets)")
    for stem in sorted(set(old) - set(new), key=lambda s: old[s]["name"]):
        lines.append(f"- **Removed:** {old[stem]['name']} ({len(old[stem]['points'])} targets)")
    for stem in sorted(set(old) & set(new), key=lambda s: new[s]["name"]):
        before, after = old[stem]["points"], new[stem]["points"]
        added = [after[k] for k in after if k not in before]
        removed = [before[k] for k in before if k not in after]
        shifted = [after[k] for k in after if k in before and moved(before[k], after[k])]
        renamed = [after[k] for k in after if k in before and label(before[k], "name") != label(after[k], "name")]
        parts = []
        if added:
            parts.append(f"+{len(added)}")
        if removed:
            parts.append(f"−{len(removed)}")
        if shifted:
            parts.append(f"{len(shifted)} moved")
        if renamed:
            parts.append(f"{len(renamed)} renamed")
        if not parts and list(before) != list(after):
            parts.append("order only")
        if not parts:
            continue
        lines.append(f"- {new[stem]['name']} ({len(after)} targets): {', '.join(parts)}")
        for title, points in (("new", added), ("removed", removed), ("moved", shifted)):
            if points:
                lines.append(f"  - {title}: {name_list(points)}")
    return lines


def area_changes(old, new, names):
    lines = []
    for stem in sorted(s for s in set(old) | set(new) if s[0] == "A"):
        map_id = stem[1:].split("_")[0]
        before = {}
        after = {}
        for areas, data in ((before, old.get(stem)), (after, new.get(stem))):
            for a in (data or {}).get("areas", ()):
                areas.setdefault(label(a, "deed"), []).append((round(a["lon"], 1), round(a["lat"], 1), a["radius"]))
        deeds = []
        for deed in sorted(set(before) | set(after)):
            b, a = before.get(deed, []), after.get(deed, [])
            if sorted(b) == sorted(a):
                continue
            if not b:
                deeds.append(f"{deed} (new, {len(a)})")
            elif not a:
                deeds.append(f"{deed} (removed)")
            elif len(a) != len(b):
                deeds.append(f"{deed} ({len(b)} → {len(a)})")
            else:
                deeds.append(f"{deed} (moved)")
        if deeds:
            more = len(deeds) - NAMES_MAX
            text = "; ".join(deeds[:NAMES_MAX]) + (f"; and {more} more" if more > 0 else "")
            lines.append(f"- {names.get(map_id, map_id)}: {text}")
    return lines


def image_changes(names):
    lines = []
    kinds = {"M": "changed", "D": "removed", "??": "new", "A": "new"}
    for line in git("status", "--porcelain", "-uall", "--", MAPS).splitlines():
        status, path = line[:2].strip(), line[3:]
        map_id = Path(path).stem
        lines.append(f"- {names.get(map_id, map_id)} ({map_id}): {kinds.get(status, status)}")
    return lines


def main():
    old, new = load(True), load(False)
    names = map_names({**old, **new})
    sections = [("Routes", route_changes(old, new)),
                ("Slayer areas", area_changes(old, new, names)),
                ("Map images", image_changes(names))]
    sections = [(title, lines) for title, lines in sections if lines]
    if not sections:
        return 1
    print("Routes regenerated from the current LotroCompanion data "
          "(`tools/fetch_data.py --markers`, `tools/build_routes.py`).")
    for title, lines in sections:
        print(f"\n### {title}\n")
        print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
