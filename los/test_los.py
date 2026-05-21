#!/usr/bin/env python3
"""Tests for los.py — run with: pytest los/test_los.py"""

import math
import sys
import os
import pytest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))
import los as L


# ----------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------

def node(name, lat, lon, attrs=None):
    return {"name": name, "lat": lat, "lon": lon, "elev": 0.0, "attrs": attrs or {}}


def flat_terrain(pts, elevation=100.0):
    return [elevation] * len(pts)


def analyze(a, b, terrain_fn=None, nlcd_class=71, **kwargs):
    """Run analyze_link with mocked terrain and NLCD."""
    if terrain_fn is None:
        terrain_fn = flat_terrain
    with patch.object(L, "fetch_elevations", side_effect=terrain_fn), \
         patch.object(L, "nlcd_class_at", return_value=nlcd_class):
        return L.analyze_link(a, b, **kwargs)


# ----------------------------------------------------------------
# knife_edge_loss — this function had a sign bug; keep it tested
# ----------------------------------------------------------------

def test_knife_edge_deep_clear():
    assert L.knife_edge_loss(-2.0) == 0.0
    assert L.knife_edge_loss(-1.0) == 0.0

def test_knife_edge_half_space():
    # v=0 (tip of obstacle exactly on LOS): ITU-R gives 6 dB
    assert abs(L.knife_edge_loss(0.0) - 6.02) < 0.05

def test_knife_edge_positive_is_loss():
    # Every positive v must return positive dB loss
    for v in [0.1, 0.5, 1.0, 1.5, 2.0, 3.0, 5.0]:
        assert L.knife_edge_loss(v) > 0.0, f"expected positive loss at v={v}"

def test_knife_edge_monotone():
    # Loss increases as obstruction deepens
    vals = [L.knife_edge_loss(v) for v in [-1.0, -0.5, 0.0, 0.5, 1.0, 2.0, 3.0]]
    assert vals == sorted(vals)

def test_knife_edge_large_v():
    # v=3: asymptotic formula gives ~22.5 dB
    assert abs(L.knife_edge_loss(3.0) - 22.5) < 0.5

def test_knife_edge_boundary_continuity():
    # No large jumps at piecewise boundaries; v=1.0 has a known ~0.28 dB
    # approximation discontinuity in ITU-R P.526 — tolerate up to 0.5 dB there.
    # ITU-R P.526 piecewise approximation has known discontinuities: ~0.28 dB at v=1.0,
    # ~0.77 dB at v=2.4.  These are accepted engineering approximation errors.
    for boundary, tol in [(0.0, 0.1), (1.0, 0.5), (2.4, 1.0)]:
        below = L.knife_edge_loss(boundary - 0.001)
        above = L.knife_edge_loss(boundary + 0.001)
        assert abs(above - below) < tol, f"discontinuity at v={boundary}: {abs(above-below):.3f} dB"


# ----------------------------------------------------------------
# free_space_path_loss
# ----------------------------------------------------------------

def test_fspl_formula():
    # Verify against the textbook formula directly
    d, f = 1000.0, 915.0
    expected = 20 * math.log10(d) + 20 * math.log10(f * 1e6) - 147.55
    assert abs(L.free_space_path_loss(d, f) - expected) < 0.001

def test_fspl_increases_with_distance():
    assert L.free_space_path_loss(2000, 915) > L.free_space_path_loss(1000, 915)

def test_fspl_increases_with_frequency():
    assert L.free_space_path_loss(1000, 2400) > L.free_space_path_loss(1000, 915)


# ----------------------------------------------------------------
# foliage_loss — ITU-R P.833 saturation model
# ----------------------------------------------------------------

def test_foliage_loss_zero():
    assert L.foliage_loss(0, 0.3, 20.0) == 0.0
    assert L.foliage_loss(100, 0.0, 20.0) == 0.0

def test_foliage_loss_short_path_linear():
    # For small d, foliage_loss ≈ d * db_per_m (within 5% relative at 5m)
    d = 5.0
    linear = d * 0.3
    saturated = L.foliage_loss(d, 0.3, 20.0)
    assert abs(saturated - linear) / linear < 0.05

def test_foliage_loss_saturates():
    # Very long paths saturate at max_db
    assert L.foliage_loss(10000, 0.3, 20.0) > 19.9
    assert L.foliage_loss(10000, 0.3, 20.0) <= 20.0

def test_foliage_loss_monotone():
    vals = [L.foliage_loss(d, 0.3, 20.0) for d in [0, 10, 50, 100, 300, 1000]]
    assert vals == sorted(vals)

def test_foliage_loss_known_value():
    # 512m at 0.3 dB/m, max 20 dB → nearly saturated
    result = L.foliage_loss(512, 0.3, 20.0)
    assert result > 19.9
    assert result < 20.0


# ----------------------------------------------------------------
# link_budget
# ----------------------------------------------------------------

def test_link_budget_margin_arithmetic():
    fspl = L.free_space_path_loss(1000, 915.0)
    result = L.link_budget(1000, 915.0, tx_dbm=28, rx_sensitivity_dbm=-148,
                           foliage_db=18.0, diffraction_db=5.0)
    expected_margin = (28 - (-148)) - fspl - 18.0 - 5.0
    assert abs(result["margin_db"] - expected_margin) < 0.001
    assert abs(result["foliage_db"] - 18.0) < 0.001

def test_link_budget_zero_losses():
    fspl = L.free_space_path_loss(1000, 915.0)
    result = L.link_budget(1000, 915.0, 28, -148, 0.0, 0.0)
    assert abs(result["margin_db"] - (176.0 - fspl)) < 0.001

def test_link_budget_diffraction_reduces_margin():
    r0 = L.link_budget(1000, 915.0, 28, -148, 18.0, 0.0)
    r1 = L.link_budget(1000, 915.0, 28, -148, 18.0, 10.0)
    assert abs(r0["margin_db"] - r1["margin_db"] - 10.0) < 0.001


# ----------------------------------------------------------------
# haversine
# ----------------------------------------------------------------

def test_haversine_one_degree_lat():
    # 1 degree latitude ≈ 111.195 km
    d = L.haversine(0, 0, 1, 0)
    assert abs(d - 111195) < 300

def test_haversine_zero():
    assert L.haversine(41.9, -74.1, 41.9, -74.1) == 0.0

def test_haversine_symmetric():
    a, b = L.haversine(41.9, -74.1, 41.95, -74.0), L.haversine(41.95, -74.0, 41.9, -74.1)
    assert abs(a - b) < 0.001


# ----------------------------------------------------------------
# analyze_link — terrain diffraction
# ----------------------------------------------------------------

def test_analyze_flat_no_diffraction():
    # Flat terrain with tall antennas → worst_geo_excess negative → no diffraction
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)
    result = analyze(a, b, default_antenna_height=20.0)
    assert result["diffraction_db"] == 0.0

def test_analyze_ridge_causes_diffraction():
    # Central ridge well above LOS → positive diffraction loss
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)

    def ridge(pts):
        elev = [100.0] * len(pts)
        mid = len(pts) // 2
        elev[mid] = 140.0  # 40m above endpoints
        return elev

    result = analyze(a, b, terrain_fn=ridge, default_antenna_height=3.0)
    assert result["diffraction_db"] > 5.0
    assert result["min_clearance_m"] < 0.0

def test_canopy_increases_diffraction():
    # Forested ridge: canopy adds to effective obstacle height → more diffraction
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)

    def ridge(pts):
        elev = [100.0] * len(pts)
        elev[len(pts) // 2] = 115.0
        return elev

    grass  = analyze(a, b, terrain_fn=ridge, nlcd_class=71, default_antenna_height=3.0)
    forest = analyze(a, b, terrain_fn=ridge, nlcd_class=41, default_antenna_height=3.0)
    # NLCD 41 = deciduous, canopy_ht=22m: effective obstacle is 22m taller
    assert forest["diffraction_db"] > grass["diffraction_db"]
    assert forest["min_clearance_m"] < grass["min_clearance_m"]

def test_analyze_clearance_positive_for_clear_path():
    # Tall antennas (20m) well above the max Fresnel radius (~9.5m at midpoint
    # of a ~1km link) → clearance positive at every sample point.
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)
    result = analyze(a, b, terrain_fn=flat_terrain, default_antenna_height=20.0)
    assert result["min_clearance_m"] > 0.0


# ----------------------------------------------------------------
# analyze_link — foliage model
# ----------------------------------------------------------------

def test_foliage_open_land_is_zero():
    # NLCD 71 (grassland): mult=0, foliage_db must be 0
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)
    result = analyze(a, b, nlcd_class=71, forest_db_per_m=0.3)
    assert result["foliage_db"] == 0.0

def test_foliage_no_nlcd_constant_terminal():
    # --no-nlcd: ITU-R P.833 applied to 2 * foliage_height depth
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)
    with patch.object(L, "fetch_elevations", side_effect=flat_terrain):
        result = L.analyze_link(a, b, forest_db_per_m=0.3, foliage_height=30.0,
                                foliage_max_db=20.0, use_nlcd=False)
    # foliage_loss(60m, 0.3, 20) = 20*(1-exp(-0.9)) ≈ 11.87 dB
    expected = L.foliage_loss(60.0, 0.3, 20.0)
    assert abs(result["foliage_db"] - expected) < 0.001
    assert "const" in result["foliage_src"]

def test_foliage_kml_override_bypasses_nlcd():
    # KML foliage_depth on both nodes → NLCD path walk skipped
    a = node("A", 41.90, -74.10, attrs={"foliage_depth": "20"})
    b = node("B", 41.91, -74.10, attrs={"foliage_depth": "10"})
    result = analyze(a, b, nlcd_class=41, forest_db_per_m=0.3, foliage_max_db=20.0)
    # foliage_loss(30m, 0.3, 20) = 20*(1-exp(-0.45)) ≈ 7.25 dB
    expected = L.foliage_loss(30.0, 0.3, 20.0)
    assert abs(result["foliage_db"] - expected) < 0.001
    assert "KML" in result["foliage_src"]

def test_foliage_open_path_is_zero():
    # All samples NLCD:71 (grassland, mult=0) → no foliage regardless of LOS height
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)
    result = analyze(a, b, nlcd_class=71, forest_db_per_m=0.3, default_antenna_height=3.0)
    assert result["foliage_db"] == 0.0

def test_foliage_full_path_forest_counts_low_segments():
    # Full-path forest (NLCD:41) with low LOS → foliage > 0
    # Tall antennas so LOS is above canopy → foliage = 0
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)
    low  = analyze(a, b, nlcd_class=41, forest_db_per_m=0.3, default_antenna_height=3.0)
    high = analyze(a, b, nlcd_class=41, forest_db_per_m=0.3, default_antenna_height=50.0)
    assert low["foliage_db"] > 0.0
    assert high["foliage_db"] == 0.0  # LOS 50m above ground, above any canopy


# ----------------------------------------------------------------
# analyze_link — return shape
# ----------------------------------------------------------------

def test_analyze_link_return_keys():
    a = node("A", 41.90, -74.10)
    b = node("B", 41.91, -74.10)
    result = analyze(a, b)
    for key in ("distance_km", "samples", "min_clearance_m", "diffraction_db",
                 "ridge_correction_db", "ridge_radius_m",
                 "antenna_a", "antenna_b", "foliage_db", "foliage_src"):
        assert key in result, f"missing key: {key}"

def test_analyze_link_antenna_heights_from_kml():
    a = node("A", 41.90, -74.10, attrs={"antenna_height": "6"})
    b = node("B", 41.91, -74.10, attrs={"antenna_height": "10"})
    result = analyze(a, b)
    assert result["antenna_a"] == 6.0
    assert result["antenna_b"] == 10.0
