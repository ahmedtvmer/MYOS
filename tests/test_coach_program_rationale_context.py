import json
from types import SimpleNamespace

from service.coach_ai import coach_program_rationale_context
from agent.program_rationale_reader import read_program_rationale


def test_five_day_program_context_keeps_selection_reason_for_every_exercise():
    days = []
    rationale_days = []
    for day_order in range(1, 6):
        exercises = [
            {
                "exercise_id": f"d{day_order}-e{index}",
                "exercise_name": f"Exercise {day_order}-{index}",
                "note": None,
            }
            for index in range(1, 7)
        ]
        days.append({
            "day_order": day_order, "day_name": f"Day {day_order}", "exercises": exercises
        })
        rationale_days.append({
            "day_order": day_order,
            "day_order_reason": {
                "code": "day_order.template", "params": {"order": day_order}
            },
            "exercises": [
                {
                    "position": index,
                        "exercise_id": exercise["exercise_id"],
                    "rationale": {
                        "selection": {
                            "code": "selection.staple",
                            "params": {"slot": "horizontal_press", "rank": index},
                        },
                        "position": {
                            "code": "position.heavy_compound",
                            "params": {"slot": "horizontal_press"},
                        },
                        "prescription": {
                            "sets": {"code": "sets.coach_dose", "params": {"count": 4}},
                            "reps": {"code": "reps.movement_class", "params": {"rep_min": 6, "rep_max": 8}},
                            "rir": {"code": "rir.experience_level", "params": {"target_rir": 2}},
                        },
                    },
                    "changes": [{"code": "change.substitution", "params": {"from": "old"}}],
                }
                for index, exercise in enumerate(exercises, 1)
            ],
        })
    program = SimpleNamespace(
        days=days,
        weeks=[],
        split_type="Upper / Lower",
        program_rationale={
            "split": {"code": "split.frequency_default", "params": {"frequency": 5}},
            "day_order": {
                "code": "day_order.template", "params": {"split": "Upper / Lower"}
            },
            "days": rationale_days,
        },
    )

    context = coach_program_rationale_context(program)

    assert context["reason_available"] is True
    assert len(context["days"]) == 5
    assert sum(len(day["exercises"]) for day in context["days"]) == 30
    assert all(
        (
            exercise["selection"]["code"] == "selection.staple"
            and exercise["position"]["code"] == "position.heavy_compound"
        )
        if isinstance(exercise, dict)
        else exercise[2:] == ["selection.staple", "position.heavy_compound"]
        for day in context["days"]
        for exercise in day["exercises"]
    )
    assert len(json.dumps(context, ensure_ascii=False, separators=(",", ":")).encode()) <= 4096


def test_occurrence_scope_distinguishes_duplicate_exercise_reasons():
    program = SimpleNamespace(
        days=[SimpleNamespace(
            week_order=1,
            day_order=1,
            day_name="Day 1",
            exercises=[
                SimpleNamespace(exercise_id="repeat", exercise_name="Repeat"),
                SimpleNamespace(exercise_id="repeat", exercise_name="Repeat"),
            ],
        )],
        weeks=[],
        program_rationale={"days": [{
            "week_order": 1,
            "day_order": 1,
            "exercises": [
                {"position": 1, "exercise_id": "repeat", "rationale": {"selection": {"code": "first"}}},
                {"position": 2, "exercise_id": "repeat", "rationale": {"selection": {"code": "second"}}},
            ],
        }]},
    )

    result = read_program_rationale(program, {
        "week_order": 1, "day_order": 1, "exercise_id": "repeat", "position": 2,
    })

    assert result["days"][0]["exercises"][0]["selection"]["code"] == "second"


def test_changes_only_rationale_does_not_claim_coach_generated_source():
    program = SimpleNamespace(
        published_by_coach_account_id="coach-1",
        source_template_id=None,
        days=[],
        weeks=[],
        program_rationale={
            "generator_reasons_available": False,
            "days": [],
        },
    )

    assert read_program_rationale(program)["source"] == "coach_authored"
