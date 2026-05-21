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


def knife_edge_loss(v):
    """ITU-R P.526 knife-edge diffraction loss in dB (positive = loss). 0 for clear paths (v <= -1)."""
    if v <= -1:
        return 0.0
    elif v <= 0:
        return -20 * math.log10(0.5 - 0.62 * v)
    elif v <= 1:
        return -20 * math.log10(0.5 * math.exp(-0.95 * v))
    elif v <= 2.4:
        return -20 * math.log10(0.4 - math.sqrt(max(0.0, 0.1184 - (0.38 - 0.1 * v) ** 2)))
    else:
        return -20 * math.log10(0.225 / v)


def link_budget(distance_m, freq_mhz, tx_dbm, rx_sensitivity_dbm, foliage_db, diffraction_db):
    fspl   = free_space_path_loss(distance_m, freq_mhz)
    margin = (tx_dbm - rx_sensitivity_dbm) - fspl - foliage_db - diffraction_db
    return {"fspl_db": fspl, "foliage_db": foliage_db, "margin_db": margin}


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


# ------------------------------------------------------------
# NLCD land cover (foliage estimation)
# ------------------------------------------------------------

NLCD_CACHE_FILE = os.path.join(os.path.dirname(__file__), "nlcd_cache.json")
NLCD_WMS_URL    = "https://www.mrlc.gov/geoserver/mrlc_display/NLCD_2021_Land_Cover_L48/wms"
_nlcd_cache: dict = {}

# depth multipliers by NLCD class (applied to default terminal depth)
_NLCD_DEPTH: dict[int, float] = {
    41: 1.0, 42: 1.0, 43: 1.0, 90: 1.0,   # forest / woody wetland — full depth
    52: 0.5, 95: 0.3,                        # shrub / emergent wetland — partial
}


def load_nlcd_cache():
    global _nlcd_cache
    if os.path.exists(NLCD_CACHE_FILE):
        with open(NLCD_CACHE_FILE) as f:
            _nlcd_cache = json.load(f)


def save_nlcd_cache():
    with open(NLCD_CACHE_FILE, "w") as f:
        json.dump(_nlcd_cache, f)


def _fetch_nlcd_class(lat, lon) -> int | None:
    d = 0.0002  # ~20 m buffer for 3×3 pixel query
    params = {
        "SERVICE": "WMS", "VERSION": "1.1.1", "REQUEST": "GetFeatureInfo",
        "LAYERS": "NLCD_2021_Land_Cover_L48",
        "QUERY_LAYERS": "NLCD_2021_Land_Cover_L48",
        "SRS": "EPSG:4326",
        "BBOX": f"{lon-d},{lat-d},{lon+d},{lat+d}",
        "WIDTH": "3", "HEIGHT": "3", "X": "1", "Y": "1",
        "INFO_FORMAT": "text/plain",
    }
    try:
        r = requests.get(NLCD_WMS_URL, params=params, timeout=10)
        r.raise_for_status()
        for line in r.text.splitlines():
            if ("PALETTE_INDEX" in line or "GRAY_INDEX" in line) and "=" in line:
                return int(float(line.split("=")[-1].strip()))
    except Exception:
        pass
    return None


def nlcd_class_at(lat, lon) -> int | None:
    key = f"{lat:.5f},{lon:.5f}"
    if key in _nlcd_cache:
        v = _nlcd_cache[key]
        return int(v) if v is not None else None
    cls = _fetch_nlcd_class(lat, lon)
    _nlcd_cache[key] = cls
    return cls


def nlcd_terminal_depth(lat, lon, default_depth: float) -> tuple[float, str]:
    """Return (terminal_depth_m, source_label) for a node position."""
    cls = nlcd_class_at(lat, lon)
    if cls is None:
        return default_depth, "default"
    mult = _NLCD_DEPTH.get(cls, 0.0)
    return default_depth * mult, f"NLCD:{cls}"


EPQS_URL = "https://epqs.nationalmap.gov/v1/json"
EPQS_SENTINEL = -1000000  # returned for points outside coverage


def _epqs_fetch_one(lat, lon):
    r = requests.get(EPQS_URL, params={"x": lon, "y": lat, "units": "Meters", "wkid": "4326"})
    r.raise_for_status()
    val = r.json().get("value")
    if val is None or float(val) <= EPQS_SENTINEL:
        return 0.0
    return float(val)


def fetch_elevations(samples):
    elevations: list[float] = [0.0] * len(samples)
    need_fetch = []

    for i, (lat, lon) in enumerate(samples):
        key = _cache_key(lat, lon)
        if key in _elev_cache:
            elevations[i] = _elev_cache[key]
        else:
            need_fetch.append((i, lat, lon))

    if need_fetch:
        print(f"    fetching {len(need_fetch)} elevations from USGS EPQS...", flush=True)
        for count, (i, lat, lon) in enumerate(need_fetch, 1):
            time.sleep(0.05)
            elev = _epqs_fetch_one(lat, lon)
            _elev_cache[_cache_key(lat, lon)] = elev
            elevations[i] = elev
            if count % 100 == 0:
                save_cache()
                print(f"      {count}/{len(need_fetch)}", flush=True)
        save_cache()

    return elevations


# ------------------------------------------------------------
# Path analysis
# ------------------------------------------------------------

def analyze_link(a, b, freq_mhz=915.0, sample_distance=5.0, default_antenna_height=3.0,
                 forest_db_per_m=0.3, default_foliage_depth=30.0, use_nlcd=True):
    h_a        = float(a["attrs"].get("antenna_height", default_antenna_height))
    h_b        = float(b["attrs"].get("antenna_height", default_antenna_height))
    wavelength = 299792458.0 / (freq_mhz * 1e6)

    # foliage terminal depth: KML foliage_depth > NLCD > constant default
    if "foliage_depth" in a["attrs"]:
        depth_a, src_a = float(a["attrs"]["foliage_depth"]), "KML"
    elif use_nlcd:
        depth_a, src_a = nlcd_terminal_depth(a["lat"], a["lon"], default_foliage_depth)
    else:
        depth_a, src_a = default_foliage_depth, "default"

    if "foliage_depth" in b["attrs"]:
        depth_b, src_b = float(b["attrs"]["foliage_depth"]), "KML"
    elif use_nlcd:
        depth_b, src_b = nlcd_terminal_depth(b["lat"], b["lon"], default_foliage_depth)
    else:
        depth_b, src_b = default_foliage_depth, "default"

    foliage_db = (depth_a + depth_b) * forest_db_per_m

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
    worst_d1 = total_distance / 2
    worst_d2 = total_distance / 2
    worst_geo_excess = 0.0   # terrain + curvature - los_h at worst point

    for i in range(1, samples):
        d1 = total_distance * (i / samples)
        d2 = total_distance - d1

        los_h     = h1 + (h2 - h1) * (d1 / total_distance)
        curvature = earth_curvature_bulge(d1, d2)
        fresnel_r = fresnel_radius(d1, d2, freq_mhz)
        clearance = los_h - terrain[i] - curvature - 0.6 * fresnel_r

        if clearance < min_clearance:
            min_clearance    = clearance
            worst_d1         = d1
            worst_d2         = d2
            worst_geo_excess = terrain[i] + curvature - los_h  # positive = above LOS

    # Knife-edge diffraction at worst obstruction point
    v              = worst_geo_excess * math.sqrt(2 * (worst_d1 + worst_d2) / (wavelength * worst_d1 * worst_d2))
    diffraction_db = knife_edge_loss(v)

    return {
        "distance_km":     total_distance / 1000.0,
        "samples":         samples,
        "min_clearance_m": min_clearance,
        "diffraction_db":  diffraction_db,
        "antenna_a":       h_a,
        "antenna_b":       h_b,
        "foliage_db":      foliage_db,
        "foliage_src_a":   src_a,
        "foliage_src_b":   src_b,
        "foliage_depth_a": depth_a,
        "foliage_depth_b": depth_b,
    }


# ------------------------------------------------------------
# Subcommands
# ------------------------------------------------------------

def _active_points(points):
    return [p for p in points if p["attrs"].get("skip", "").lower() not in ("true", "1", "yes")]


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


def _tab_table(headers: list[str], rows: list[list[str]]):
    """Print a Starbase-format tab table: header, dashes separator, data rows."""
    print("\t".join(headers))
    print("\t".join("-" * len(h) for h in headers))
    for row in rows:
        print("\t".join(row))


def cmd_analyze(args):
    load_cache()
    load_nlcd_cache()
    points = _active_points(parse_kml(args.kml))

    available_db = args.tx_power - args.rx_sensitivity
    foliage_src  = "default" if args.no_nlcd else "NLCD"

    print()
    print("LoRa LOS / Fresnel + Link Budget Analysis")
    print(f"  TX {args.tx_power:.0f} dBm  |  RX {args.rx_sensitivity:.0f} dBm  "
          f"|  Budget {available_db:.0f} dB  |  Forest {args.forest_db_per_m} dB/m  "
          f"|  Default antenna ht {args.antenna_height:.0f} m")
    print(f"  Foliage terminal depth: {args.forest_terminal_depth:.0f}m default  "
          f"|  Source: {foliage_src} (override per node with: set NAME foliage_depth M)  "
          f"|  Fade margin {args.fade_margin:.0f} dB")
    print()

    reachable: dict[str, set[str]] = {p["name"]: set() for p in points}
    rows: list[list[str]] = []

    for a, b in itertools.combinations(points, 2):
        result = analyze_link(a, b,
                              freq_mhz=args.freq_mhz,
                              sample_distance=args.sample_distance,
                              default_antenna_height=args.antenna_height,
                              forest_db_per_m=args.forest_db_per_m,
                              default_foliage_depth=args.forest_terminal_depth,
                              use_nlcd=not args.no_nlcd)

        rf     = link_budget(result["distance_km"] * 1000, args.freq_mhz,
                             args.tx_power, args.rx_sensitivity,
                             result["foliage_db"],
                             result["diffraction_db"])

        margin = rf["margin_db"]
        status = "OK" if margin >= args.fade_margin else "MARGINAL" if margin >= 0 else "FAIL"

        if status in ("OK", "MARGINAL"):
            reachable[a["name"]].add(b["name"])
            reachable[b["name"]].add(a["name"])

        foliage_note = (f"{result['foliage_src_a']}/{result['foliage_src_b']} "
                        f"{result['foliage_depth_a']:.0f}/{result['foliage_depth_b']:.0f}m")
        rows.append([
            f"{a['name']} -> {b['name']}",
            f"{result['distance_km']:.2f}km",
            f"{result['antenna_a']:.0f}/{result['antenna_b']:.0f}m",
            f"{result['min_clearance_m']:.1f}m",
            f"{result['diffraction_db']:.1f}dB",
            f"{rf['foliage_db']:.1f}dB",
            foliage_note,
            f"{rf['fspl_db']:.1f}dB",
            f"{margin:.1f}dB",
            status,
        ])

    save_nlcd_cache()
    _tab_table(["Link", "Dist", "Ant", "MinClr", "Diffr", "Foliage", "FolSrc", "FSPL", "Margin", "Status"], rows)

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
    p_a.add_argument("--antenna-height",        type=float, default=3.0,    metavar="M",
                     help="default antenna height in meters (overridden per-point by KML extended data)")
    p_a.add_argument("--freq-mhz",             type=float, default=915.0)
    p_a.add_argument("--sample-distance",      type=float, default=5.0,    metavar="M")
    p_a.add_argument("--tx-power",             type=float, default=28.0,   metavar="DBM")
    p_a.add_argument("--rx-sensitivity",       type=float, default=-148.0, metavar="DBM")
    p_a.add_argument("--forest-db-per-m",      type=float, default=0.3,    metavar="DB/M")
    p_a.add_argument("--forest-terminal-depth",type=float, default=30.0,   metavar="M")
    p_a.add_argument("--fade-margin",          type=float, default=10.0,   metavar="DB",
                     help="required reliability margin in dB for OK status (default: 10)")
    p_a.add_argument("--no-nlcd", action="store_true",
                     help="skip NLCD land cover lookup, use constant foliage depth for all nodes")

    args = parser.parse_args()
    {"list": cmd_list, "set": cmd_set, "analyze": cmd_analyze}[args.cmd](args)


if __name__ == "__main__":
    main()
