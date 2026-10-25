from agent.ProgramState import (
    PersistedProgramDaySchema,
    PersistedProgramExerciseSchema,
    PersistedProgramSchema,
    PersistedProgramWeekSchema,
)
from service.program_analytics import ProgramAnalyticsActor
from service.program_edit import (
    ProgramEdit,
    ProgramEditExercise,
    edit_active_program_day,
)

TEST_PLAYER_ID = "00000000-0000-4000-8000-000000000001"


def test_program_edit_targets_week_and_day_coordinates(fresh_store):
    db = fresh_store
    ledger = db.ledger
    catalog_exercises = db.catalog_conn.execute(
        "SELECT id, name FROM exercises ORDER BY id LIMIT 2"
    ).fetchall()
    first_id, first_name = str(catalog_exercises[0][0]), str(catalog_exercises[0][1])
    second_id, second_name = str(catalog_exercises[1][0]), str(catalog_exercises[1][1])
    first_exercise = PersistedProgramExerciseSchema(
        exercise_id=first_id,
        exercise_name=first_name,
        target_sets=3,
        target_reps_min=5,
        target_reps_max=8,
    )
    second_exercise = PersistedProgramExerciseSchema(
        exercise_id=second_id,
        exercise_name=second_name,
        target_sets=4,
        target_reps_min=5,
        target_reps_max=8,
    )
    first_day = PersistedProgramDaySchema(
        day_name="Full A",
        day_order=1,
        week_order=1,
        exercises=[first_exercise],
    )
    second_day = PersistedProgramDaySchema(
        day_name="Full A",
        day_order=1,
        week_order=2,
        exercises=[second_exercise],
    )
    ledger.save_training_program(
        PersistedProgramSchema(
            program_name="Two-week plan",
            split_type="Full Body",
            weekly_frequency=1,
            days=[first_day, second_day],
            weeks=[
                PersistedProgramWeekSchema(
                    week_name="Base", week_order=1, days=[first_day]
                ),
                PersistedProgramWeekSchema(
                    week_name="Build", week_order=2, days=[second_day]
                ),
            ],
        ).model_dump()
    )
    active = ledger.get_active_program()
    ledger.log_workout_session(
        "program-edit-cursor-seed",
        "2026-10-01",
        "Full A",
        "2026-10-01T10:00:00+00:00",
        "2026-10-01T11:00:00+00:00",
        program_version=active.version,
        program_week_order=1,
        program_day_order=1,
    )

    edit_active_program_day(
        db,
        ledger,
        ProgramEdit(
            day_name="Full A",
            expected_active_version=active.version,
            exercises=[ProgramEditExercise(0, second_id, 2)],
            player_account_id=TEST_PLAYER_ID,
            actor=ProgramAnalyticsActor(TEST_PLAYER_ID, "player"),
            week_order=2,
            day_order=1,
        ),
    )

    updated = ledger.get_active_program()
    assert updated.weeks[0].days[0].exercises[0].exercise_id == first_id
    assert updated.weeks[1].days[0].exercises[0].target_sets == 2
    position = ledger.get_program_position(updated)
    assert (position.current_week, position.next_day_order) == (2, 1)


def test_program_edit_records_trim_reorder_removal_and_keeps_reasons(fresh_store):
    db = fresh_store
    ledger = db.ledger
    rows = db.catalog_conn.execute("SELECT id, name FROM exercises ORDER BY id LIMIT 4").fetchall()
    exercises = [PersistedProgramExerciseSchema(exercise_id=str(row[0]), exercise_name=str(row[1]), target_sets=3, target_reps_min=8, target_reps_max=12) for row in rows]
    day = PersistedProgramDaySchema(day_name="Edit", day_order=1, exercises=exercises)
    rationale = {"split": {"code": "split.frequency_default", "params": {}}, "day_order": {"code": "day_order.template", "params": {}}, "days": [{"day_order": 1, "exercises": [
        {"position": i + 1, "exercise_id": str(row[0]), "rationale": {"selection": {"code": f"selection.generator_{i}"}}} for i, row in enumerate(rows)
    ]}]}
    program = PersistedProgramSchema(program_name="Edit", split_type="Full Body", weekly_frequency=1, days=[day], program_rationale=rationale)
    ledger.save_training_program(program.model_dump())
    active = ledger.get_active_program()
    result = edit_active_program_day(db, ledger, ProgramEdit(day_name="Edit", expected_active_version=active.version,
        exercises=[ProgramEditExercise(0, str(rows[0][0]), 3), ProgramEditExercise(2, str(rows[2][0]), 2), ProgramEditExercise(3, str(rows[3][0]), 3)],
        player_account_id=TEST_PLAYER_ID, actor=ProgramAnalyticsActor(TEST_PLAYER_ID, "player"), day_order=1))
    assert result["version"] == 2
    saved = ledger.get_active_program().program_rationale["days"][0]
    by_id = {entry["exercise_id"]: entry for entry in saved["exercises"]}
    assert by_id[str(rows[2][0])]["rationale"]["selection"]["code"] == "selection.generator_2"
    assert by_id[str(rows[2][0])]["changes"][0]["code"] == "change.program_edit_trimmed"
    assert by_id[str(rows[2][0])]["changes"][0]["params"] == {"from_sets": 3, "to_sets": 2}
    assert by_id[str(rows[0][0])]["rationale"]["selection"]["code"] == "selection.generator_0"
    assert by_id[str(rows[0][0])].get("changes", []) == []
    assert by_id[str(rows[3][0])]["changes"][0]["code"] == "change.program_edit_reordered"
    assert saved["removed"][0]["exercise_id"] == str(rows[1][0])
    assert saved["removed"][0]["code"] == "change.program_edit_removed"
