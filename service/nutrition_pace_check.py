"""Consent-based weekly Nutrition pace proposals (#467)."""

import json
import math
from dataclasses import dataclass, replace
from datetime import UTC, date, datetime
from typing import Any

from service import weight_history


MIN_HISTORY_DAYS = 21
MIN_SEPARATE_WEEKS = 3
PACE_DIFFERENCE_THRESHOLD_PCT = 0.15
MAX_CALORIE_CHANGE = 250
CALORIES_PER_KG = 7700


@dataclass(frozen=True)
class PaceCheckContext:
    plan: Any
    profile: dict[str, Any]
    targets: dict[str, Any]
    weight: float
    actual_rate_pct: float
    planned_rate_pct: float = 0
    calorie_floor: int = 0


def evaluate(ledger: Any, today: date) -> dict[str, Any] | None:
    plan = ledger.get_active_nutrition_plan()
    if plan is None or _pending_proposal(ledger, int(plan["id"])) is not None:
        return None
    last_checked = ledger.get_last_nutrition_pace_check_date()
    if last_checked and (today - date.fromisoformat(last_checked)).days < 7:
        return None
    points = _eligible_weight_points(ledger, plan, today)
    if points is None:
        return None
    proposal = _proposal_for_points(ledger, plan, points)
    if proposal is None:
        _record_check(ledger, today)
        return None
    now = datetime.now(UTC).isoformat()
    with ledger.ledger_transaction():
        proposal_id = ledger.create_nutrition_pace_proposal(int(plan["id"]), proposal, now)
        ledger.record_nutrition_pace_check(today.isoformat())
    return {"id": proposal_id, "plan_version_id": int(plan["id"]), "payload": proposal,
            "status": "pending", "created_at": now, "decided_at": None, "decided_by": None}


def _pending_proposal(ledger: Any, plan_version_id: int) -> dict[str, Any] | None:
    proposal = ledger.get_nutrition_pace_proposal()
    return proposal if proposal and proposal["status"] == "pending" and int(
        proposal["plan_version_id"]
    ) == plan_version_id else None


def _eligible_weight_points(ledger: Any, plan: Any, today: date) -> list[Any] | None:
    created_at = datetime.fromisoformat(str(plan["created_at"]).replace("Z", "+00:00"))
    if created_at.tzinfo is None:
        created_at = created_at.replace(tzinfo=UTC)
    started = weight_history.player_local_date(ledger, str(ledger.ledger_id), created_at)
    if (today - started).days < MIN_HISTORY_DAYS:
        return None
    trend = weight_history.get_weight_trend(
        None, weight_history.WeightTrendQuery(
            ledger_id=str(ledger.ledger_id), weeks=52, as_of=today), ledger,
    )
    points = [point for point in trend.points if started <= point.date <= today]
    weeks = {(point.date.isocalendar().year, point.date.isocalendar().week) for point in points}
    if len(weeks) < MIN_SEPARATE_WEEKS or len(points) < 2:
        return None
    return points if (points[-1].date - points[0].date).days >= MIN_HISTORY_DAYS else None


def _proposal_for_points(ledger: Any, plan: Any, points: list[Any]) -> dict[str, Any] | None:
    profile = ledger.get_nutrition_profile() or {}
    targets_json = json.loads(plan["targets_json"])
    split_targets = all(isinstance(targets_json.get(key), dict)
                        for key in ("training_day", "rest_day"))
    target_options = ({key: targets_json[key] for key in ("training_day", "rest_day")}
                      if split_targets else {})
    targets = (target_options.get("training_day") if split_targets
               else targets_json.get("daily") or targets_json)
    if split_targets:
        training_days = ledger.get_nutrition_training_days(profile.get("weekly_frequency") or 0)
        average_calories = (
            target_options["training_day"]["calories"] * training_days
            + target_options["rest_day"]["calories"] * (7 - training_days)
        ) / 7
        targets = {**targets, "calories": round(average_calories)}
    first, latest = points[0], points[-1]
    weight = float(latest.weight_kg)
    elapsed = (latest.date - first.date).days
    actual_rate = (float(latest.weight_kg) - float(first.weight_kg)) / elapsed * 7 / weight * 100
    target = profile.get("target_weight_kg")
    context = _planned_rate_and_floor(
        ledger, PaceCheckContext(plan, profile, targets, weight, actual_rate)
    )
    if plan["goal"] != "maintain" and target is not None and abs(weight - float(target)) <= 1:
        proposal = _maintain_proposal(ledger, context)
    else:
        proposal = _pace_proposal(context)
    if proposal is not None and target_options:
        proposal["target_options"] = {
            day: _recompute_macros(target, max(context.calorie_floor,
                int(target["calories"]) + proposal["calorie_change"]), weight)
            for day, target in target_options.items()
        }
    return proposal


def _maintain_proposal(ledger: Any, context: PaceCheckContext) -> dict[str, Any]:
    from service.nutrition import _calculate_for

    calculated = _calculate_for(ledger, context.profile,
        context.profile.get("gender") or "male", context.plan["daily_activity"],
        "maintain", "moderate")
    proposal_targets = _recompute_macros(context.targets, int(calculated["calories"]), context.weight)
    return {"kind": "maintain_at_target", "goal": "maintain", "intensity": None,
        "actual_rate_pct": round(context.actual_rate_pct, 4), "planned_rate_pct": 0,
        "calorie_change": proposal_targets["calories"] - int(context.targets["calories"]),
        "targets": proposal_targets}


def _pace_proposal(context: PaceCheckContext) -> dict[str, Any] | None:
    difference = context.planned_rate_pct - context.actual_rate_pct
    if abs(difference) <= PACE_DIFFERENCE_THRESHOLD_PCT:
        return None
    requested_change = round(max(-MAX_CALORIE_CHANGE, min(MAX_CALORIE_CHANGE,
        difference / 100 * context.weight * CALORIES_PER_KG / 7)))
    requested_calories = int(context.targets["calories"]) + requested_change
    calories = max(context.calorie_floor, requested_calories)
    adjusted_targets = _recompute_macros(context.targets, calories, context.weight)
    return {"kind": "pace", "goal": context.plan["goal"], "intensity": context.plan["intensity"],
        "actual_rate_pct": round(context.actual_rate_pct, 4),
        "planned_rate_pct": round(context.planned_rate_pct, 4),
        "calorie_change": calories - int(context.targets["calories"]),
        "floor_limited": requested_calories < context.calorie_floor,
        "calorie_floor": context.calorie_floor, "targets": adjusted_targets}


def _record_check(ledger: Any, today: date) -> None:
    with ledger.ledger_transaction():
        ledger.record_nutrition_pace_check(today.isoformat())


def _recompute_macros(current: dict[str, Any], calories: int, weight: float) -> dict[str, int]:
    protein = int(current["protein_g"])
    fat = int(current["fat_g"])
    if protein * 4 + fat * 9 > calories:
        min_fat = round(weight * 0.6)
        min_protein = round(weight * 1.6)
        while protein * 4 + fat * 9 > calories and fat > min_fat:
            fat -= 1
        while protein * 4 + fat * 9 > calories and protein > min_protein:
            protein -= 1
        while protein * 4 + fat * 9 > calories and fat > 0:
            fat -= 1
        while protein * 4 + fat * 9 > calories and protein > 0:
            protein -= 1
    carbs = max(0, (calories - protein * 4 - fat * 9) // 4)
    return {"calories": calories, "protein_g": protein, "carbs_g": carbs, "fat_g": fat}


def _planned_rate_and_floor(ledger: Any, context: PaceCheckContext) -> PaceCheckContext:
    from service.nutrition import _calculate_for

    baseline = _calculate_for(
        ledger, context.profile, context.profile.get("gender") or "male",
        context.plan["daily_activity"], "maintain", "moderate",
    )
    floor = math.ceil(baseline["calorie_floor"])
    rate = context.targets.get("weekly_rate_pct")
    if rate is not None:
        planned_rate = -float(rate) if context.plan["goal"] == "lose" else float(rate)
    else:
        calorie_gap = int(context.targets["calories"]) - float(baseline["maintenance"])
        planned_rate = calorie_gap * 7 / (context.weight * CALORIES_PER_KG) * 100
    return replace(context, planned_rate_pct=planned_rate, calorie_floor=floor)


