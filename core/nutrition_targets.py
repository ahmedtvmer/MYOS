"""Pure, deterministic calculation of Player Nutrition targets."""

from dataclasses import dataclass
from math import ceil


ACTIVITY_FACTORS = {
    "mostly_sitting": 1.2,
    "on_feet": 1.375,
    "physical_job": 1.55,
}
PACE_RATES = {
    "lose": {"light": 0.0025, "moderate": 0.005, "aggressive": 0.01},
    "maintain": {"light": 0.0, "moderate": 0.0, "aggressive": 0.0},
    "gain": {"light": 0.001, "moderate": 0.0025, "aggressive": 0.005},
}


@dataclass(frozen=True)
class NutritionTargets:
    calories: int
    protein_g: int
    carbs_g: int
    fat_g: int
    bmr: float
    maintenance: float
    calorie_floor: float
    floor_applied: bool
    weekly_rate_pct: float


@dataclass(frozen=True)
class NutritionCalculationInput:
    sex: str
    age: int
    height_cm: float
    weight_kg: float
    daily_activity: str
    training_days: int
    goal: str
    intensity: str


def calculate_targets(inputs: NutritionCalculationInput) -> NutritionTargets:
    _validate(inputs)
    bmr_raw = 10 * inputs.weight_kg + 6.25 * inputs.height_cm - 5 * inputs.age + (5 if inputs.sex == "male" else -161)
    bmr = round(bmr_raw, 1)
    maintenance = bmr_raw * (ACTIVITY_FACTORS[inputs.daily_activity] + 0.0625 * inputs.training_days)
    calorie_floor = max(bmr_raw, 1200 if inputs.sex == "female" else 1500)
    delta = PACE_RATES[inputs.goal][inputs.intensity] * inputs.weight_kg * 7700 / 7
    raw_calories = _raw_calories(inputs.goal, maintenance, delta)
    calories, floor_applied = _round_calories(inputs.goal, raw_calories, calorie_floor)
    weekly_rate = _realized_rate(inputs.goal, maintenance, calories, inputs.weight_kg)
    protein, carbs, fat = _macros(inputs.goal, inputs.weight_kg, calories)
    return NutritionTargets(int(calories), protein, carbs, fat, bmr, round(maintenance, 1), calorie_floor,
                            floor_applied, round(weekly_rate, 4))


def _validate(inputs: NutritionCalculationInput) -> None:
    if inputs.age < 18:
        raise ValueError("Nutrition targets are not available for players under 18.")
    if inputs.sex not in ("male", "female"):
        raise ValueError("Sex must be male or female.")
    if inputs.daily_activity not in ACTIVITY_FACTORS:
        raise ValueError("Unknown Daily activity.")
    if inputs.goal not in PACE_RATES or inputs.intensity not in PACE_RATES[inputs.goal]:
        raise ValueError("Unknown Nutrition goal or intensity.")


def _raw_calories(goal: str, maintenance: float, delta: float) -> float:
    if goal == "lose":
        return maintenance - delta
    if goal == "gain":
        return maintenance + delta
    return maintenance


def _round_calories(goal: str, raw_calories: float, calorie_floor: float) -> tuple[float, bool]:
    floor_applied = raw_calories < calorie_floor
    calories = max(calorie_floor, raw_calories)
    if goal == "lose":
        rounded = ceil(calories / 10) * 10
    elif goal == "gain":
        rounded = int(calories // 10) * 10
    else:
        rounded = round(calories / 10) * 10
    return max(rounded, ceil(calorie_floor / 10) * 10), floor_applied


def _realized_rate(goal: str, maintenance: float, calories: float, weight_kg: float) -> float:
    if goal == "lose":
        return max(0.0, (maintenance - calories) * 7 / (weight_kg * 7700) * 100)
    if goal == "gain":
        return max(0.0, (calories - maintenance) * 7 / (weight_kg * 7700) * 100)
    return 0.0


def _macros(goal: str, weight_kg: float, calories: float) -> tuple[int, int, int]:
    protein = round(weight_kg * (2.0 if goal == "lose" else 1.8))
    fat = round(weight_kg * 0.8)
    min_protein = round(weight_kg * 1.6)
    min_fat = round(weight_kg * 0.6)
    while protein * 4 + fat * 9 > calories and fat > min_fat:
        fat -= 1
    while protein * 4 + fat * 9 > calories and protein > min_protein:
        protein -= 1
    # Very low targets can make even both macro minimums impossible; never
    # report macro calories above the target in that case.
    while protein * 4 + fat * 9 > calories and fat > 0:
        fat -= 1
    while protein * 4 + fat * 9 > calories and protein > 0:
        protein -= 1
    carbs = max(0, int((calories - protein * 4 - fat * 9) // 4))
    return protein, carbs, fat
