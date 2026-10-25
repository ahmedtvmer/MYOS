"""Carry Program rationale across immutable versions that change exercises."""

from copy import deepcopy
from datetime import datetime, timezone
from typing import Any


def map_exercise_occurrences(
    old_exercises: list[dict[str, Any]],
    new_exercises: list[dict[str, Any]],
    *,
    week_order: int,
    day_order: int,
    source_positions: dict[int, int] | None = None,
    changes_by_position: dict[int, list[dict[str, Any]]] | None = None,
) -> list[dict[str, Any]]:
    """Create explicit positional mappings, retaining duplicate occurrences."""
    positions_by_id: dict[str, list[int]] = {}
    for position, exercise in enumerate(old_exercises, 1):
        positions_by_id.setdefault(str(exercise.get("exercise_id", "")), []).append(position)
    occurrences: dict[str, int] = {}
    mappings = []
    for to_position, exercise in enumerate(new_exercises, 1):
        exercise_id = str(exercise.get("exercise_id", ""))
        occurrence = occurrences.get(exercise_id, 0)
        occurrences[exercise_id] = occurrence + 1
        old_positions = positions_by_id.get(exercise_id, [])
        from_position = (source_positions or {}).get(to_position)
        if from_position is None and old_positions:
            from_position = old_positions[min(occurrence, len(old_positions) - 1)]
        mappings.append({
            "week_order": week_order,
            "day_order": day_order,
            "from_position": from_position,
            "to_position": to_position,
            "changes": (changes_by_position or {}).get(to_position, []),
        })
    return mappings


def occurrence_mappings_for_days(
    old_days: list[dict[str, Any]],
    new_days: list[dict[str, Any]],
    *,
    source_positions: dict[tuple[int, int], dict[int, int]] | None = None,
    changes_by_target: dict[tuple[int, int, int], list[dict[str, Any]]] | None = None,
) -> list[dict[str, Any]]:
    """Build explicit occurrence rows for every day in a program version."""
    old_by_day = {
        (int(day.get("week_order", 1)), int(day.get("day_order", 0))): day
        for day in old_days
    }
    mappings = []
    for day in new_days:
        week_order = int(day.get("week_order", 1))
        day_order = int(day.get("day_order", 0))
        day_key = (week_order, day_order)
        changes = {
            position: entries
            for (week, order, position), entries in (changes_by_target or {}).items()
            if (week, order) == day_key
        }
        mappings.extend(map_exercise_occurrences(
            old_by_day.get(day_key, {}).get("exercises", []),
            day.get("exercises", []),
            week_order=week_order,
            day_order=day_order,
            source_positions=(source_positions or {}).get(day_key),
            changes_by_position=changes,
        ))
    return mappings


def carry_program_rationale(
    old_program: Any,
    program_data: dict[str, Any],
    *,
    occurrence_mappings: list[dict[str, Any]],
    removed_entries: list[dict[str, Any]] | None = None,
) -> None:
    """Carry recorded rationale using explicit week/day exercise occurrences."""
    old_rationale = (
        old_program.get("program_rationale")
        if isinstance(old_program, dict)
        else getattr(old_program, "program_rationale", None)
    )
    rationale = deepcopy(old_rationale) if old_rationale else {
        "generator_reasons_available": False,
        "days": [],
    }
    now = datetime.now(timezone.utc).isoformat()
    rationale_days = _index_rationale_days(rationale)
    mappings_by_day = _index_occurrence_mappings(occurrence_mappings)
    for day in _program_data_days(program_data):
        _carry_day_reasons(day, rationale, rationale_days, mappings_by_day, now)
    _record_removed_entries(removed_entries or [], rationale_days, now)
    program_data["program_rationale"] = rationale


def _index_rationale_days(rationale: dict[str, Any]) -> dict[tuple[int, int], dict[str, Any]]:
    return {
        (int(day.get("week_order", 1)), int(day.get("day_order", 0))): day
        for day in rationale.get("days", [])
    }


def _index_occurrence_mappings(
    occurrence_mappings: list[dict[str, Any]],
) -> dict[tuple[int, int], dict[int, dict[str, Any]]]:
    by_day: dict[tuple[int, int], dict[int, dict[str, Any]]] = {}
    for mapping in occurrence_mappings:
        day_key = (int(mapping["week_order"]), int(mapping["day_order"]))
        by_day.setdefault(day_key, {})[int(mapping["to_position"])] = mapping
    return by_day


def _program_data_days(program_data: dict[str, Any]) -> list[dict[str, Any]]:
    if program_data.get("days"):
        return program_data["days"]
    if not program_data.get("weeks"):
        return []
    from agent.program_weeks import flatten_program_days, normalize_program_weeks

    return flatten_program_days(normalize_program_weeks(program_data))


def _carry_day_reasons(
    day: dict[str, Any],
    rationale: dict[str, Any],
    rationale_days: dict[tuple[int, int], dict[str, Any]],
    mappings_by_day: dict[tuple[int, int], dict[int, dict[str, Any]]],
    timestamp: str,
) -> None:
    day_key = (int(day.get("week_order", 1)), int(day.get("day_order", 0)))
    target = rationale_days.get(day_key)
    if target is None:
        target = {"week_order": day_key[0], "day_order": day_key[1], "exercises": []}
        rationale.setdefault("days", []).append(target)
        rationale_days[day_key] = target
    target["exercises"] = _copy_occurrence_reasons(
        day, target.get("exercises", []), mappings_by_day.get(day_key, {}), timestamp
    )


def _copy_occurrence_reasons(
    day: dict[str, Any],
    old_records: list[dict[str, Any]],
    mappings: dict[int, dict[str, Any]],
    timestamp: str,
) -> list[dict[str, Any]]:
    old_by_position = {
        int(record.get("position", index)): record
        for index, record in enumerate(old_records, 1)
    }
    copied = []
    for position, exercise in enumerate(day.get("exercises", []), 1):
        exercise_id = str(exercise.get("exercise_id", ""))
        mapping = mappings.get(position)
        from_position = mapping.get("from_position") if mapping else None
        prior = old_by_position.get(int(from_position)) if from_position is not None else None
        reason = deepcopy(prior or {"exercise_id": exercise_id, "position": position})
        reason.update(position=position, exercise_id=exercise_id)
        _append_change_entries(reason, mapping, timestamp)
        copied.append(reason)
    return copied


def _append_change_entries(
    reason: dict[str, Any], mapping: dict[str, Any] | None, timestamp: str
) -> None:
    changes = mapping.get("changes", []) if mapping else []
    if changes:
        reason.setdefault("changes", []).extend([
            {"code": item["code"], "params": item.get("params", {}), "at": timestamp}
            for item in changes
        ])


def _record_removed_entries(
    removed_entries: list[dict[str, Any]],
    rationale_days: dict[tuple[int, int], dict[str, Any]],
    timestamp: str,
) -> None:
    for removed in removed_entries:
        day_key = (int(removed["week_order"]), int(removed["day_order"]))
        target = rationale_days.get(day_key)
        if target is not None:
            target.setdefault("removed", []).append({
                "exercise_id": removed["exercise_id"],
                "code": removed["code"],
                "at": timestamp,
            })
