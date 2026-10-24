"""Player Nutrition setup, deterministic target selection, and version storage."""

import json
from datetime import date, timedelta
from typing import Any

from agent.program_blueprints import classify_goal
from core.nutrition_targets import NutritionCalculationInput, NutritionTargets, calculate_targets
from database.ledger.nutrition import NutritionPlanVersion, NutritionSetup


SCREENING_KEYS = (
    "pregnant_or_breastfeeding",
    "medical_condition",
    "eating_disorder",
)
MESSAGES = {
    "incomplete": ("Complete your Training profile before setting Nutrition targets.",
                   "أكمل الملف التدريبي قبل إعداد الأهداف الغذائية."),
    "under_18": ("MYOS does not set automatic Nutrition targets for players under 18.",
                 "لا يحدد ميوس أهدافًا غذائية تلقائية لمن هم دون 18 عامًا."),
    "blocked": ("MYOS will not set calorie targets. Please speak with a registered dietitian.",
                "لن يحدد ميوس أهداف السعرات. يُرجى التحدث إلى اختصاصي تغذية مسجل."),
}


def _message(state: str, language: str) -> str:
    return MESSAGES[state][1 if language == "ar" else 0]


def resolve_goal(current_goal: str | None, long_term_goal: str | None,
                 weight_kg: float, target_weight_kg: float | None) -> tuple[str, dict[str, Any]]:
    classified = classify_goal(current_goal, long_term_goal)
    target_goal = None
    if target_weight_kg is not None:
        difference = target_weight_kg - weight_kg
        target_goal = "lose" if difference < -1 else "gain" if difference > 1 else "maintain"
    if target_goal is not None and (classified is None or target_goal != classified):
        return target_goal, {"code": "target_weight", "target_weight_kg": target_weight_kg}
    if classified is not None:
        goal_text = current_goal if classify_goal(current_goal) else long_term_goal
        return classified, {"code": "current_goal", "goal_text": goal_text}
    return "maintain", {"code": "default"}


def _target_json(targets: NutritionTargets) -> dict[str, Any]:
    return {
        "calories": targets.calories, "protein_g": targets.protein_g,
        "carbs_g": targets.carbs_g, "fat_g": targets.fat_g,
        "bmr": targets.bmr, "maintenance": targets.maintenance,
        "calorie_floor": targets.calorie_floor, "floor_applied": targets.floor_applied,
        "weekly_rate_pct": targets.weekly_rate_pct,
    }


def setup(ledger: Any, body: dict[str, Any]) -> dict[str, Any]:
    with ledger.ledger_transaction():
        return _save_setup(ledger, body)


def _save_setup(ledger: Any, body: dict[str, Any]) -> dict[str, Any]:
    training_profile = ledger.get_nutrition_profile()
    if not _profile_is_complete(training_profile):
        return {"state": "incomplete", "targets": None,
                "message": _message("incomplete", body.get("language", "en"))}
    sex = body["sex"]
    activity = body["daily_activity"]
    answers = {key: bool(body["screening"][key]) for key in SCREENING_KEYS}
    if any(answers.values()):
        ledger.save_nutrition_setup(NutritionSetup(
            sex=sex, daily_activity=activity, screening=answers, plan=None,
        ))
        return {"state": "blocked", "targets": None,
                "message": _message("blocked", body.get("language", "en"))}
    if int(training_profile["age"]) < 18:
        return {"state": "under_18", "targets": None,
                "message": _message("under_18", body.get("language", "en"))}
    return _save_first_plan(ledger, training_profile,
                            NutritionSetup(sex, activity, answers, plan=None))


def _profile_is_complete(training_profile: dict[str, Any] | None) -> bool:
    return training_profile is not None and all(
        training_profile.get(field) is not None for field in ("age", "height_cm", "weight_kg")
    )


def _save_first_plan(ledger: Any, training_profile: dict[str, Any], setup_request: NutritionSetup) -> dict[str, Any]:
    age, height, weight = training_profile["age"], training_profile["height_cm"], training_profile["weight_kg"]
    goal, reason = resolve_goal(training_profile.get("current_goal"), training_profile.get("long_term_goal"),
                                float(weight), training_profile.get("target_weight_kg"))
    training_days = ledger.get_nutrition_training_days(training_profile.get("weekly_frequency") or 0)
    targets = _target_json(calculate_targets(NutritionCalculationInput(
        sex=setup_request.sex, age=int(age), height_cm=float(height), weight_kg=float(weight),
        daily_activity=setup_request.daily_activity, training_days=training_days, goal=goal, intensity="moderate",
    )))
    intensity = None if goal == "maintain" else "moderate"
    plan = NutritionPlanVersion(goal, reason, intensity, setup_request.daily_activity, targets)
    ledger.save_nutrition_setup(NutritionSetup(setup_request.sex, setup_request.daily_activity,
                                               setup_request.screening, plan))
    return {"state": "ready", "goal": goal, "goal_reason": reason,
            "intensity": intensity, "daily_activity": setup_request.daily_activity, "targets": targets}


def read(
    ledger: Any, language: str = "en", *, today: date | None = None
) -> dict[str, Any]:
    today = today or date.today()
    screening = ledger.get_nutrition_screening()
    answers = json.loads(screening[0]) if screening else None
    if answers and any(answers.values()):
        return {"state": "blocked", "targets": None, "screening": answers,
                "message": _message("blocked", language)}
    active_plan = ledger.get_active_nutrition_plan()
    if active_plan is None:
        nutrition_state = _read_without_plan(ledger, answers, language)
    else:
        nutrition_state = _read_active_plan(active_plan, answers)
    nutrition_state.update(_adherence_state(ledger, today))
    return nutrition_state


def _adherence_state(ledger: Any, today: date) -> dict[str, Any]:
    start = today - timedelta(days=6)
    entries = {entry["date"]: entry["value"] for entry in ledger.list_nutrition_adherence(
        start.isoformat(), today.isoformat())}
    profile = ledger.get_nutrition_profile()
    weights = ledger.list_weight_history("0001-01-01", "9999-12-31")
    return {
        "today_adherence": entries.get(today.isoformat()),
        "adherence_days": [
            {"date": (start + timedelta(days=offset)).isoformat(),
             "value": entries.get((start + timedelta(days=offset)).isoformat())}
            for offset in range(7)
        ],
        "latest_weight": weights[-1]["weight_kg"] if weights else profile.get("weight_kg") if profile else None,
        "target_weight": profile.get("target_weight_kg") if profile else None,
    }


def log_adherence(ledger: Any, value: str, today: date) -> tuple[dict[str, Any], str]:
    updated_at = ledger.upsert_nutrition_adherence(today.isoformat(), value)
    return read(ledger, today=today), updated_at


def _read_without_plan(ledger: Any, answers: dict[str, bool] | None,
                       language: str) -> dict[str, Any]:
    training_profile = ledger.get_nutrition_profile()
    state = "not_started"
    if training_profile is None:
        state = "incomplete"
    elif int(training_profile.get("age") or 0) < 18:
        state = "under_18"
    message = _message(state, language) if state in MESSAGES else None
    return {"state": state, "targets": None, "screening": answers,
            "sex": training_profile.get("gender") if training_profile else None,
            "daily_activity": training_profile.get("daily_activity") if training_profile else None,
            "message": message}


def _read_active_plan(active_plan: Any, answers: dict[str, bool] | None) -> dict[str, Any]:
    return {"state": "ready", "goal": active_plan["goal"],
            "goal_reason": json.loads(active_plan["goal_reason_data_json"]),
            "intensity": active_plan["intensity"], "daily_activity": active_plan["daily_activity"],
            "targets": json.loads(active_plan["targets_json"]), "author": active_plan["author"],
            "provenance": active_plan["provenance"], "screening": answers}


def update_activity(ledger: Any, activity: str, today: date | None = None) -> dict[str, Any]:
    training_profile = ledger.get_nutrition_profile()
    active_plan = ledger.get_active_nutrition_plan()
    screening = ledger.get_nutrition_screening()
    if screening and any(json.loads(screening[0]).values()):
        return read(ledger, today=today)
    if not _profile_is_complete(training_profile) or active_plan is None:
        return read(ledger, today=today)
    if int(training_profile["age"]) < 18:
        return read(ledger, today=today)
    targets = _recalculate_activity_targets(ledger, training_profile, active_plan, activity)
    with ledger.ledger_transaction():
        ledger.update_nutrition_activity(activity)
        ledger.save_nutrition_plan(NutritionPlanVersion(
            active_plan["goal"], json.loads(active_plan["goal_reason_data_json"]),
            active_plan["intensity"], activity, targets,
        ))
    return read(ledger, today=today)


def _recalculate_activity_targets(ledger: Any, training_profile: dict[str, Any],
                                  active_plan: Any, activity: str) -> dict[str, Any]:
    goal = active_plan["goal"]
    age, height, weight = (training_profile["age"], training_profile["height_cm"],
                           training_profile["weight_kg"])
    return _target_json(calculate_targets(NutritionCalculationInput(
        sex=training_profile.get("gender", "male"), age=int(age), height_cm=float(height), weight_kg=float(weight),
        daily_activity=activity,
        training_days=ledger.get_nutrition_training_days(training_profile.get("weekly_frequency") or 0),
        goal=goal, intensity=active_plan["intensity"] or "moderate",
    )))
