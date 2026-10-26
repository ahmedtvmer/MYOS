from core.cardio_calories import estimate_cardio_calories


def test_cardio_estimates_cover_machines_and_treadmill_modes():
    cases = [
        ({"machine": "treadmill", "minutes": 30, "speed_kmh": 5, "incline_pct": 0}, 70, 88, False),
        ({"machine": "treadmill", "minutes": 30, "speed_kmh": 10, "incline_pct": 0}, 70, 350, False),
        ({"machine": "stairmaster", "minutes": 30, "level": 5}, 70, 203, False),
        ({"machine": "bike", "minutes": 30, "level": 5}, 70, 203, False),
        ({"machine": "elliptical", "minutes": 30, "level": 5}, 70, 140, False),
        ({"machine": "rower", "minutes": 30, "level": 5}, 70, 140, False),
        ({"machine": "stairmaster", "minutes": 30}, 70, 203, True),
        ({"machine": "bike", "minutes": 30}, 70, 203, True),
        ({"machine": "elliptical", "minutes": 30}, 70, 140, True),
        ({"machine": "rower", "minutes": 30}, 70, 140, True),
        ({"machine": "bike", "minutes": 30, "watts": 100}, 70, 175, False),
        ({"machine": "rower", "minutes": 30, "watts": 120}, 70, 228, False),
        ({"machine": "rower", "minutes": 30, "watts": 99.5}, 70, 140, False),
        ({"machine": "elliptical", "minutes": 30, "watts": 150}, 70, 140, True),
        ({"machine": "other", "minutes": 30}, 70, 70, True),
        ({"machine": "other", "minutes": 30, "level": 5}, 70, 70, True),
    ]
    for entry, weight, expected, flagged in cases:
        result = estimate_cardio_calories(entry, weight)
        assert result["kcal"] == expected
        assert result["estimate"] is flagged


def test_estimate_flag_and_bodyweight_and_incline_effects():
    base = {"machine": "treadmill", "minutes": 20, "speed_kmh": 5}
    low = estimate_cardio_calories(base, 60)
    heavy = estimate_cardio_calories(base, 90)
    uphill = estimate_cardio_calories({**base, "incline_pct": 10}, 60)
    assert low["estimate"] is True
    assert estimate_cardio_calories({**base, "incline_pct": 0}, 60)["estimate"] is False
    assert heavy["kcal"] > low["kcal"]
    assert uphill["kcal"] > estimate_cardio_calories({**base, "incline_pct": 0}, 60)["kcal"]


def test_outdoor_speed_uses_distance_or_moderate_default():
    assert estimate_cardio_calories(
        {"machine": "outdoor_walk_run", "minutes": 30, "distance_m": 5000}, 70
    )["kcal"] == 350
    assert estimate_cardio_calories(
        {"machine": "outdoor_walk_run", "minutes": 30}, 70
    )["estimate"] is True


def test_missing_bodyweight_uses_flagged_default():
    estimate = estimate_cardio_calories(
        {"machine": "bike", "minutes": 30, "level": 5}, None
    )
    assert estimate == {"kcal": 203, "estimate": True}
