import pytest

from core.nutrition_targets import NutritionCalculationInput, calculate_targets


def _calculate(**inputs):
    return calculate_targets(NutritionCalculationInput(**inputs))


@pytest.mark.parametrize("sex,expected_bmr", [("male", 1780), ("female", 1614)])
def test_targets_use_mifflin_st_jeor_and_return_macros(sex, expected_bmr):
    result = _calculate(
        sex=sex, age=30, height_cm=180, weight_kg=80,
        daily_activity="mostly_sitting", training_days=0,
        goal="maintain", intensity="moderate",
    )
    assert result.bmr == expected_bmr
    assert result.calories == round(result.calories / 10) * 10
    assert result.protein_g == 144
    assert result.fat_g == 64
    assert result.carbs_g == (247 if sex == "male" else 197)
    assert result.calories == (2140 if sex == "male" else 1940)


@pytest.mark.parametrize("calories,weight,training,expected_fiber,expected_water", [
    (2140, 80, False, 30, 2750), (2140, 80, True, 30, 3250),
    (1800, 65, False, 25, 2250),
])
def test_fiber_and_water_targets(calories, weight, training, expected_fiber, expected_water):
    from core.nutrition_targets import calculate_fiber_water_targets

    assert calculate_fiber_water_targets(calories, weight, training) == {
        "fiber_g": expected_fiber, "water_ml": expected_water,
    }


def test_floor_recomputes_real_weekly_rate():
    result = _calculate(
        sex="female", age=30, height_cm=160, weight_kg=50,
        daily_activity="mostly_sitting", training_days=0,
        goal="lose", intensity="aggressive",
    )
    assert result.floor_applied
    assert result.calories == result.calorie_floor
    expected_maintenance = 1189 * 1.2
    expected_rate = round((expected_maintenance - result.calorie_floor) * 7 / (50 * 7700) * 100, 4)
    assert result.weekly_rate_pct == expected_rate


def test_under_18_refuses_targets():
    with pytest.raises(ValueError, match="under 18"):
        _calculate(
            sex="male", age=17, height_cm=180, weight_kg=80,
            daily_activity="mostly_sitting", training_days=2,
            goal="gain", intensity="moderate",
        )


@pytest.mark.parametrize("activity,factor", [
    ("mostly_sitting", 1.2), ("on_feet", 1.375), ("physical_job", 1.55),
])
@pytest.mark.parametrize("goal,intensity,rate", [
    ("lose", "light", 0.25), ("lose", "moderate", 0.5),
    ("lose", "aggressive", 1.0), ("maintain", "light", 0.0),
    ("maintain", "moderate", 0.0), ("maintain", "aggressive", 0.0),
    ("gain", "light", 0.1), ("gain", "moderate", 0.25),
    ("gain", "aggressive", 0.5),
])
@pytest.mark.parametrize("training_days", [0, 2, 7])
def test_activity_and_pace_table(activity, factor, goal, intensity, rate, training_days):
    result = _calculate(
        sex="male", age=30, height_cm=180, weight_kg=80,
        daily_activity=activity, training_days=training_days, goal=goal, intensity=intensity,
    )
    maintenance = 1780 * (factor + training_days * 0.0625)
    assert result.maintenance == round(maintenance, 1)
    if goal == "lose":
        actual_rate = max(0, maintenance - result.calories) * 7 / (80 * 7700) * 100
    elif goal == "gain":
        actual_rate = max(0, result.calories - maintenance) * 7 / (80 * 7700) * 100
    else:
        actual_rate = 0
    assert result.weekly_rate_pct == round(actual_rate, 4)
    assert result.protein_g * 4 + result.fat_g * 9 + result.carbs_g * 4 <= result.calories


@pytest.mark.parametrize("intensity,expected", [("moderate", 1480), ("aggressive", 1480)])
def test_high_weight_short_woman_macros_fit_calorie_floor(intensity, expected):
    result = _calculate(sex="female", age=60, height_cm=150, weight_kg=100,
        daily_activity="mostly_sitting", training_days=0, goal="lose", intensity=intensity)
    assert result.calories == expected
    assert result.calorie_floor == 1476.5
    assert (result.protein_g, result.fat_g, result.carbs_g) == (200, 75, 1)
    assert result.protein_g * 4 + result.fat_g * 9 + result.carbs_g * 4 <= result.calories


def test_gain_rounding_keeps_realized_rate_within_half_percent_cap():
    result = _calculate(sex="male", age=30, height_cm=180, weight_kg=80,
        daily_activity="mostly_sitting", training_days=0, goal="gain", intensity="aggressive")
    assert result.calories == 2570
    assert result.weekly_rate_pct <= 0.5


def test_mens_calorie_floor_and_rounding():
    result = _calculate(sex="male", age=80, height_cm=150, weight_kg=50,
        daily_activity="mostly_sitting", training_days=0, goal="lose", intensity="aggressive")
    assert result.calorie_floor == 1500
    assert result.calories == 1500
    assert result.floor_applied


@pytest.mark.parametrize("goal,intensity,expected_calories,expected_carbs", [
    ("lose", "light", 1920, 176),
    ("maintain", "moderate", 2140, 247),
    ("gain", "aggressive", 2570, 354),
])
def test_calories_and_carbs_match_fixed_rate_examples(goal, intensity, expected_calories, expected_carbs):
    result = _calculate(sex="male", age=30, height_cm=180, weight_kg=80,
        daily_activity="mostly_sitting", training_days=0, goal=goal, intensity=intensity)
    assert result.maintenance == 2136.0
    assert result.calories == expected_calories
    assert result.carbs_g == expected_carbs
