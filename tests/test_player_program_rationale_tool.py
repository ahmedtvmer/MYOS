import json
from types import SimpleNamespace

from agent.player_tools import build_player_read_tools


def _program(*, rationale=None, authored=False):
    exercises = [
        SimpleNamespace(
            exercise_id=f"id-{index}", exercise_name=f"Lift {index}", note="Coach note"
        )
        for index in range(1, 5)
    ]
    day = SimpleNamespace(day_name="Push", day_order=1, exercises=exercises,
                          warmup_exercises=[], cardio=None)
    return SimpleNamespace(
        program_name="Plan", weekly_frequency=1, split_type="Full Body",
        days=[day], weeks=[], version=2, program_rationale=rationale,
        published_by_coach_account_id="coach" if authored else None,
        source_template_id=None,
    )


def _reader(program):
    tools, _ = build_player_read_tools(SimpleNamespace(get_active_program=lambda: program))
    return next(tool for tool in tools if tool.name == "get_program_rationale")


def test_program_rationale_reader_scopes_by_day_or_exercise_and_keeps_unknown_codes():
    program = _program(rationale={
        "split": {"code": "split.new_code", "params": {}},
        "day_order": {"code": "day_order.new_code", "params": {}},
        "days": [{"day_order": 1, "exercises": [
            {"position": 1, "exercise_id": "id-1", "selection": {"code": "new.selection", "params": {}}},
            {"position": 2, "exercise_id": "id-2", "selection": {"code": "selection.staple", "params": {}}},
        ]}],
    })
    reader = _reader(program)

    day = json.loads(reader.invoke({"day_name": "Push"}))
    exercise = json.loads(reader.invoke({"exercise_id": "id-2", "day_name": "Push"}))

    assert day["days"][0]["day"] == "Push"
    assert len(day["days"][0]["exercises"]) == 4
    assert exercise["days"][0]["exercises"][0]["exercise_id"] == "id-2"
    assert exercise["days"][0]["exercises"][0]["rationale"]["selection"]["code"] == "selection.staple"
    assert day["split"]["code"] == "split.new_code"


def test_program_rationale_reader_reports_legacy_and_coach_authored_source_and_note():
    legacy = json.loads(_reader(_program()).invoke({}))
    authored = json.loads(_reader(_program(authored=True)).invoke({"exercise_id": "id-1"}))

    assert legacy["reason_available"] is False
    assert authored["reason_available"] is False
    assert authored["source"] == "coach_authored"
    assert authored["days"][0]["exercises"][0]["coach_note"] == "Coach note"


def test_program_rationale_reader_never_exceeds_4_kb():
    rationale = {"split": {"code": "split.test", "params": {}}, "days": [
        {"day_order": 1, "exercises": [{"position": i, "exercise_id": f"id-{i}", "payload": "x" * 1200} for i in range(4)]}
    ]}
    result = _reader(_program(rationale=rationale)).invoke({})
    assert len(result.encode("utf-8")) <= 4096
    assert json.loads(result)["status"] == "summary"
