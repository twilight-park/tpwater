#!/usr/bin/env python3

"""
lora_los.py

LoRa 915 MHz LOS / Fresnel analyzer for KML relay sites.

Features:
- Parses Google Earth KML placemarks
- Downloads terrain elevations from OpenTopoData
- Computes:
    - geometric LOS
    - Fresnel clearance
    - Earth curvature
- Generates pairwise link report

Usage:
    python lora_los.py TWP-LOS.kml

Optional:
    --antenna-height 3
    --freq-mhz 915
    --samples 200
"""

import argparse
import json
import math
import itertools
import os
import time
import requests
import xml.etree.ElementTree as ET

EARTH_RADIUS = 6371000.0


# ------------------------------------------------------------
# RF link budget
# ------------------------------------------------------------

def free_space_path_loss(distance_m, freq_mhz):
    """FSPL in dB."""
    return 20 * math.log10(distance_m) + 20 * math.log10(freq_mhz * 1e6) - 147.55


def link_budget(distance_m, freq_mhz, tx_dbm, rx_sensitivity_dbm,
                forest_db_per_m, forest_terminal_depth_m):
    fspl      = free_space_path_loss(distance_m, freq_mhz)
    # Foliage loss applies at both terminals (signal punches through canopy
    # at each end); path between endpoints travels mostly through air.
    foliage   = 2 * forest_db_per_m * forest_terminal_depth_m
    available = tx_dbm - rx_sensitivity_dbm
    margin    = available - fspl - foliage
    return {
        "fspl_db":      fspl,
        "foliage_db":   foliage,
        "available_db": available,
        "margin_db":    margin,
    }


# ------------------------------------------------------------
# Geometry
# ------------------------------------------------------------

def haversine(lat1, lon1, lat2, lon2):
    r = 6371000.0

    p1 = math.radians(lat1)
    p2 = math.radians(lat2)

    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)

    a = (
        math.sin(dp / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    )

    return 2 * r * math.asin(math.sqrt(a))


def fresnel_radius(d1, d2, freq_mhz):
    """
    Returns first Fresnel radius in meters.
    d1/d2 in meters.
    """

    freq_hz = freq_mhz * 1e6
    wavelength = 299792458.0 / freq_hz

    return math.sqrt((wavelength * d1 * d2) / (d1 + d2))


def earth_curvature_bulge(d1, d2):
    """
    Earth curvature bulge at point between endpoints.
    """

    return (d1 * d2) / (2 * EARTH_RADIUS)


# ------------------------------------------------------------
# KML parsing
# ------------------------------------------------------------

def parse_kml(path):

    ns = {
        "kml": "http://www.opengis.net/kml/2.2"
    }

    tree = ET.parse(path)
    root = tree.getroot()

    points = []

    for placemark in root.findall(".//kml:Placemark", ns):

        name_el = placemark.find("kml:name", ns)
        point_el = placemark.find(".//kml:Point", ns)

        if name_el is None or point_el is None:
            continue

        coord_el = point_el.find("kml:coordinates", ns)

        if coord_el is None:
            continue

        coords = (coord_el.text or "").strip().split()[0].split(",")

        lon = float(coords[0])
        lat = float(coords[1])

        if len(coords) >= 3:
            elev = float(coords[2])
        else:
            elev = 0.0

        points.append({
            "name": (name_el.text or "").strip(),
            "lat": lat,
            "lon": lon,
            "elev": elev,
        })

    return points


# ------------------------------------------------------------
# Terrain elevation
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
    """
    samples:
        [(lat, lon), ...]

    Returns:
        [elev_meters]
    """

    elevations: list[float] = [0.0] * len(samples)
    need_fetch  = []

    for i, (lat, lon) in enumerate(samples):
        key = _cache_key(lat, lon)
        if key in _elev_cache:
            elevations[i] = _elev_cache[key]
        else:
            need_fetch.append((i, lat, lon))

    if need_fetch:
        fetched = []
        for batch_start in range(0, len(need_fetch), batch_size):
            batch = need_fetch[batch_start:batch_start + batch_size]
            coords = "|".join(f"{lat},{lon}" for _, lat, lon in batch)
            url = f"https://api.opentopodata.org/v1/ned10m?locations={coords}"
            time.sleep(1.2)
            r = requests.get(url)
            r.raise_for_status()
            fetched += [
                item["elevation"] if item["elevation"] is not None else 0
                for item in r.json()["results"]
            ]

        for (i, lat, lon), elev in zip(need_fetch, fetched):
            key = _cache_key(lat, lon)
            _elev_cache[key] = elev
            elevations[i] = elev

        save_cache()

    return elevations


# ------------------------------------------------------------
# Path analysis
# ------------------------------------------------------------

def analyze_link(a, b,
                 antenna_height=3.0,
                 freq_mhz=915.0,
                 sample_distance=5.0):

    total_distance = haversine(
        a["lat"], a["lon"],
        b["lat"], b["lon"]
    )

    samples = max(2, int(total_distance / sample_distance))

    sample_points = []

    for i in range(samples + 1):

        t = i / samples

        lat = a["lat"] + (b["lat"] - a["lat"]) * t
        lon = a["lon"] + (b["lon"] - a["lon"]) * t

        sample_points.append((lat, lon))

    terrain = fetch_elevations(sample_points)

    h1 = terrain[0] + antenna_height
    h2 = terrain[-1] + antenna_height

    obstructed = False
    min_clearance = 999999

    for i in range(1, samples):

        d1 = total_distance * (i / samples)
        d2 = total_distance - d1

        terrain_h = terrain[i]

        los_h = h1 + (h2 - h1) * (d1 / total_distance)

        curvature = earth_curvature_bulge(d1, d2)

        fresnel = fresnel_radius(d1, d2, freq_mhz)

        required_clearance = terrain_h + curvature + 0.6 * fresnel

        clearance = los_h - required_clearance

        min_clearance = min(min_clearance, clearance)

        if clearance < 0:
            obstructed = True

    return {
        "distance_km": total_distance / 1000.0,
        "samples": samples,
        "obstructed": obstructed,
        "min_clearance_m": min_clearance,
    }


# ------------------------------------------------------------
# Main
# ------------------------------------------------------------

def main():

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "kml",
        nargs="?",
        default=os.path.expanduser("~/Downloads/TWP-LOS.kml"),
    )

    parser.add_argument(
        "--antenna-height",
        type=float,
        default=3.0,
    )

    parser.add_argument(
        "--freq-mhz",
        type=float,
        default=915.0,
    )

    parser.add_argument(
        "--sample-distance",
        type=float,
        default=5.0,
        metavar="METERS",
        help="terrain sample interval in meters (default: 5)",
    )

    parser.add_argument(
        "--marginal-threshold",
        type=float,
        default=2.0,
        metavar="METERS",
        help="clearance below 0 still considered marginal (default: 2)",
    )

    parser.add_argument(
        "--tx-power",
        type=float,
        default=28.0,
        metavar="DBM",
        help="transmitter power in dBm (default: 28 — Heltec V4)",
    )

    parser.add_argument(
        "--rx-sensitivity",
        type=float,
        default=-148.0,
        metavar="DBM",
        help="receiver sensitivity in dBm (default: -148 — SX1262 SF12)",
    )

    parser.add_argument(
        "--forest-db-per-m",
        type=float,
        default=0.3,
        metavar="DB_PER_M",
        help="foliage attenuation dB/meter through canopy (default: 0.3)",
    )

    parser.add_argument(
        "--forest-terminal-depth",
        type=float,
        default=30.0,
        metavar="METERS",
        help="estimated canopy depth at each terminal in meters (default: 30)",
    )

    args = parser.parse_args()

    load_cache()

    points = parse_kml(args.kml)

    available_db = args.tx_power - args.rx_sensitivity

    print()
    print("LoRa LOS / Fresnel + Link Budget Analysis")
    print(f"  TX {args.tx_power:.0f} dBm  |  RX sensitivity {args.rx_sensitivity:.0f} dBm  "
          f"|  Budget {available_db:.0f} dB  |  Forest {args.forest_db_per_m} dB/m  "
          f"|  Antenna ht {args.antenna_height:.0f} m")
    print()
    foliage_db = 2 * args.forest_db_per_m * args.forest_terminal_depth
    print(f"  Foliage: {args.forest_db_per_m} dB/m × {args.forest_terminal_depth:.0f}m × 2 terminals = {foliage_db:.1f} dB (constant)")
    print()
    print(f"{'Link':<43} {'Dist':>6}  {'Terrain':8}  {'MinClr':>7}  "
          f"{'FSPL':>6}  {'Foliage':>7}  {'Margin':>7}  {'RF':8}")
    print("-" * 105)

    for a, b in itertools.combinations(points, 2):

        result = analyze_link(
            a,
            b,
            antenna_height=args.antenna_height,
            freq_mhz=args.freq_mhz,
            sample_distance=args.sample_distance,
        )

        rf = link_budget(
            result["distance_km"] * 1000,
            args.freq_mhz,
            args.tx_power,
            args.rx_sensitivity,
            args.forest_db_per_m,
            args.forest_terminal_depth,
        )

        clr = result["min_clearance_m"]
        if clr >= 0:
            terrain_status = "CLEAR"
        elif clr >= -args.marginal_threshold:
            terrain_status = "MARGINAL"
        else:
            terrain_status = "BLOCKED"

        rf_status = "OK" if rf["margin_db"] >= 0 else "MARGINAL" if rf["margin_db"] >= -10 else "FAIL"

        link_label = f"{a['name']} -> {b['name']}"
        print(
            f"{link_label:<43} "
            f"{result['distance_km']:6.2f}km  "
            f"{terrain_status:8s}  "
            f"{clr:7.2f}m  "
            f"{rf['fspl_db']:6.1f}dB  "
            f"{rf['foliage_db']:7.1f}dB  "
            f"{rf['margin_db']:7.1f}dB  "
            f"{rf_status}"
        )


if __name__ == "__main__":
    main()