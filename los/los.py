#!/usr/bin/env python3

"""
los.py — LoRa 915 MHz LOS / Fresnel + link budget analyzer for KML sites.

Usage:
    python los.py analyze                      # analyze ~/Downloads/TWP-LOS.kml
    python los.py analyze path/to/file.kml
    python los.py list
    python los.py list path/to/file.kml
    python los.py set "Gate House" antenna_height 6
    python los.py set "Gate House" antenna_height 6 path/to/file.kml
"""

import argparse
import json
import math
import itertools
import os
import time
import requests
import xml.etree.ElementTree as ET

EARTH_RADIUS  = 6371000.0
DEFAULT_KML   = os.path.expanduser("~/Downloads/TWP-LOS.kml")
KML_NS        = "http://www.opengis.net/kml/2.2"
ET.register_namespace("", KML_NS)


# ------------------------------------------------------------
# RF link budget
# ------------------------------------------------------------

def free_space_path_loss(distance_m, freq_mhz):
    return 20 * math.log10(distance_m) + 20 * math.log10(freq_mhz * 1e6) - 147.55


def link_budget(distance_m, freq_mhz, tx_dbm, rx_sensitivity_dbm,
                forest_db_per_m, forest_terminal_depth_m):
    fspl     = free_space_path_loss(distance_m, freq_mhz)
    # Foliage applied at both terminals; mid-path travels mostly through air.
    foliage  = 2 * forest_db_per_m * forest_terminal_depth_m
    margin   = (tx_dbm - rx_sensitivity_dbm) - fspl - foliage
    return {"fspl_db": fspl, "foliage_db": foliage, "margin_db": margin}


# ------------------------------------------------------------
# Geometry
# ------------------------------------------------------------

def haversine(lat1, lon1, lat2, lon2):
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a  = math.sin(dp/2)**2 + math.cos(p1) * math.cos(p2) * math.sin(dl/2)**2
    return 2 * EARTH_RADIUS * math.asin(math.sqrt(a))


def fresnel_radius(d1, d2, freq_mhz):
    wavelength = 299792458.0 / (freq_mhz * 1e6)
    return math.sqrt((wavelength * d1 * d2) / (d1 + d2))


def earth_curvature_bulge(d1, d2):
    return (d1 * d2) / (2 * EARTH_RADIUS)


# ------------------------------------------------------------
# KML parsing and editing
# ------------------------------------------------------------

def _ns(tag):
    return f"{{{KML_NS}}}{tag}"


def _parse_extended_data(placemark):
    """Return dict of name→value from <ExtendedData><Data> elements."""
    attrs = {}
    ed = placemark.find(_ns("ExtendedData"))
    if ed is not None:
        for data in ed.findall(_ns("Data")):
            name = data.get("name")
            val_el = data.find(_ns("value"))
            if name and val_el is not None and val_el.text:
                attrs[name] = val_el.text.strip()
    return attrs


def parse_kml(path):
    tree = ET.parse(path)
    root = tree.getroot()
    points = []

    for placemark in root.findall(f".//{_ns('Placemark')}"):
        name_el  = placemark.find(_ns("name"))
        point_el = placemark.find(f".//{_ns('Point')}")

        if name_el is None or point_el is None:
            continue

        coord_el = point_el.find(_ns("coordinates"))
        if coord_el is None:
            continue

        coords = (coord_el.text or "").strip().split()[0].split(",")
        lon    = float(coords[0])
        lat    = float(coords[1])
        elev   = float(coords[2]) if len(coords) >= 3 else 0.0

        points.append({
            "name":  (name_el.text or "").strip(),
            "lat":   lat,
            "lon":   lon,
            "elev":  elev,
            "attrs": _parse_extended_data(placemark),
        })

    return points


def set_kml_attr(path, placemark_name, key, value):
    """Set an ExtendedData attribute on a named placemark and write back."""
    tree = ET.parse(path)
    root = tree.getroot()

    for placemark in root.findall(f".//{_ns('Placemark')}"):
        name_el = placemark.find(_ns("name"))
        if name_el is None or (name_el.text or "").strip() != placemark_name:
            continue

        ed = placemark.find(_ns("ExtendedData"))
        if ed is None:
            ed = ET.SubElement(placemark, _ns("ExtendedData"))

        for data in ed.findall(_ns("Data")):
            if data.get("name") == key:
                val_el = data.find(_ns("value"))
                if val_el is None:
                    val_el = ET.SubElement(data, _ns("value"))
                val_el.text = str(value)
                tree.write(path, encoding="unicode", xml_declaration=True)
                return

        data_el  = ET.SubElement(ed, _ns("Data"))
        data_el.set("name", key)
        val_el   = ET.SubElement(data_el, _ns("value"))
        val_el.text = str(value)
        tree.write(path, encoding="unicode", xml_declaration=True)
        return

    raise ValueError(f"Placemark '{placemark_name}' not found in {path}")


# ------------------------------------------------------------
# Terrain elevation cache
# ------------------------------------------------------------

CACHE_FILE = os.path.join(os.path.dirname(__file__), "elevation_cache.json")
_elev_cache: dict = {}


def _cache_key(lat, lon):
    return f"{lat:.6f},{lon:.6f}"


def load_cache():
    global _elev_cache
    if os.path.exists(CACHE_FILE):
        with open(CACHE_FILE) as f:
            _elev_cache = json.load(f)


def save_cache():
    with open(CACHE_FILE, "w") as f:
        json.dump(_elev_cache, f)


def fetch_elevations(samples, batch_size=100):
    elevations: list[float] = [0.0] * len(samples)
    need_fetch = []

    for i, (lat, lon) in enumerate(samples):
        key = _cache_key(lat, lon)
        if key in _elev_cache:
            elevations[i] = _elev_cache[key]
        else:
            need_fetch.append((i, lat, lon))

    if need_fetch:
        fetched = []
        for batch_start in range(0, len(need_fetch), batch_size):
            batch  = need_fetch[batch_start:batch_start + batch_size]
            coords = "|".join(f"{lat},{lon}" for _, lat, lon in batch)
            time.sleep(1.2)
            r = requests.get(f"https://api.opentopodata.org/v1/ned10m?locations={coords}")
            r.raise_for_status()
            fetched += [
                item["elevation"] if item["elevation"] is not None else 0.0
                for item in r.json()["results"]
            ]

        for (i, lat, lon), elev in zip(need_fetch, fetched):
            _elev_cache[_cache_key(lat, lon)] = elev
            elevations[i] = elev

        save_cache()

    return elevations


# ------------------------------------------------------------
# Path analysis
# ------------------------------------------------------------

def analyze_link(a, b, freq_mhz=915.0, sample_distance=5.0, default_antenna_height=3.0):
    h_a = float(a["attrs"].get("antenna_height", default_antenna_height))
    h_b = float(b["attrs"].get("antenna_height", default_antenna_height))

    total_distance = haversine(a["lat"], a["lon"], b["lat"], b["lon"])
    samples = max(2, int(total_distance / sample_distance))

    sample_points = [
        (a["lat"] + (b["lat"] - a["lat"]) * i / samples,
         a["lon"] + (b["lon"] - a["lon"]) * i / samples)
        for i in range(samples + 1)
    ]

    terrain = fetch_elevations(sample_points)
    h1 = terrain[0]  + h_a
    h2 = terrain[-1] + h_b

    min_clearance = float("inf")
    obstructed    = False

    for i in range(1, samples):
        d1 = total_distance * (i / samples)
        d2 = total_distance - d1

        los_h    = h1 + (h2 - h1) * (d1 / total_distance)
        required = terrain[i] + earth_curvature_bulge(d1, d2) + 0.6 * fresnel_radius(d1, d2, freq_mhz)
        clearance = los_h - required

        min_clearance = min(min_clearance, clearance)
        if clearance < 0:
            obstructed = True

    return {
        "distance_km":    total_distance / 1000.0,
        "samples":        samples,
        "obstructed":     obstructed,
        "min_clearance_m": min_clearance,
        "antenna_a":      h_a,
        "antenna_b":      h_b,
    }


# ------------------------------------------------------------
# Subcommands
# ------------------------------------------------------------

def cmd_list(args):
    points = parse_kml(args.kml)
    print(f"\n{len(points)} placemarks in {args.kml}\n")
    for p in points:
        attrs = p["attrs"]
        attr_str = "  ".join(f"{k}={v}" for k, v in attrs.items()) if attrs else "(no extended data)"
        print(f"  {p['name']:<25}  lat={p['lat']:.6f}  lon={p['lon']:.6f}  {attr_str}")
    print()


def cmd_set(args):
    set_kml_attr(args.kml, args.name, args.key, args.value)
    print(f"Set {args.name!r}: {args.key} = {args.value}  ({args.kml})")


def cmd_analyze(args):
    load_cache()
    points = parse_kml(args.kml)

    available_db = args.tx_power - args.rx_sensitivity
    foliage_db   = 2 * args.forest_db_per_m * args.forest_terminal_depth

    print()
    print("LoRa LOS / Fresnel + Link Budget Analysis")
    print(f"  TX {args.tx_power:.0f} dBm  |  RX {args.rx_sensitivity:.0f} dBm  "
          f"|  Budget {available_db:.0f} dB  |  Forest {args.forest_db_per_m} dB/m  "
          f"|  Default antenna ht {args.antenna_height:.0f} m")
    print(f"  Foliage: {args.forest_db_per_m} dB/m × {args.forest_terminal_depth:.0f}m "
          f"× 2 terminals = {foliage_db:.1f} dB (constant)")
    print()
    print(f"{'Link':<43} {'Dist':>6}  {'Ant':>7}  {'Terrain':8}  {'MinClr':>7}  "
          f"{'FSPL':>6}  {'Foliage':>7}  {'Margin':>7}  RF")
    print("-" * 115)

    # adjacency set for connectivity analysis (CLEAR or MARGINAL terrain + OK rf)
    reachable: dict[str, set[str]] = {p["name"]: set() for p in points}

    for a, b in itertools.combinations(points, 2):
        result = analyze_link(a, b,
                              freq_mhz=args.freq_mhz,
                              sample_distance=args.sample_distance,
                              default_antenna_height=args.antenna_height)

        rf  = link_budget(result["distance_km"] * 1000, args.freq_mhz,
                          args.tx_power, args.rx_sensitivity,
                          args.forest_db_per_m, args.forest_terminal_depth)

        clr = result["min_clearance_m"]
        terrain_status = "CLEAR" if clr >= 0 else "MARGINAL" if clr >= -args.marginal_threshold else "BLOCKED"
        rf_status      = "OK"    if rf["margin_db"] >= 0 else "MARGINAL" if rf["margin_db"] >= -10 else "FAIL"

        if terrain_status in ("CLEAR", "MARGINAL") and rf_status in ("OK", "MARGINAL"):
            reachable[a["name"]].add(b["name"])
            reachable[b["name"]].add(a["name"])

        ant_str = f"{result['antenna_a']:.0f}/{result['antenna_b']:.0f}m"
        print(
            f"{a['name']} -> {b['name']:<{43 - len(a['name']) - 4}} "
            f"{result['distance_km']:6.2f}km  "
            f"{ant_str:>7}  "
            f"{terrain_status:8s}  "
            f"{clr:7.2f}m  "
            f"{rf['fspl_db']:6.1f}dB  "
            f"{rf['foliage_db']:7.1f}dB  "
            f"{rf['margin_db']:7.1f}dB  "
            f"{rf_status}"
        )

    # connected components via BFS
    seen       = set()
    components = []
    for start in reachable:
        if start in seen:
            continue
        component = set()
        queue     = [start]
        while queue:
            node = queue.pop()
            if node in component:
                continue
            component.add(node)
            queue.extend(reachable[node] - component)
        seen      |= component
        components.append(sorted(component))

    components.sort(key=len, reverse=True)

    print()
    print("Network Connectivity")
    print("-" * 50)
    if len(components) == 1:
        print(f"  All {len(points)} nodes form a single connected mesh.")
    else:
        for i, comp in enumerate(components):
            label = "ISOLATED" if len(comp) == 1 else f"Component {i + 1}"
            print(f"  {label}: {', '.join(comp)}")


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(prog="los.py")
    parser.add_argument("--kml", default=DEFAULT_KML, metavar="FILE",
                        help=f"KML file (default: {DEFAULT_KML})")

    sub = parser.add_subparsers(dest="cmd", required=True)

    # list
    sub.add_parser("list", help="list placemarks and their extended attributes")

    # set
    p_set = sub.add_parser("set", help="set an extended attribute on a placemark")
    p_set.add_argument("name",  help="placemark name")
    p_set.add_argument("key",   help="attribute name (e.g. antenna_height)")
    p_set.add_argument("value", help="value to set")

    # analyze
    p_a = sub.add_parser("analyze", help="run LOS/Fresnel and link budget analysis")
    p_a.add_argument("--antenna-height",       type=float, default=3.0,    metavar="M",
                     help="default antenna height in meters (default: 3; overridden per-point by KML extended data)")
    p_a.add_argument("--freq-mhz",             type=float, default=915.0)
    p_a.add_argument("--sample-distance",      type=float, default=5.0,    metavar="M")
    p_a.add_argument("--marginal-threshold",   type=float, default=2.0,    metavar="M")
    p_a.add_argument("--tx-power",             type=float, default=28.0,   metavar="DBM")
    p_a.add_argument("--rx-sensitivity",       type=float, default=-148.0, metavar="DBM")
    p_a.add_argument("--forest-db-per-m",      type=float, default=0.3,    metavar="DB/M")
    p_a.add_argument("--forest-terminal-depth",type=float, default=30.0,   metavar="M")

    args = parser.parse_args()
    {"list": cmd_list, "set": cmd_set, "analyze": cmd_analyze}[args.cmd](args)


if __name__ == "__main__":
    main()
