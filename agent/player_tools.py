"""Read-only, turn-scoped tools for the player assistant."""

from __future__ import annotations

import json
import logging
import math
import time
from collections.abc import Callable, Sequence
from concurrent.futures import ThreadPoolExecutor, TimeoutError
from dataclasses import dataclass
from typing import Any

from langchain_core.messages import ToolMessage
from langchain_core.tools import StructuredTool
from pydantic import BaseModel

from database.ledger.profile import PLAYER_PROFILE_STORAGE_DEFAULTS
from agent.focus_muscles import FOCUS_REVIEW_MUSCLES
from service.injuries import render_public_injury_record
from service.nutrition import assistant_projection
from service.player_weight_context import render_player_weight_context
from service.weight_history import WeightTrendQuery, get_weight_trend, player_local_date
from agent.player_prompt import (
    HOSTED_PROMPT_MAX_BYTES,
    HOSTED_PROMPT_TOOL_RESULT_RESERVE_BYTES,
)

logger = logging.getLogger(__name__)

MAX_TOOL_RESULT_BYTES = 4 * 1024
TOOL_TIMEOUT_SECONDS = 5.0
_TRUNCATED_PROMPT_RESULT = '{"status":"truncated"}'
_INJURY_CLEARANCE_TOOL_FIELDS = (
    "exercise_name",
    "original_wording",
    "verdict",
    "note",
    "recorded_at",
    "source",
)


class EmptyToolArgs(BaseModel):
    """Schema for a read tool that takes no arguments."""


class ProgramRationaleArgs(BaseModel):
    """Optional scope for the active program's recorded rationale."""

    day_name: str | None = None
    day_order: int | None = None
    exercise_name: str | None = None
    exercise_id: str | None = None
    week_order: int | None = None
    page: int = 0


class ActiveProgramArgs(BaseModel):
    """Optional day scope for the active program."""

    day_name: str | None = None


@dataclass(frozen=True)
class PlayerReadTool:
    """A reusable entry in the player read-tool registry."""

    name: str
    description: str
    args_schema: type[BaseModel]
    reader: Callable[..., dict[str, Any]]
    status_en: str
    status_ar: str
    args_reader: Callable[[Any, BaseModel], dict[str, Any]] | None = None
    timeout_seconds: float = TOOL_TIMEOUT_SECONDS


def _not_set(profile_value: Any) -> Any:
    if profile_value is None:
        return "not set"
    if isinstance(profile_value, str):
        cleaned = profile_value.strip()
        if not cleaned:
            return "not set"
        return cleaned
    if isinstance(profile_value, float) and not math.isfinite(profile_value):
        return "not set"
    return profile_value


_PROFILE_FIELDS = (
    ("gender", "gender"),
    ("proportions", "proportions"),
    ("age", "age"),
    ("height_cm", "height_cm"),
    ("weight_kg", "weight_kg"),
    ("target_weight_kg", "target_weight_kg"),
    ("current_goal", "current_goal"),
    ("long_term_goal", "long_term_goal"),
    ("training_age_years", "training_age_years"),
    ("rep_preference", "rep_preference"),
    ("equipment_access", "equipment_access"),
    # Backward-compatible projection maintained by the injury-record writer.
    ("injuries_or_limitations", "injuries_or_limitations"),
    ("weekly_frequency", "weekly_frequency"),
    ("stress_and_sleep", "stress_and_sleep"),
    ("weak_points", "weak_points"),
)


def _is_storage_default(key: str, stored_value: Any) -> bool:
    default = PLAYER_PROFILE_STORAGE_DEFAULTS.get(key)
    if default is None:
        return False
    if isinstance(stored_value, str) and isinstance(default, str):
        return stored_value.strip().casefold() == default.casefold()
    try:
        return float(stored_value) == float(default)
    except (TypeError, ValueError):
        return stored_value == default


def _profile_has_completion_evidence(ledger: Any) -> bool:
    intake_state = ledger.get_intake_state()
    if intake_state is not None and intake_state.get("status") == "confirmed":
        return True
    completion_getter = getattr(ledger, "get_onboarding_analytics_completed_at", None)
    if callable(completion_getter) and completion_getter():
        return True
    return ledger.get_active_program() is not None


def _read_profile(ledger: Any) -> dict[str, Any]:
    profile = ledger.get_player_profile() or {}
    answers = ledger.load_intake_answers()
    onboarding_completed = _profile_has_completion_evidence(ledger)
    profile_fields = {}
    for label, key in _PROFILE_FIELDS:
        if key in answers:
            answer = answers[key]
            value = answer.get("value")
            if (
                answer.get("prefilled")
                and not onboarding_completed
                and _is_storage_default(key, value)
            ):
                value = None
        else:
            value = profile.get(key)
            if not onboarding_completed and _is_storage_default(key, value):
                value = None
        profile_fields[label] = _not_set(value)
    return {
        "status": "ok",
        "profile": profile_fields,
    }


def _read_weight_trend(ledger: Any) -> dict[str, Any]:
    ledger_id = ledger.ledger_id
    as_of = player_local_date(ledger, ledger_id)
    trend = get_weight_trend(
        None,
        WeightTrendQuery(ledger_id=ledger_id, weeks=8, as_of=as_of),
        ledger=ledger,
    )
    profile = ledger.get_player_profile() or {}
    return {
        "status": "ok",
        "weight_context": render_player_weight_context(
            trend, profile.get("target_weight_kg"), as_of=as_of
        ),
    }


def _read_player_injuries(ledger: Any) -> dict[str, Any]:
    records = []
    for record in ledger.list_injury_records():
        rendered = render_public_injury_record(record)
        rendered.pop("id", None)
        rendered["clearances"] = [
            {
                key: clearance[key]
                for key in _INJURY_CLEARANCE_TOOL_FIELDS
                if key in clearance
            }
            for clearance in ledger.list_exercise_clearances(str(record["id"]))
        ]
        records.append(rendered)
    return {"status": "ok", "injuries": records}


def _read_assistant_preferences(ledger: Any) -> dict[str, Any]:
    return {
        "status": "ok",
        "preferences": [
            preference["text"] for preference in ledger.list_assistant_preferences()
        ],
    }


def _read_player_nutrition(ledger: Any) -> dict[str, Any]:
    """Returns a privacy-safe projection of active targets and recent adherence."""
    today = player_local_date(ledger, ledger.ledger_id)
    return assistant_projection(ledger, today)


def _read_active_program(ledger: Any, args: ActiveProgramArgs | None = None) -> dict[str, Any]:
    program = ledger.get_active_program()
    if program is None:
        return {"status": "not_set", "active_program": "not set"}
    from core.weak_points import WEAK_POINT_MUSCLES
    from agent.ProgramState import program_exercise_working_sets

    all_days = list(getattr(program, "days", ()) or ())
    selected_name = args.day_name.strip().casefold() if args and args.day_name else None
    if selected_name:
        matching = [day for day in all_days if str(getattr(day, "day_name", "")).casefold() == selected_name]
        if not matching:
            return {"status": "not_found", "day_names": [str(getattr(day, "day_name", "not set")) for day in all_days]}
        all_days = matching
    exercise_ids = sorted({
        str(getattr(exercise, "exercise_id", ""))
        for day in all_days for exercise in (getattr(day, "exercises", ()) or ())
        if getattr(exercise, "exercise_id", None)
    })
    targets = ledger.volume_review_exercise_targets(exercise_ids)
    summary: dict[str, int] = {muscle: 0 for muscle in WEAK_POINT_MUSCLES}
    other_muscles: dict[str, int] = {}
    days = []
    for day in all_days:
        exercises = []
        for exercise in getattr(day, "exercises", ()) or ():
            sets = program_exercise_working_sets(exercise)
            muscle = targets.get(str(getattr(exercise, "exercise_id", "")))
            if muscle:
                normalized_muscle = str(muscle).strip().casefold()
                matching_groups = [
                    group for group, names in FOCUS_REVIEW_MUSCLES.items()
                    if normalized_muscle in {name.casefold() for name in names}
                ]
                if matching_groups:
                    for group in matching_groups:
                        summary[group] += sets
                else:
                    other_muscles[str(muscle).strip()] = other_muscles.get(str(muscle).strip(), 0) + sets
            name = str(getattr(exercise, "exercise_name", "not set"))
            reps_min = getattr(exercise, "target_reps_min", None)
            reps_max = getattr(exercise, "target_reps_max", None)
            rir = 10 - float(getattr(exercise, "target_rpe", 8.5))
            rest = getattr(exercise, "rest_seconds", None)
            groups = getattr(exercise, "set_groups", ()) or ()
            flat = (
                sets, reps_min, reps_max, rir,
                getattr(exercise, "load", None),
                False,
            )
            groups_differ = bool(groups) and any(
                (group.sets, group.reps_min, group.reps_max, group.target_rir,
                 group.load, group.amrap_last_set) != flat
                for group in groups
            )
            if selected_name:
                row = {
                    "name": name, "sets": sets, "reps_min": reps_min,
                    "reps_max": reps_max, "rir": rir, "muscle": muscle or "not set",
                }
                row["rest_seconds"] = rest if rest is not None else "not set"
                if groups_differ:
                    row["set_groups"] = [
                        {
                            "sets": group.sets, "reps_min": group.reps_min,
                            "reps_max": group.reps_max, "rir": group.target_rir,
                            **({"load": group.load.model_dump()} if group.load else {}),
                            **({"amrap_last_set": True} if group.amrap_last_set else {}),
                        }
                        for group in groups
                    ]
            else:
                row = {"n": name, "s": sets, "r": reps_min, "R": reps_max, "m": muscle or "not set"}
                if groups_differ:
                    row["g"] = [
                        {
                            "s": group.sets, "r": group.reps_min, "R": group.reps_max,
                            "i": group.target_rir,
                            **({"l": {"k": group.load.kind, "v": group.load.value}} if group.load else {}),
                            **({"a": True} if group.amrap_last_set else {}),
                        }
                        for group in groups
                    ]
            exercises.append(row)
        day_name = str(getattr(day, "day_name", "not set"))
        days.append(
            {"day": day_name, "exercises": exercises}
            if selected_name else {"d": day_name, "e": exercises}
        )
    return {
        "status": "ok", "f": getattr(program, "weekly_frequency", "not set"),
        "split": _not_set(getattr(program, "split_type", None)), "days": days,
        **({} if selected_name else {
            "weekly_sets_by_muscle": summary, "other_muscles": other_muscles,
            "message": "Weak point groups can overlap. Request a day_name scope for RIR and rest.",
        }),
    }


def _read_program_rationale(ledger: Any, args: ProgramRationaleArgs) -> dict[str, Any]:
    program = ledger.get_active_program()
    if program is None:
        return {"status": "not_set", "reason_available": False, "source": "none"}
    from agent.program_rationale_reader import read_program_rationale
    return read_program_rationale(program, args)


PLAYER_READ_TOOL_REGISTRY: tuple[PlayerReadTool, ...] = (
    PlayerReadTool(
        name="get_player_profile",
        description=(
            "Read the current player's saved profile facts. Use this before answering "
            "questions about the player's own profile. Empty fields are returned as 'not set'."
        ),
        args_schema=EmptyToolArgs,
        reader=_read_profile,
        status_en="Checking your profile…",
        status_ar="ببص على بياناتك…",
    ),
    PlayerReadTool(
        name="get_active_program",
        description=(
            "Read the current player's active Training program, including its training days "
            "and weekly sets by muscle. Compact keys: d=day, e=exercises, n=name, s=sets, "
            "r/R=reps min/max, m=muscle, g=set groups. Request day_name for full RIR/rest. "
            "Weak point groups can overlap. Use this before program questions."
        ),
        args_schema=ActiveProgramArgs,
        reader=_read_active_program,
        args_reader=lambda ledger, args: _read_active_program(ledger, args),
        status_en="Checking your Training program…",
        status_ar="ببص على برنامجك التدريبي…",
    ),
    PlayerReadTool(
        name="get_program_rationale",
        description=(
            "Read recorded reasons for the active Training program. Use this for every why-question "
            "about the Split, day order, exercises or prescriptions. Scope by day_name/day_order or "
            "exercise_name/exercise_id and week_order; use page/next_page to read large results. "
            "If reason_available is false, no recorded generator reason exists."
        ),
        args_schema=ProgramRationaleArgs,
        reader=lambda ledger, args=None: _read_program_rationale(ledger, args or ProgramRationaleArgs()),
        args_reader=lambda ledger, args: _read_program_rationale(ledger, args),
        status_en="Checking why your program is arranged this way…",
        status_ar="ببص على أسباب ترتيب برنامجك…",
    ),
    PlayerReadTool(
        name="get_player_weight_trend",
        description=(
            "Read the current player's dated body-weight trend and computed changes. Use this "
            "before answering questions about weight changes or progress toward a target weight."
        ),
        args_schema=EmptyToolArgs,
        reader=_read_weight_trend,
        status_en="Checking your weight trend…",
        status_ar="ببص على تغيّر وزنك…",
    ),
    PlayerReadTool(
        name="get_player_nutrition",
        description=(
            "Read the current player's active Nutrition targets, author, Nutrition goal, pace, "
            "last-14-day adherence counts, and today's Cardio calories and calorie adjustment. "
            "This is read-only; direct target changes "
            "to the Nutrition tab."
        ),
        args_schema=EmptyToolArgs,
        reader=_read_player_nutrition,
        status_en="Checking your Nutrition targets…",
        status_ar="ببص على أهداف التغذية بتاعتك…",
    ),
    PlayerReadTool(
        name="get_player_injuries",
        description=(
            "Read the current player's injury records, body areas, descriptions, and statuses. "
            "Use this before answering questions about injuries or physician follow-up."
        ),
        args_schema=EmptyToolArgs,
        reader=_read_player_injuries,
        status_en="Checking your injury records…",
        status_ar="ببص على سجلات إصاباتك…",
    ),
    PlayerReadTool(
        name="get_assistant_preferences",
        description=(
            "Read preferences the current player explicitly asked the assistant to remember. "
            "Use when answering how the player likes to train. Do not infer or write preferences."
        ),
        args_schema=EmptyToolArgs,
        reader=_read_assistant_preferences,
        status_en="Checking your saved preferences…",
        status_ar="ببص على تفضيلاتك المحفوظة…",
    ),
)


def _encode_tool_result(tool_result: Any) -> str:
    rendered = tool_result if isinstance(tool_result, str) else json.dumps(
        tool_result, ensure_ascii=False, separators=(",", ":"), allow_nan=False
    )
    if len(rendered.encode("utf-8")) <= MAX_TOOL_RESULT_BYTES:
        return rendered
    if isinstance(tool_result, dict) and "weekly_sets_by_muscle" in tool_result:
        compact = {
            "status": "summary_only",
            "weekly_sets_by_muscle": tool_result["weekly_sets_by_muscle"],
            "day_names": [day.get("d", "") for day in tool_result.get("days", [])],
            "message": "Ask for a day_name scope to read a full day.",
        }
        compact_rendered = json.dumps(compact, ensure_ascii=False, separators=(",", ":"))
        if len(compact_rendered.encode("utf-8")) <= MAX_TOOL_RESULT_BYTES:
            return compact_rendered
    # Keep the tool message valid JSON and bounded. The assistant can explain
    # that this result was too large and ask the player to narrow the question.
    return json.dumps(
        {
            "status": "truncated",
            "message": "The result exceeded the 4 KB limit; ask a narrower question.",
        },
        ensure_ascii=False,
        separators=(",", ":"),
    )


def _unavailable_result() -> str:
    return '{"status":"unavailable"}'


def cap_tool_results_for_prompt(
    prompt_messages: Sequence[Any], tool_messages: Sequence[ToolMessage]
) -> list[ToolMessage]:
    """Keeps this round's results within the prompt ceiling and reserves later-round room."""
    prompt_bytes = sum(
        len(str(message.content).encode("utf-8")) for message in prompt_messages
    )
    result_budget = HOSTED_PROMPT_MAX_BYTES - HOSTED_PROMPT_TOOL_RESULT_RESERVE_BYTES
    capped_messages = []
    for message in tool_messages:
        content = str(message.content)
        content_bytes = len(content.encode("utf-8"))
        if prompt_bytes + content_bytes > result_budget:
            content = _TRUNCATED_PROMPT_RESULT
            content_bytes = len(content.encode("utf-8"))
        if prompt_bytes + content_bytes > HOSTED_PROMPT_MAX_BYTES:
            content = "{}"
            content_bytes = len(content.encode("utf-8"))
        if prompt_bytes + content_bytes > HOSTED_PROMPT_MAX_BYTES:
            content = ""
            content_bytes = 0
        capped_messages.append(message.model_copy(update={"content": content}))
        prompt_bytes += content_bytes
    return capped_messages


def build_player_read_tools(ledger: Any) -> tuple[list[StructuredTool], dict[str, PlayerReadTool]]:
    """Builds this turn's tools; their readers close over only its own ledger."""
    tools: list[StructuredTool] = []
    definitions = {definition.name: definition for definition in PLAYER_READ_TOOL_REGISTRY}
    for definition in PLAYER_READ_TOOL_REGISTRY:
        if definition.args_reader is not None:
            def reader(_definition=definition, **kwargs: Any) -> str:
                args = _definition.args_schema(**kwargs)
                return _encode_tool_result(_definition.args_reader(ledger, args))
        else:
            def reader(_definition=definition) -> str:
                return _encode_tool_result(_definition.reader(ledger))

        tools.append(
            StructuredTool.from_function(
                func=reader,
                name=definition.name,
                description=definition.description,
                args_schema=definition.args_schema,
            )
        )
    return tools, definitions


def run_player_tool_calls(
    tool_calls: Sequence[dict[str, Any]],
    *,
    tools: Sequence[StructuredTool],
    definitions: dict[str, PlayerReadTool],
    language: str,
    status_callback: Callable[[str], None] | None = None,
) -> tuple[list[ToolMessage], list[tuple[str, float]]]:
    """Runs one parallel tool round; reader failures become unavailable results."""
    tools_by_name = {tool.name: tool for tool in tools}
    futures = []
    started_at = []
    names = []
    executor = ThreadPoolExecutor(max_workers=max(1, min(len(tool_calls), 4)))
    try:
        for index, call in enumerate(tool_calls):
            name = str(call.get("name", ""))
            definition = definitions.get(name)
            tool = tools_by_name.get(name)
            tool_call_id = str(call.get("id") or f"tool-call-{index + 1}")
            names.append((name, definition, tool_call_id))
            if definition is None or tool is None:
                futures.append(None)
                started_at.append(time.perf_counter())
                continue
            if status_callback is not None:
                status_callback(definition.status_ar if language == "ar" else definition.status_en)
            args = call.get("args")
            args = args if isinstance(args, dict) else {}
            started_at.append(time.perf_counter())
            futures.append(executor.submit(tool.invoke, args))

        messages: list[ToolMessage] = []
        telemetry: list[tuple[str, float]] = []
        for (name, definition, call_id), future, started in zip(names, futures, started_at):
            elapsed_ms = 0.0
            if definition is None or future is None:
                tool_result = _unavailable_result()
            else:
                try:
                    remaining_seconds = max(
                        0.0,
                        definition.timeout_seconds - (time.perf_counter() - started),
                    )
                    tool_result = str(future.result(timeout=remaining_seconds))
                except TimeoutError:
                    tool_result = _unavailable_result()
                except Exception:
                    logger.warning("Player read tool %s failed; returning unavailable", name)
                    tool_result = _unavailable_result()
                elapsed_ms = (time.perf_counter() - started) * 1000.0
            if len(tool_result.encode("utf-8")) > MAX_TOOL_RESULT_BYTES:
                tool_result = _encode_tool_result(tool_result)
            messages.append(
                ToolMessage(content=tool_result, tool_call_id=call_id, name=name or "unavailable")
            )
            if definition is not None:
                telemetry.append((name, elapsed_ms))
        return messages, telemetry
    finally:
        executor.shutdown(wait=False, cancel_futures=True)
