#!/usr/bin/env python3
"""Builds Pathfinder routes from LotroCompanion data.

Collects every deed objective with coordinates (explorer and lore deeds),
groups them by map, orders them as a short path (nearest neighbour + 2-opt,
alternative trigger points of a landmark choose the cheapest) and writes one
Lua file per map and deed type into plugin/Pathfinder/Route/Routes/.

The map images come from lotro-maps-db as PNG (1024x768). The plugin API only
shows TGA/JPG and can't reliably scale, so they are converted to JPG in the
final display size (--scale) into plugin/Pathfinder/Route/Resources/Maps/.

Usage: python3 -I tools/build_routes.py [--types EXPLORER,LORE] [--map Breeland] [--scale 0.6]
Run tools/fetch_data.py first.
"""

import argparse
import math
import re
import sys
import urllib.request
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CACHE = ROOT / "cache"
OUT = ROOT / "plugin" / "Pathfinder" / "Route" / "Routes"
PACKAGE = "Pathfinder.Route.Routes"
MAPS_OUT = ROOT / "plugin" / "Pathfinder" / "Route" / "Resources" / "Maps"
# Image paths in the plugin are relative to the Plugins folder
MAPS_PLUGIN_PATH = "Pathfinder/Route/Resources/Maps/"
MAP_PNG_URL = "https://raw.githubusercontent.com/LotroCompanion/lotro-maps-db/master/maps/{id}.png"
MAP_SIZE = (1024, 768)

# German and English route name suffix per deed type
TYPE_NAMES = {"EXPLORER": ("Erkundung", "Exploration"), "LORE": ("Wissen", "Lore")}
METERS_PER_UNIT = 200
MIN_TARGETS = 3
# Points this far outside their deed's map (in lon/lat units) belong elsewhere
MAP_MARGIN = 0.5


def load_labels(path):
    labels = {}
    for label in ET.parse(path).getroot().iter("label"):
        labels[label.get("key")] = label.get("value", "").replace("\\q", '"')
    return labels


def load_maps(path, names_de):
    maps = {}
    for m in ET.parse(path).getroot().iter("map"):
        geo = m.find("geo")
        point = geo.find("point") if geo is not None else None
        if point is None:
            continue
        map_id = m.get("id")
        maps[map_id] = {
            "id": int(map_id),
            "name": names_de.get(map_id) or m.get("name"),
            "name_en": m.get("name"),
            "imageId": int(m.get("imageId")),
            "factor": float(geo.get("factor")),
            "lon": float(point.get("longitude")),
            "lat": float(point.get("latitude")),
            "min": (float(m.find("min").get("longitude")), float(m.find("min").get("latitude"))),
            "max": (float(m.find("max").get("longitude")), float(m.find("max").get("latitude"))),
        }
    return maps


def collect_targets(deeds_path, deed_names, marker_names, types):
    """Returns {(map_id, type): [target, ...]}; a target has 'options' (alternative points).
    map_id is None for deeds without a map, region 0 where the data has none."""
    groups = defaultdict(list)
    for deed in ET.parse(deeds_path).getroot().iter("deed"):
        deed_type = deed.get("type")
        if deed_type not in types:
            continue
        map_el = deed.find("map")
        if map_el is None:
            continue
        map_id = map_el.get("mapId")
        region = int(map_el.get("region", "0"))
        deed_id = deed.get("id")
        deed_name_en = deed.get("name")
        deed_name = deed_names.get(deed_id) or deed_name_en
        number = 0
        for objective in deed.iter("objective"):
            for cond in objective:
                points = cond.findall(".//point")
                if not points:
                    continue
                did = (cond.get("landmarkId") or cond.get("itemId") or cond.get("npcId"))
                base_name_en = cond.get("landmarkName") or cond.get("itemName") or cond.get("npcName")
                base_name = (marker_names.get(did) if did else None) or base_name_en
                options = [(float(p.get("longitude")), float(p.get("latitude"))) for p in points]
                # Several required items: every point is its own stop.
                # Otherwise the points are alternative trigger spots.
                if int(cond.get("count", "1")) > 1:
                    stops = [[o] for o in options]
                else:
                    stops = [options]
                for stop in stops:
                    number += 1
                    groups[(map_id, deed_type)].append({
                        "key": f"{deed_id}_{number}",
                        "name": base_name or f"{deed_name} ({number})",
                        "name_en": base_name_en or f"{deed_name_en} ({number})",
                        "deed": deed_name,
                        "deed_en": deed_name_en,
                        "deedId": int(deed_id),
                        "region": region,
                        "options": stop,
                    })
    return groups


def on_map(point, map_info):
    if not map_info:
        return True
    (min_lon, min_lat), (max_lon, max_lat) = map_info["min"], map_info["max"]
    return (min_lon - MAP_MARGIN <= point[0] <= max_lon + MAP_MARGIN
            and min_lat - MAP_MARGIN <= point[1] <= max_lat + MAP_MARGIN)


def load_map_regions(path):
    return {m.get("id"): int(m.get("region", "0"))
            for m in ET.parse(path).getroot().iter("parchmentMap")}


def find_map(options, region, maps, map_regions):
    """Most detailed map of the region that contains one of the options;
    the region's overview maps (factor <= 1) only as a last resort. With an
    unknown region (deeds of instances) every region is searched, but only a
    unique answer counts: the regions share their coordinates."""
    candidates = sorted((m for mid, m in maps.items()
                         if (map_regions.get(mid) == region if region else mid in map_regions)
                         and any(on_map(o, m) for o in options)),
                        key=lambda m: -m["factor"])
    if not region and len({map_regions[str(m["id"])] for m in candidates}) > 1:
        return None
    return candidates[0] if candidates else None


def assign_maps(groups, maps, map_regions, report=None):
    """Moves targets that lie outside their deed's map (or have none) to the
    most detailed map of the same region that contains them. Returns the new
    groups and the region per map (0 = unknown, e.g. instances)."""
    result = defaultdict(list)
    map_region = {}
    moved = 0
    dropped = []
    for (map_id, deed_type), targets in groups.items():
        for t in targets:
            region = t["region"] or map_regions.get(map_id, 0)
            target_map = map_id
            own = maps.get(map_id)
            if map_id is None or (own is not None and not any(on_map(o, own) for o in t["options"])):
                found = find_map(t["options"], region, maps, map_regions)
                if found is None:
                    dropped.append((deed_type, map_id, region, t))
                    continue
                target_map = str(found["id"])
                moved += 1
            t["options"] = [o for o in t["options"] if on_map(o, maps.get(target_map))]
            result[(target_map, deed_type)].append(t)
            if not map_region.get(target_map):
                map_region[target_map] = map_regions.get(target_map) or region
            t["region"] = map_region[target_map]
    print(f"{moved} Ziele auf eine andere Karte verschoben, {len(dropped)} ohne passende Karte ignoriert")
    if report is not None:
        write_dropped(report, dropped, maps)
    return result, map_region


def write_dropped(path, dropped, maps):
    lines = ["# Ziele ohne passende Karte (tools/build_routes.py)",
             "# Typ\tTat\tZiel\tRegion\tKarte der Tat\tPunkte (lon/lat)"]
    for deed_type, map_id, region, t in sorted(dropped, key=lambda d: (d[0], d[3]["deed_en"], d[3]["key"])):
        own = maps.get(map_id)
        map_text = f"{map_id} {own['name_en']}" if own else str(map_id)
        points = " ".join(f"{lon:.2f}/{lat:.2f}" for lon, lat in t["options"])
        lines.append("\t".join([deed_type, t["deed_en"], t["name_en"], str(region or "?"), map_text, points]))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


def path_length(points):
    return sum(dist(points[i], points[i + 1]) for i in range(len(points) - 1))


def order_targets(targets):
    """Short open path through all targets, choosing one option per target."""
    n = len(targets)
    if n <= 1:
        for t in targets:
            t["point"] = t["options"][0]
        return targets
    centers = [
        (sum(o[0] for o in t["options"]) / len(t["options"]),
         sum(o[1] for o in t["options"]) / len(t["options"]))
        for t in targets
    ]

    def nearest_neighbour(start):
        left = set(range(n))
        left.remove(start)
        tour = [start]
        while left:
            last = centers[tour[-1]]
            nxt = min(left, key=lambda j: dist(last, centers[j]))
            left.remove(nxt)
            tour.append(nxt)
        return tour

    best = min((nearest_neighbour(s) for s in range(n)),
               key=lambda tour: path_length([centers[i] for i in tour]))

    chosen = list(centers)
    for _ in range(4):
        # Choose the cheapest alternative given the neighbours
        for pos, i in enumerate(best):
            prev = chosen[best[pos - 1]] if pos > 0 else None
            nxt = chosen[best[pos + 1]] if pos + 1 < n else None

            def cost(p):
                return (dist(prev, p) if prev else 0) + (dist(p, nxt) if nxt else 0)

            chosen[i] = min(targets[i]["options"], key=cost)
        # 2-opt on the open path
        improved = True
        while improved:
            improved = False
            for a in range(n - 1):
                for b in range(a + 1, n):
                    p = [chosen[i] for i in best]
                    before = (dist(p[a - 1], p[a]) if a > 0 else 0) + (dist(p[b], p[b + 1]) if b + 1 < n else 0)
                    after = (dist(p[a - 1], p[b]) if a > 0 else 0) + (dist(p[a], p[b + 1]) if b + 1 < n else 0)
                    if after < before - 1e-9:
                        best[a:b + 1] = reversed(best[a:b + 1])
                        improved = True
    result = []
    for i in best:
        targets[i]["point"] = chosen[i]
        result.append(targets[i])
    return result


def lua_str(text):
    text = text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "")
    return f'"{text}"'


def lua_num(value):
    return f"{value:.5f}".rstrip("0").rstrip(".")


def module_name(map_id, deed_type):
    return f"R{map_id}_{deed_type}"


def make_map_image(map_id, scale):
    """Returns the plugin path of the JPG for a map, None if there is no image."""
    from PIL import Image

    png = CACHE / "maps-db" / "maps" / f"{map_id}.png"
    if not png.exists():
        png.parent.mkdir(parents=True, exist_ok=True)
        try:
            with urllib.request.urlopen(MAP_PNG_URL.format(id=map_id), timeout=60) as response:
                data = response.read()
        except OSError as exc:
            print(f"Kartenbild {map_id} nicht ladbar: {exc}")
            return None
        png.write_bytes(data)
    size = (round(MAP_SIZE[0] * scale), round(MAP_SIZE[1] * scale))
    jpg = MAPS_OUT / f"{map_id}.jpg"
    stale = not jpg.exists() or jpg.stat().st_mtime < png.stat().st_mtime
    if not stale:
        with Image.open(jpg) as existing:
            stale = existing.size != size
    if stale:
        MAPS_OUT.mkdir(parents=True, exist_ok=True)
        with Image.open(png) as image:
            image.convert("RGB").resize(size, Image.LANCZOS).save(jpg, quality=85)
    return MAPS_PLUGIN_PATH + jpg.name


def english(item, field):
    """English text only where it differs, the plugin falls back to German."""
    text = item.get(field + "_en")
    if not text or text == item.get(field):
        return ""
    return f", {field}_en = {lua_str(text)}"


def write_route(path, route_id, name, region, map_info, targets, image_file):
    lines = [
        "-- Generiert von tools/build_routes.py aus LotroCompanion-Daten. Nicht von Hand aendern.",
        "Pathfinder.Routes.Register({",
        f"    id = {lua_str(route_id)},",
        f"    name = {lua_str(name[0])},",
        f"    name_en = {lua_str(name[1])},",
    ]
    # Unknown for instance maps: the plugin then accepts any region
    if region:
        lines.append(f"    region = {region},")
    if map_info:
        lines.append(
            f"    map = {{ id = {map_info['id']}, image = {map_info['imageId']}, "
            f"factor = {lua_num(map_info['factor'])}, lon = {lua_num(map_info['lon'])}, "
            f"lat = {lua_num(map_info['lat'])}"
            + (f", file = {lua_str(image_file)}" if image_file else "") + " },")
    lines.append("    points = {")
    for t in targets:
        lon, lat = t["point"]
        lines.append(
            f"        {{ key = {lua_str(t['key'])}, lon = {lua_num(lon)}, lat = {lua_num(lat)}, "
            f"name = {lua_str(t['name'])}, deed = {lua_str(t['deed'])}"
            + english(t, "name") + english(t, "deed") + " },")
    lines.append("    },")
    lines.append("})")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--types", default="EXPLORER,LORE", help="deed types, comma separated")
    parser.add_argument("--map", help="only maps whose name contains this text")
    parser.add_argument("--scale", type=float, default=0.6,
                        help="map size in the game, share of 1024x768 (default 0.6)")
    parser.add_argument("--no-images", action="store_true", help="skip the map images")
    args = parser.parse_args()
    types = [t.strip().upper() for t in args.types.split(",") if t.strip()]

    deed_names = load_labels(CACHE / "lotro-data/labels/de/deeds.xml")
    marker_names = load_labels(CACHE / "maps-db/labels/de/markers.xml")
    maps = load_maps(CACHE / "maps-db/maps/maps.xml",
                     load_labels(CACHE / "maps-db/labels/de/basemaps.xml"))
    groups = collect_targets(CACHE / "lotro-data/deeds.xml", deed_names, marker_names, types)

    OUT.mkdir(parents=True, exist_ok=True)
    for old in OUT.glob("R*.lua"):
        old.unlink()

    groups, regions = assign_maps(groups, maps, load_map_regions(CACHE / "lotro-data/parchmentMaps.xml"),
                                  CACHE / "dropped_targets.txt")

    modules = []
    used_images = set()
    total_targets = 0
    for (map_id, deed_type), targets in sorted(groups.items(), key=lambda kv: (maps.get(kv[0][0], {}).get("name", ""), kv[0][1])):
        map_info = maps.get(map_id)
        map_name = map_info["name"] if map_info else f"Karte {map_id}"
        map_name_en = map_info["name_en"] if map_info else f"Map {map_id}"
        if args.map and args.map.lower() not in (map_name + " " + map_name_en).lower():
            continue
        if len(targets) < MIN_TARGETS:
            continue
        ordered = order_targets(targets)
        length_m = path_length([t["point"] for t in ordered]) * METERS_PER_UNIT
        module = module_name(map_id, deed_type)
        type_de, type_en = TYPE_NAMES.get(deed_type, (deed_type, deed_type))
        name = (f"{map_name} - {type_de}", f"{map_name_en} - {type_en}")
        image_file = None
        if map_info and not args.no_images:
            image_file = make_map_image(map_id, args.scale)
            if image_file:
                used_images.add(Path(image_file).name)
        write_route(OUT / f"{module}.lua", module, name, regions[map_id], map_info, ordered, image_file)
        modules.append(module)
        total_targets += len(ordered)
        print(f"{name[0]}: {len(ordered)} Ziele, {length_m / 1000:.1f} km")

    if not args.no_images and not args.map:
        for old in MAPS_OUT.glob("*.jpg"):
            if old.name not in used_images:
                old.unlink()

    init = ["-- Generiert von tools/build_routes.py. Laedt alle Routen.",
            f"Pathfinder.Routes.MAP_SCALE = {lua_num(args.scale)}"]
    init += [f'import "{PACKAGE}.{m}"' for m in modules]
    (OUT / "__init__.lua").write_text("\n".join(init) + "\n", encoding="utf-8")
    print(f"{len(modules)} Routen, {total_targets} Ziele -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
