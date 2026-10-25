"""Carry Program rationale across immutable versions that change exercises."""

from copy import deepcopy
from datetime import datetime, timezone
from typing import Any


def record_exercise_changes(
    old_program: Any,
    program_data: dict[str, Any],
    changes: dict[str, list[dict[str, Any]]],
    *,
    source_ids: dict[str, str] | None = None,
) -> None:
    """Copy reasons for surviving exercises and append supplied change entries.

    ``changes`` is keyed by exercise id. Position is re-derived from the new
    version, while the original generator rationale follows the exercise.
    """
    old_rationale = getattr(old_program, "program_rationale", None)
    if not old_rationale:
        return
    rationale = deepcopy(old_rationale)
    rationale_days = {int(day.get("day_order", 0)): day for day in rationale.get("days", [])}
    now = datetime.now(timezone.utc).isoformat()
    for day in program_data.get("days", []):
        target = rationale_days.get(int(day.get("day_order", 0)))
        if target is None:
            continue
        old_by_id = {
            str(exercise.get("exercise_id", "")): exercise
            for exercise in target.get("exercises", [])
        }
        copied = []
        for position, exercise in enumerate(day.get("exercises", [])):
            exercise_id = str(exercise.get("exercise_id", ""))
            source_id = (source_ids or {}).get(exercise_id, exercise_id)
            reason = deepcopy(old_by_id.get(source_id, {"rationale": {}}))
            reason.update(position=position + 1, exercise_id=exercise_id)
            if exercise_id in changes:
                reason.setdefault("changes", []).extend([
                    {"code": item["code"], "params": item.get("params", {}), "at": now}
                    for item in changes[exercise_id]
                ])
            copied.append(reason)
        target["exercises"] = copied
    program_data["program_rationale"] = rationale
