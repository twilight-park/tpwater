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
import math
import itertools
import os
import requests
import xml.etree.ElementTree as ET

EARTH_RADIUS = 6371000.0


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
        coord_el = placemark.find(".//kml:coordinates", ns)

        if name_el is None or coord_el is None:
            continue

        coords = (coord_el.text or "").strip().split(",")

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

def fetch_elevations(samples, batch_size=100):
    """
    samples:
        [(lat, lon), ...]

    Returns:
        [elev_meters]
    """

    elevations = []

    for i in range(0, len(samples), batch_size):
        batch = samples[i:i + batch_size]
        coords = "|".join(f"{lat},{lon}" for lat, lon in batch)
        url = (
            "https://api.opentopodata.org/v1/ned10m"
            f"?locations={coords}"
        )
        r = requests.get(url)
        r.raise_for_status()
        elevations += [
            item["elevation"] if item["elevation"] is not None else 0
            for item in r.json()["results"]
        ]

    return elevations


# ------------------------------------------------------------
# Path analysis
# ------------------------------------------------------------

def analyze_link(a, b,
                 antenna_height=3.0,
                 freq_mhz=915.0,
                 samples=200):

    total_distance = haversine(
        a["lat"], a["lon"],
        b["lat"], b["lon"]
    )

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
        "--samples",
        type=int,
        default=100,
    )

    args = parser.parse_args()

    points = parse_kml(args.kml)

    print()
    print("LoRa LOS / Fresnel Analysis")
    print()

    for a, b in itertools.combinations(points, 2):

        result = analyze_link(
            a,
            b,
            antenna_height=args.antenna_height,
            freq_mhz=args.freq_mhz,
            samples=args.samples,
        )

        status = (
            "CLEAR"
            if not result["obstructed"]
            else "BLOCKED"
        )

        print(
            f"{a['name']:20s} -> "
            f"{b['name']:20s} | "
            f"{result['distance_km']:6.2f} km | "
            f"{status:8s} | "
            f"MinClr {result['min_clearance_m']:7.2f} m"
        )


if __name__ == "__main__":
    main()