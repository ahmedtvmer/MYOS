from types import SimpleNamespace
from copy import deepcopy

from service.program_rationale_changes import carry_program_rationale
from service.coach_program_drafts import _carry_generated_rationale_through_edit


def test_change_carry_over_keeps_duplicate_occurrences_and_isolates_days():
    old = SimpleNamespace(program_rationale={"days": [
        {"week_order": 1, "day_order": 1, "exercises": [
            {"position": 1, "exercise_id": "repeat", "rationale": {"selection": {"code": "first"}}},
            {"position": 2, "exercise_id": "repeat", "rationale": {"selection": {"code": "second"}}},
        ]},
        {"week_order": 2, "day_order": 1, "exercises": [
            {"position": 1, "exercise_id": "repeat", "rationale": {"selection": {"code": "other_week"}}},
        ]},
    ]})
    data = {"days": [
        {"week_order": 1, "day_order": 1, "exercises": [
            {"exercise_id": "repeat"}, {"exercise_id": "repeat"},
        ]},
        {"week_order": 2, "day_order": 1, "exercises": [{"exercise_id": "repeat"}]},
    ]}

    carry_program_rationale(old, data, occurrence_mappings=[
        {"week_order": 1, "day_order": 1, "from_position": 1, "to_position": 1,
         "changes": [{"code": "change.substitution"}]},
        {"week_order": 1, "day_order": 1, "from_position": 2, "to_position": 2},
        {"week_order": 2, "day_order": 1, "from_position": 1, "to_position": 1},
    ])

    rationale = data["program_rationale"]
    first, second = rationale["days"]
    assert [item["rationale"]["selection"]["code"] for item in first["exercises"]] == ["first", "second"]
    assert [item.get("changes", []) for item in first["exercises"]] == [[{"code": "change.substitution", "params": {}, "at": first["exercises"][0]["changes"][0]["at"]}], []]
    assert second["exercises"][0]["rationale"]["selection"]["code"] == "other_week"


def test_legacy_change_records_without_generator_reasons():
    old = SimpleNamespace(program_rationale=None)
    data = {"days": [{"day_order": 1, "exercises": [{"exercise_id": "new"}]}]}
    carry_program_rationale(old, data, occurrence_mappings=[
        {"week_order": 1, "day_order": 1, "from_position": None, "to_position": 1,
         "changes": [{"code": "change.substitution"}]},
    ])

    rationale = data["program_rationale"]
    assert rationale["generator_reasons_available"] is False
    assert rationale["days"][0]["exercises"][0]["changes"][0]["code"] == "change.substitution"


def test_occurrence_mappings_keep_duplicate_reasons_through_reorder_and_isolate_days():
    old = SimpleNamespace(program_rationale={"days": [
        {"week_order": 1, "day_order": 1, "exercises": [
            {"position": 1, "exercise_id": "repeat", "rationale": {"selection": {"code": "first"}}},
            {"position": 2, "exercise_id": "repeat", "rationale": {"selection": {"code": "second"}}},
        ]},
        {"week_order": 1, "day_order": 2, "exercises": [
            {"position": 1, "exercise_id": "repeat", "rationale": {"selection": {"code": "day_two"}}},
        ]},
    ]})
    result = {"days": [
        {"week_order": 1, "day_order": 1, "exercises": [
            {"exercise_id": "repeat"}, {"exercise_id": "repeat"},
        ]},
        {"week_order": 1, "day_order": 2, "exercises": [{"exercise_id": "repeat"}]},
    ]}
    mappings = [
        {"week_order": 1, "day_order": 1, "from_position": 2, "to_position": 1},
        {"week_order": 1, "day_order": 1, "from_position": 1, "to_position": 2},
        {"week_order": 1, "day_order": 2, "from_position": 1, "to_position": 1},
    ]

    carry_program_rationale(old, result, occurrence_mappings=mappings)

    day_one, day_two = result["program_rationale"]["days"]
    assert [e["rationale"]["selection"]["code"] for e in day_one["exercises"]] == ["second", "first"]
    assert day_two["exercises"][0]["rationale"]["selection"]["code"] == "day_two"


def test_occurrence_mappings_preserve_each_week_in_multiweek_program():
    old = SimpleNamespace(program_rationale={"days": [
        {"week_order": week, "day_order": 1, "exercises": [
            {"position": 1, "exercise_id": f"lift-{week}", "rationale": {"selection": {"code": f"week-{week}"}}},
        ]} for week in (1, 2)
    ]})
    result = {"days": [
        {"week_order": week, "day_order": 1, "exercises": [{"exercise_id": f"lift-{week}"}]}
        for week in (1, 2)
    ]}
    mappings = [
        {"week_order": week, "day_order": 1, "from_position": 1, "to_position": 1}
        for week in (1, 2)
    ]

    carry_program_rationale(old, result, occurrence_mappings=mappings)

    assert [d["exercises"][0]["rationale"]["selection"]["code"] for d in result["program_rationale"]["days"]] == ["week-1", "week-2"]


def test_multiweek_coach_draft_carries_reasons_by_week_and_day():
    draft = {
        "program_name": "Two weeks",
        "weeks": [
            {"week_order": 1, "days": [{"day_order": 1, "day_name": "A", "exercises": [{"exercise_id": "same", "notes": None}]}]},
            {"week_order": 2, "days": [{"day_order": 1, "day_name": "A", "exercises": [{"exercise_id": "same", "notes": None}]}]},
        ],
        "program_rationale": {"days": [
            {"week_order": 1, "day_order": 1, "exercises": [{"position": 1, "exercise_id": "same", "rationale": {"selection": {"code": "reason_week_1"}}}]},
            {"week_order": 2, "day_order": 1, "exercises": [{"position": 1, "exercise_id": "same", "rationale": {"selection": {"code": "reason_week_2"}}}]},
        ]},
    }
    updated = deepcopy(draft)
    updated["weeks"][1]["days"][0]["exercises"][0]["notes"] = "Coach edit"

    saved = _carry_generated_rationale_through_edit(draft, updated)

    assert [day["week_order"] for day in saved["program_rationale"]["days"]] == [1, 2]
    assert [day["exercises"][0]["rationale"]["selection"]["code"]
            for day in saved["program_rationale"]["days"]] == ["reason_week_1", "reason_week_2"]
    assert saved["program_rationale"]["days"][1]["exercises"][0]["changes"][0]["code"] == "change.coach_edit"


def test_legacy_coach_draft_records_edit_without_generator_reasons():
    draft = {
        "weeks": [{"week_order": 1, "days": [{
            "day_order": 1,
            "exercises": [{"exercise_id": "lift", "notes": None}],
        }]}],
    }
    updated = deepcopy(draft)
    updated["weeks"][0]["days"][0]["exercises"][0]["notes"] = "Coach note"

    saved = _carry_generated_rationale_through_edit(draft, updated)

    rationale = saved["program_rationale"]
    assert rationale["generator_reasons_available"] is False
    assert rationale["days"][0]["exercises"][0]["changes"][0]["code"] == "change.coach_edit"


def test_coach_draft_reorder_keeps_duplicate_id_reasons_with_occurrences():
    draft = {
        "weeks": [{"week_order": 1, "days": [{"day_order": 1, "exercises": [
            {"exercise_id": "repeat", "target_sets": 2},
            {"exercise_id": "repeat", "target_sets": 4},
        ]}]}],
        "program_rationale": {"days": [{
            "week_order": 1,
            "day_order": 1,
            "exercises": [
                {"position": 1, "exercise_id": "repeat", "rationale": {"selection": {"code": "two_sets"}}},
                {"position": 2, "exercise_id": "repeat", "rationale": {"selection": {"code": "four_sets"}}},
            ],
        }]},
    }
    updated = deepcopy(draft)
    updated["weeks"][0]["days"][0]["exercises"] = [
        updated["weeks"][0]["days"][0]["exercises"][1],
        updated["weeks"][0]["days"][0]["exercises"][0],
    ]

    saved = _carry_generated_rationale_through_edit(draft, updated)

    assert [exercise["rationale"]["selection"]["code"]
            for exercise in saved["program_rationale"]["days"][0]["exercises"]] == [
                "four_sets", "two_sets",
            ]
