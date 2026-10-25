"""Permanent edits to a player's active program day."""

from copy import deepcopy
from agent.ProgramState import program_exercise_working_sets
from dataclasses import dataclass, replace
from enum import Enum
from typing import Any

from agent.program_rationale import CHANGE_PROGRAM_EDIT_REMOVED, CHANGE_PROGRAM_EDIT_REORDERED, CHANGE_PROGRAM_EDIT_TRIMMED
from agent.program_weeks import (
    flatten_program_days,
    find_program_day,
    normalize_program_weeks,
)
from service import analytics
from service.program_analytics import ProgramAnalyticsActor, capture_program_edited
from service.programs import COACH_CONTROLLED_ERROR, player_controls_program


class ProgramEditErrorCode(str, Enum):
    DAY_NOT_FOUND = "day_not_found"
    EXERCISE_NOT_ON_DAY = "exercise_not_on_day"
    DUPLICATE_EXERCISE = "duplicate_exercise"
    EMPTY_DAY = "empty_day"
    INVALID_SET_COUNT = "invalid_set_count"
    COACH_CONTROLLED = "coach_controlled"
    NO_ACTIVE_PROGRAM = "no_active_program"
    PROGRAM_CHANGED = "program_changed"


PROGRAM_EDIT_ERRORS = {
    ProgramEditErrorCode.DAY_NOT_FOUND: "That day is not part of your current program.",
    ProgramEditErrorCode.EXERCISE_NOT_ON_DAY: "That exercise is not in that day of your current program.",
    ProgramEditErrorCode.DUPLICATE_EXERCISE: "Each exercise entry can appear only once in a Program edit.",
    ProgramEditErrorCode.EMPTY_DAY: "A training day must keep at least one working-set exercise.",
    ProgramEditErrorCode.INVALID_SET_COUNT: "Working sets must be from 1 to the current prescription.",
    ProgramEditErrorCode.COACH_CONTROLLED: COACH_CONTROLLED_ERROR,
    ProgramEditErrorCode.NO_ACTIVE_PROGRAM: "No active program.",
    ProgramEditErrorCode.PROGRAM_CHANGED: "The program changed since this edit was opened.",
}
PROGRAM_EDIT_MESSAGE_CODES = {
    ProgramEditErrorCode.DAY_NOT_FOUND: "program.edit.day_not_found.v1",
    ProgramEditErrorCode.EXERCISE_NOT_ON_DAY: "program.edit.exercise_not_on_day.v1",
    ProgramEditErrorCode.DUPLICATE_EXERCISE: "program.edit.duplicate_exercise.v1",
    ProgramEditErrorCode.EMPTY_DAY: "program.edit.empty_day.v1",
    ProgramEditErrorCode.INVALID_SET_COUNT: "program.edit.invalid_set_count.v1",
    ProgramEditErrorCode.COACH_CONTROLLED: "program.coach_controls.v1",
    ProgramEditErrorCode.NO_ACTIVE_PROGRAM: "program.no_active.v1",
    ProgramEditErrorCode.PROGRAM_CHANGED: "program.edit.changed.v1",
}


@dataclass(frozen=True)
class ProgramEditExercise:
    source_index: int
    exercise_id: str
    target_sets: int


@dataclass(frozen=True)
class ProgramEdit:
    day_name: str
    expected_active_version: int
    exercises: list[ProgramEditExercise]
    player_account_id: str
    actor: ProgramAnalyticsActor
    week_order: int | None = None
    day_order: int | None = None
    client: analytics.ClientContext = analytics.UNKNOWN_CLIENT


@dataclass(frozen=True)
class _PreparedProgramEdit:
    program_copy: dict[str, Any]
    day: dict[str, Any]


def edit_active_program_day(db: Any, ledger: Any, edit_request: ProgramEdit) -> dict[str, Any]:
    active, failure = _active_program_for_edit(db, ledger, edit_request)
    if failure:
        return failure
    current_position = ledger.get_program_position(active)
    if edit_request.week_order is None:
        edit_request = replace(edit_request, week_order=current_position.current_week)
    prepared, failure = _prepare_program_edit(active, edit_request)
    if failure:
        return failure
    previous_version = active.version
    if _is_unchanged(prepared.day["exercises"], edit_request.exercises):
        return _updated_program_result(ledger, previous_version)
    _apply_program_edit(prepared, edit_request.exercises)
    from service.program_rationale_changes import record_exercise_changes
    old_day = next((day for day in active.days if int(day.day_order) == int(edit_request.day_order or 1)
                    and int(getattr(day, "week_order", 1)) == int(edit_request.week_order or 1)), None)
    old_exercises = [exercise.model_dump() for exercise in old_day.exercises] if old_day else []
    new_exercises = prepared.day.get("exercises", [])
    changes = {}
    old_order = [str(ex["exercise_id"]) for ex in old_exercises]
    new_order = [str(ex["exercise_id"]) for ex in new_exercises]
    for position, exercise_id in enumerate(new_order):
        old = next((item for item in old_exercises if str(item["exercise_id"]) == exercise_id), None)
        new = next(item for item in new_exercises if str(item["exercise_id"]) == exercise_id)
        if old is None:
            continue
        before, after = int(old.get("target_sets", 0)), int(new.get("target_sets", 0))
        if before != after:
            changes[exercise_id] = [{"code": CHANGE_PROGRAM_EDIT_TRIMMED, "params": {"from_sets": before, "to_sets": after}}]
        old_pos = old_order.index(exercise_id)
        if old_pos != position:
            changes.setdefault(exercise_id, []).append({"code": CHANGE_PROGRAM_EDIT_REORDERED, "params": {"from_position": old_pos + 1, "to_position": position + 1}})
    record_exercise_changes(active, prepared.program_copy, changes)
    rationale = prepared.program_copy.get("program_rationale")
    if rationale:
        day_record = next((item for item in rationale.get("days", []) if int(item.get("day_order", 0)) == int(edit_request.day_order or 1)), None)
        if day_record is not None:
            removed_ids = [exercise_id for exercise_id in old_order if exercise_id not in new_order]
            if removed_ids:
                from datetime import datetime, timezone
                at = datetime.now(timezone.utc).isoformat()
                day_record["removed"] = day_record.get("removed", []) + [
                    {"exercise_id": exercise_id, "code": CHANGE_PROGRAM_EDIT_REMOVED, "at": at}
                    for exercise_id in removed_ids
                ]
    prepared.program_copy.pop("created_at", None)
    ledger.save_training_program(
        prepared.program_copy,
        published_by_coach_account_id=None,
        starting_position=current_position,
    )
    updated = ledger.get_active_program()
    if updated is not None:
        capture_program_edited(edit_request.actor, updated, client=edit_request.client)
    return _updated_program_result(ledger, previous_version)


def _active_program_for_edit(db: Any, ledger: Any, edit_request: ProgramEdit) -> tuple[Any, dict[str, Any] | None]:
    if not player_controls_program(db, ledger, edit_request.player_account_id):
        return None, _failure(ProgramEditErrorCode.COACH_CONTROLLED)
    active = ledger.get_active_program()
    if active is None:
        return None, _failure(ProgramEditErrorCode.NO_ACTIVE_PROGRAM)
    if active.version != edit_request.expected_active_version:
        return None, _failure(ProgramEditErrorCode.PROGRAM_CHANGED)
    return active, None


def _prepare_program_edit(
    active: Any,
    edit_request: ProgramEdit,
) -> tuple[_PreparedProgramEdit | None, dict[str, Any] | None]:
    program_copy = active.model_dump()
    weeks = normalize_program_weeks(program_copy)
    week_order = edit_request.week_order or 1
    day = find_program_day(
        weeks,
        week_order,
        day_order=edit_request.day_order,
        day_name=edit_request.day_name,
    )
    if day is None:
        return None, _failure(ProgramEditErrorCode.DAY_NOT_FOUND)
    if not edit_request.exercises:
        return None, _failure(ProgramEditErrorCode.EMPTY_DAY)
    failure = _validate_program_edit(day["exercises"], edit_request.exercises)
    if failure:
        return None, failure
    program_copy["weeks"] = weeks
    program_copy["days"] = flatten_program_days(weeks)
    return _PreparedProgramEdit(program_copy, day), None


def _validate_program_edit(
    current_exercises: list[dict[str, Any]],
    requested_exercises: list[ProgramEditExercise],
) -> dict[str, Any] | None:
    requested_indexes = [exercise.source_index for exercise in requested_exercises]
    if len(set(requested_indexes)) != len(requested_indexes):
        return _failure(ProgramEditErrorCode.DUPLICATE_EXERCISE)
    if any(
        exercise.source_index < 0
        or exercise.source_index >= len(current_exercises)
        or str(current_exercises[exercise.source_index]["exercise_id"]) != exercise.exercise_id
        for exercise in requested_exercises
    ):
        return _failure(ProgramEditErrorCode.EXERCISE_NOT_ON_DAY)
    if any(
        exercise.target_sets < 1
        or exercise.target_sets > (
            int(current_exercises[exercise.source_index]["set_groups"][0]["sets"])
            if len(current_exercises[exercise.source_index].get("set_groups") or []) > 1
            else program_exercise_working_sets(current_exercises[exercise.source_index])
        )
        for exercise in requested_exercises
    ):
        return _failure(ProgramEditErrorCode.INVALID_SET_COUNT)
    return None


def _is_unchanged(
    current_exercises: list[dict[str, Any]],
    requested_exercises: list[ProgramEditExercise],
) -> bool:
    return len(current_exercises) == len(requested_exercises) and all(
        requested.source_index == index
        and (
            int(current["set_groups"][0]["sets"])
            if len(current.get("set_groups") or []) > 1
            else program_exercise_working_sets(current)
        ) == requested.target_sets
        for index, (current, requested) in enumerate(zip(current_exercises, requested_exercises))
    )


def _apply_program_edit(
    prepared: _PreparedProgramEdit,
    requested_exercises: list[ProgramEditExercise],
) -> None:
    current_exercises = prepared.day["exercises"]
    prepared.day["exercises"] = []
    for requested in requested_exercises:
        exercise_copy = deepcopy(current_exercises[requested.source_index])
        groups = exercise_copy.get("set_groups") or []
        if groups:
            groups[0]["sets"] = requested.target_sets
            exercise_copy["set_groups"] = groups
            exercise_copy["target_sets"] = groups[0]["sets"]
        else:
            exercise_copy["target_sets"] = requested.target_sets
        prepared.day["exercises"].append(exercise_copy)


def _updated_program_result(ledger: Any, previous_version: int) -> dict[str, Any]:
    updated = ledger.get_active_program()
    if updated is None:
        return _failure(ProgramEditErrorCode.NO_ACTIVE_PROGRAM)
    return {**updated.model_dump(), "previous_version": previous_version}


def _failure(code: ProgramEditErrorCode) -> dict[str, Any]:
    return {
        "code": code,
        "error": PROGRAM_EDIT_ERRORS[code],
        "message_code": PROGRAM_EDIT_MESSAGE_CODES[code],
    }
