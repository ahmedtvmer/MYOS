"""Deterministic net Cardio calorie estimates used when a workout is committed."""

from __future__ import annotations

from math import floor
from typing import Any

# ACSM speed equations use metres/minute. Other machine values use 2024 Adult
# Compendium activities; level-only controls map 1–3/4–7/8+ to low/moderate/high.
# This shared level mapping is an estimate because machines have no common scale.
# Watts use Compendium power bands where listed; Other defaults to 3 MET.
ACSM_WALKING_COEFFICIENTS = (0.1, 1.8, 3.5)
ACSM_RUNNING_COEFFICIENTS = (0.2, 0.9, 3.5)
RESTING_VO2_ML_KG_MIN = 3.5
KCAL_PER_LITER_OXYGEN = 5.0
COMPENDIUM_METS = {
    "stairmaster": {"low": 4.5, "moderate": 6.8, "high": 9.3},
    "bike": {"low": 4.0, "moderate": 6.8, "high": 10.3},
    "elliptical": {"low": 3.5, "moderate": 5.0, "high": 9.0},
    "rower": {"low": 5.0, "moderate": 5.0, "high": 7.3},
    "other": {"low": 2.0, "moderate": 3.0, "high": 4.0},
}
BIKE_WATTS_METS = (
    (30, 3.5), (50, 4.0), (60, 5.0), (80, 5.8), (100, 6.0), (125, 6.8),
    (150, 8.0), (199, 10.3), (229, 10.8), (250, 12.5), (325, 13.8),
)
# Upper limits are exclusive, matching the Compendium's <100, 100–149,
# 150–199 W bands; fractional watt readings keep their actual band.
ROWER_WATTS_METS = ((100, 5.0), (150, 7.5), (200, 11.0))
MODERATE_LEVEL_MIN = 4.0
HIGH_LEVEL_MIN = 8.0


def _rounded_kcal(kcal: float) -> int:
    return int(floor(kcal + 0.5))


def _treadmill_kcal(entry: dict[str, Any], weight_kg: float) -> tuple[float, bool]:
    minutes = float(entry["minutes"])
    speed = entry.get("speed_kmh")
    incline = entry.get("incline_pct")
    estimate = incline is None
    if speed is None and entry.get("machine") == "outdoor_walk_run" and entry.get("distance_m"):
        speed = float(entry["distance_m"]) / 1000 / (minutes / 60)
    if speed is None:
        speed = 5.0
        estimate = True
    velocity = float(speed) * 1000 / 60
    grade = float(incline or 0) / 100
    a, b, c = ACSM_RUNNING_COEFFICIENTS if float(speed) >= 8 else ACSM_WALKING_COEFFICIENTS
    net_vo2 = max(0.0, a * velocity + b * velocity * grade + c - RESTING_VO2_ML_KG_MIN)
    kcal = net_vo2 * weight_kg * minutes / 1000 * KCAL_PER_LITER_OXYGEN
    return kcal, estimate


def _machine_intensity(level: float) -> str:
    if level < MODERATE_LEVEL_MIN:
        return "low"
    return "moderate" if level < HIGH_LEVEL_MIN else "high"


def _watts_met(machine: str, watts: float) -> float | None:
    bands = BIKE_WATTS_METS if machine == "bike" else ROWER_WATTS_METS
    if machine not in {"bike", "rower"}:
        return None
    for upper_bound, met in bands:
        within_band = watts < upper_bound if machine == "rower" else watts <= upper_bound
        if within_band:
            return met
    return 16.3 if machine == "bike" else 14.0


def _machine_kcal(entry: dict[str, Any], weight_kg: float) -> tuple[float, bool]:
    machine = str(entry.get("machine", "other"))
    level = entry.get("level")
    mets = COMPENDIUM_METS.get(machine, COMPENDIUM_METS["other"])
    watts = entry.get("watts")
    watts_met = _watts_met(machine, float(watts)) if watts is not None else None
    estimate = (level is None and (watts is None or watts_met is None)) or machine == "other"
    if watts_met is not None:
        met = watts_met
    else:
        intensity = "moderate" if level is None else _machine_intensity(float(level))
        met = mets[intensity]
    kcal = (met - 1) * weight_kg * float(entry["minutes"]) / 60
    return kcal, estimate


def estimate_cardio_calories(entry: dict[str, Any], weight_kg: float | None) -> dict[str, Any]:
    """Return integer net kcal and whether effort or bodyweight was assumed."""
    estimate = weight_kg is None
    effective_weight = float(weight_kg or 70.0)
    estimator = _treadmill_kcal if entry.get("machine") in {"treadmill", "outdoor_walk_run"} else _machine_kcal
    kcal, settings_missing = estimator(entry, effective_weight)
    return {"kcal": _rounded_kcal(kcal), "estimate": estimate or settings_missing}
