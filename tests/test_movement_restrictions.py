import pytest

from core.movement_restrictions import (
    MOVEMENT_RESTRICTIONS,
    is_movement_restricted,
    validate_movement_restrictions,
)
from core.movement_restriction_suggestions import suggest_movement_restrictions


def test_restriction_vocabulary_is_fixed_and_validated():
    assert "Knee flexion" in MOVEMENT_RESTRICTIONS
    assert validate_movement_restrictions(["Knee flexion", "Hip adduction"]) == [
        "Knee flexion", "Hip adduction"
    ]


def test_curated_primary_and_secondary_actions_and_uncurated_slot_are_excluded():
    restrictions = ["Knee flexion", "Hip adduction"]
    assert is_movement_restricted(
        {"primary_action": "Knee Flexion", "secondary_actions": []}, "ham_curl", restrictions
    )
    assert is_movement_restricted(
        {"primary_action": "Hip Extension", "secondary_actions": ["Hip Adduction"]},
        "glute_thrust", restrictions,
    )
    assert is_movement_restricted(
        {"primary_action": None, "secondary_actions": []}, "adductors", restrictions
    )
    assert not is_movement_restricted(
        {"primary_action": "Hip Extension", "secondary_actions": []}, "glute_thrust", restrictions
    )


def test_matcher_splits_pipe_joined_secondary_actions():
    assert is_movement_restricted(
        {"primary_action": "Elbow Flexion", "secondary_actions": "Knee Flexion|Hip Adduction"},
        "",
        ["Knee flexion"],
    )


def test_slotless_candidates_are_classified_by_signature_and_generation_name_rules():
    assert is_movement_restricted(
        {
            "name": "Dumbbell Shoulder Press",
            "primary_action": "Shoulder Flexion",
            "primary_muscle": "Front Delts",
            "secondary_actions": [],
        },
        "",
        ["Overhead pressing"],
    )


def test_restriction_matching_checks_stored_and_unique_candidate_classification():
    # Ranking words and overlapping signatures must not invent a slot.
    assert not is_movement_restricted(
        {"name": "Seated Row (Machine)", "primary_action": "Elbow Flexion",
         "primary_muscle": "Upper Back", "secondary_actions": []}, "", ["Knee flexion"]
    )
    assert not is_movement_restricted(
        {"name": "Single-Arm Pushdown (Cable)", "primary_action": "Elbow Extension",
         "primary_muscle": "Triceps", "secondary_actions": []}, "", ["Overhead pressing"]
    )
    shoulder_press = {"name": "Dumbbell Shoulder Press", "primary_action": "Shoulder Flexion",
                      "primary_muscle": "Front Delts", "secondary_actions": []}
    assert is_movement_restricted(shoulder_press, "flat_press", ["Overhead pressing"])


def test_real_catalog_classification_does_not_use_ranking_name_patterns(fresh_store):
    seated_row = fresh_store.get_exercise_library_entry("1350")
    pushdown = fresh_store.get_exercise_library_entry("1723")
    dumbbell_press = fresh_store.get_exercise_library_entry("360")
    assert not is_movement_restricted(seated_row, "", ["Knee flexion"])
    assert not is_movement_restricted(pushdown, "", ["Overhead pressing"])
    assert is_movement_restricted(dumbbell_press, "flat_press", ["Overhead pressing"])


def test_real_catalog_overhead_extensions_are_restricted_but_pushdowns_are_not(fresh_store):
    for exercise_id in ("194", "92", "2188", "453"):
        candidate = fresh_store.get_exercise_library_entry(exercise_id)
        assert is_movement_restricted(candidate, "", ["Overhead pressing"]), exercise_id
        assert is_movement_restricted(candidate, "flat_press", ["Overhead pressing"]), exercise_id
    pushdown = fresh_store.get_exercise_library_entry("1723")
    assert not is_movement_restricted(pushdown, "", ["Overhead pressing"])


def test_overhead_term_catalog_rows_are_restricted_by_their_own_classification(fresh_store):
    terms = ("overhead", "military", "shoulder press", "push press", "arnold",
             "behind the neck", "z press", "jerk", "french press")
    with fresh_store._catalog_lock:
        ids = [row[0] for row in fresh_store.catalog_conn.execute(
            "SELECT e.id FROM exercises e LEFT JOIN exercise_display_names d ON d.exercise_id=e.id "
            "WHERE " + " OR ".join("lower(e.name) LIKE ? OR lower(d.display_name) LIKE ?" for _ in terms),
            [value for term in terms for value in (f"%{term}%", f"%{term}%")],
        )]
    assert {"1727", "1738", "423", "1457", "194", "92", "2188", "453"}.issubset(set(ids))
    for exercise_id in ids:
        candidate = fresh_store.get_exercise_library_entry(exercise_id)
        if "landmine" in " ".join((str(candidate.get("name") or ""), str(candidate.get("source_name") or ""))).casefold():
            assert not is_movement_restricted(candidate, "flat_press", ["Overhead pressing"])
            continue
        assert is_movement_restricted(candidate, "flat_press", ["Overhead pressing"]), exercise_id
    for exercise_id in ("1723", "186", "334", "590"):
        assert not is_movement_restricted(fresh_store.get_exercise_library_entry(exercise_id), "", ["Overhead pressing"])


def test_uncurated_candidate_uses_supplied_slot_fallback(fresh_store):
    for exercise_id in ("1000", "1370", "108"):
        candidate = fresh_store.get_exercise_library_entry(exercise_id)
        assert not is_movement_restricted(candidate or {}, "calf", ["Hip adduction"]), exercise_id


@pytest.mark.parametrize(("description", "expected"), [
    ("I have FAI and my friend tore his ACL", ["Deep hip flexion"]),
    ("I do not have back pain", []),
    ("my brother tore his ACL", []),
])
def test_suggestion_subject_and_negation_are_scoped_per_clause(description, expected):
    assert suggest_movement_restrictions(description) == expected


@pytest.mark.parametrize(("description", "expected"), [
    ("my brother tore his ACL and has back pain", []),
    ("I do not have knee flexion and hip adduction restrictions", []),
])
def test_suggestion_subject_and_negation_carry_across_conjoined_clauses(description, expected):
    assert suggest_movement_restrictions(description) == expected


@pytest.mark.parametrize(("description", "expected"), [
    ("I do not have back pain and I tore my ACL", ["Knee flexion", "Loaded knee extension"]),
    ("ما عنديش وجع الظهر و عندي احتكاك مفصل الحوض", ["Deep hip flexion"]),
    ("no back pain and knee pain", []),
])
def test_suggestion_negation_ends_at_new_positive_clause(description, expected):
    assert suggest_movement_restrictions(description) == expected


def test_warmup_restrictions_filter_dead_bug_and_record_the_drop(fresh_store):
    from agent.program_generator import build_warmup_block

    skipped = []
    warmups = build_warmup_block(
        "lower",
        "Commercial gym",
        "None",
        ledger=fresh_store.ledger,
        movement_restrictions=["Deep hip flexion"],
        skipped_restricted=skipped,
    )
    assert "Dead Bug" not in {warmup.exercise_name for warmup in warmups}
    assert {"slot": "warmup:dead_bug", "restriction": "Deep hip flexion"} in skipped
    assert is_movement_restricted(
        {"name": "Lying Leg Curl", "primary_action": None, "secondary_actions": []},
        "",
        ["Knee flexion"],
    )


def test_owner_approved_slots_apply_even_to_curated_rows_and_match_final_table():
    assert MOVEMENT_RESTRICTIONS["Hip abduction"]["slots"] == set()
    assert MOVEMENT_RESTRICTIONS["Overhead pressing"]["actions"] == set()
    assert is_movement_restricted(
        {"primary_action": "Knee Extension", "secondary_actions": []},
        "quad_compound", ["Deep hip flexion"],
    )
    assert is_movement_restricted(
        {"primary_action": "Knee Extension", "secondary_actions": []},
        "quad_compound", ["Loaded knee extension"],
    )


def test_unknown_restrictions_are_rejected():
    with pytest.raises(ValueError):
        validate_movement_restrictions(["ACL injury"])


def test_malformed_restriction_elements_are_rejected_as_value_error():
    with pytest.raises(ValueError):
        validate_movement_restrictions([["Knee flexion"]])


def test_restrictions_are_returned_in_canonical_vocabulary_order():
    assert validate_movement_restrictions(["Hip adduction", "Knee flexion"]) == [
        "Knee flexion", "Hip adduction"
    ]


@pytest.mark.parametrize(
    ("description", "expected"),
    [
        ("fai syndrome", ["Deep hip flexion"]),
        ("torn acl", ["Knee flexion", "Loaded knee extension"]),
        ("can not perform knee flexion nor training adductors", ["Knee flexion", "Hip adduction"]),
        ("الرباط الصليبي", ["Knee flexion", "Loaded knee extension"]),
        ("احتكاك مفصل الحوض", ["Deep hip flexion"]),
    ],
)
def test_injury_suggestion_keywords_are_deterministic(description, expected):
    assert suggest_movement_restrictions(description) == expected


@pytest.mark.parametrize(
    ("description", "expected"),
    [
        ("my friend tore his ACL", []),
        ("no ACL injury", []),
        ("no back pain", []),
        ("Cannot do overhead pressing", ["Overhead pressing"]),
        ("صاحبي عنده الرباط الصليبي", []),
        ("ما عنديش ألم في الظهر", []),
    ],
)
def test_injury_suggestions_respect_subject_negation_and_overhead_scope(description, expected):
    assert suggest_movement_restrictions(description) == expected


def test_arabic_back_pain_negation_suppresses_spinal_suggestion():
    assert suggest_movement_restrictions("ما عنديش وجع الظهر") == []
    assert suggest_movement_restrictions("عندي وجع الظهر") == ["Spinal loading / flexion"]


def test_production_injury_combination_drops_conflicting_slots(fresh_store):
    from agent.program_generator import ProgramGenerationRequest, generate_program_draft_pipeline
    from agent.program_rules import restricted_candidate_reasons

    profile = _profile(
        restrictions=["Knee flexion", "Hip adduction", "Deep hip flexion"],
        limitations="FAI syndrome; torn ACL; cannot perform knee flexion nor train adductors",
    )
    assert restricted_candidate_reasons(
        "ham_curl", profile["equipment_access"], profile["injuries_or_limitations"],
        tuple(profile["movement_restrictions"]), ledger=fresh_store.ledger,
    ) == ["Knee flexion"]
    program = generate_program_draft_pipeline(
        ProgramGenerationRequest(user_split_override="ppl", frequency_override=3),
        ledger=fresh_store.ledger,
        profile=profile,
    )[0]
    prescribed = [exercise for day in program.days for exercise in day.exercises]
    assert all(exercise.slot_key not in {"ham_curl", "adductors", "quad_compound", "quad_lunge"} for exercise in prescribed)
    assert all(
        not is_movement_restricted(_curation_for(fresh_store, exercise.exercise_id), exercise.slot_key,
                                   profile["movement_restrictions"])
        for exercise in prescribed
    )
    skipped = [entry for day in program.program_rationale["days"] for entry in day.get("skipped", [])]
    assert {entry["slot"] for entry in skipped} >= {"ham_curl", "adductors"}, program.program_rationale


def test_all_generation_splits_frequencies_and_equipment_respect_restrictions(fresh_store):
    from agent.program_generator import ProgramGenerationRequest, generate_program_draft_pipeline
    from agent.program_rules import SPLIT_OPTIONS_BY_FREQUENCY
    from utils.equipment_access import BODYWEIGHT_ONLY, COMMERCIAL_GYM, HOME_GYM

    restriction_sets = (
        ["Knee flexion", "Hip adduction"],
        ["Deep hip flexion", "Loaded knee extension"],
    )
    for frequency, splits in SPLIT_OPTIONS_BY_FREQUENCY.items():
        for split_type, _display_name in splits:
            for equipment in (COMMERCIAL_GYM, HOME_GYM, BODYWEIGHT_ONLY):
                for restrictions in restriction_sets:
                    profile = _profile(restrictions, equipment=equipment)
                    program = generate_program_draft_pipeline(
                        ProgramGenerationRequest(
                            user_split_override=split_type, frequency_override=frequency,
                        ),
                        ledger=fresh_store.ledger,
                        profile=profile,
                    )[0]
                    for day in program.days:
                        for exercise in day.exercises:
                            assert not is_movement_restricted(
                                _curation_for(fresh_store, exercise.exercise_id),
                                exercise.slot_key,
                                restrictions,
                            ), (split_type, frequency, equipment, restrictions, exercise)
                    rationale_skips = [
                        skip for day in program.program_rationale["days"]
                        for skip in day.get("skipped", [])
                    ]
                    if "Knee flexion" in restrictions:
                        assert any(skip["slot"] == "ham_curl" for skip in rationale_skips), (split_type, frequency, equipment, restrictions, rationale_skips)


def test_player_edits_cannot_add_restricted_curl(fresh_store):
    from agent.ProgramState import program_exercise_working_sets
    from agent.program_generator import ProgramGenerationRequest, generate_program_draft_pipeline
    from service.program_analytics import ProgramAnalyticsActor
    from service.program_edit import ProgramEdit, ProgramEditExercise, edit_active_program_day

    db = fresh_store
    profile = _profile(["Knee flexion"])
    db.ledger.upsert_player_profile(profile)
    program = generate_program_draft_pipeline(
        ProgramGenerationRequest(user_split_override="ppl", frequency_override=3),
        ledger=db.ledger, profile=profile,
    )[0]
    db.ledger.save_training_program(program.model_dump())
    active = db.ledger.get_active_program()
    day = active.days[0]
    original_edits = [
        ProgramEditExercise(index, str(exercise.exercise_id), program_exercise_working_sets(exercise))
        for index, exercise in enumerate(day.exercises)
    ]
    curl = db.catalog_conn.execute(
        "SELECT e.id FROM exercises e JOIN exercise_curated_fields cf ON cf.exercise_id=e.id "
        "WHERE LOWER(cf.primary_action)='knee flexion' AND cf.hidden=0 LIMIT 1"
    ).fetchone()
    assert curl is not None
    player_id = "00000000-0000-4000-8000-000000000001"
    result = edit_active_program_day(
        db, db.ledger,
        ProgramEdit(
            day_name=day.day_name, expected_active_version=active.version,
            exercises=[*original_edits, ProgramEditExercise(-1, str(curl[0]), 2)],
            player_account_id=player_id,
            actor=ProgramAnalyticsActor(player_id, "player"),
        ),
    )
    assert result["code"] == "movement_restricted"


def test_substitution_suggestions_cannot_replace_with_restricted_curl(fresh_store):
    from agent.program_generator import ProgramGenerationRequest, generate_program_draft_pipeline
    from service.program_substitution import ProgramSubstitution, substitute_program_exercise

    db = fresh_store
    profile = _profile(["Knee flexion"])
    db.ledger.upsert_player_profile(profile)
    program = generate_program_draft_pipeline(
        ProgramGenerationRequest(user_split_override="ppl", frequency_override=3),
        ledger=db.ledger, profile=profile,
    )[0]
    db.ledger.save_training_program(program.model_dump())
    active = db.ledger.get_active_program()
    source = next(exercise for exercise in active.days[0].exercises)
    curl = db.catalog_conn.execute(
        "SELECT e.id FROM exercises e JOIN exercise_curated_fields cf ON cf.exercise_id=e.id "
        "WHERE LOWER(cf.primary_action)='knee flexion' AND cf.hidden=0 LIMIT 1"
    ).fetchone()
    assert curl is not None
    response = substitute_program_exercise(
        db.ledger, db, active,
        ProgramSubstitution(
            day_name=active.days[0].day_name,
            exercise_id=str(source.exercise_id), replacement_exercise_id=str(curl[0]),
        ),
    )
    assert response["code"] == "movement_restricted"


def test_open_workout_prescription_flags_conflicting_curl_without_removing_it(fresh_store):
    from agent.program_generator import ProgramGenerationRequest, generate_program_draft_pipeline
    from service.workouts import build_prescription

    db = fresh_store
    profile = _profile([])
    program = generate_program_draft_pipeline(
        ProgramGenerationRequest(user_split_override="ppl", frequency_override=3),
        ledger=db.ledger, profile=profile,
    )[0]
    day = next(day for day in program.days if any(ex.slot_key == "ham_curl" for ex in day.exercises))
    db.ledger.upsert_player_profile(_profile(["Knee flexion"]))
    response = build_prescription(
        db, db.ledger.ledger_id, day, ledger=db.ledger,
        player_account_id="00000000-0000-4000-8000-000000000001",
    )
    curl = next(target for target in response["targets"] if target["exercise_name"] == next(
        ex.exercise_name for ex in day.exercises if ex.slot_key == "ham_curl"
    ))
    assert curl["movement_restriction"]["label"] == "Knee flexion"


def _profile(restrictions, limitations="None", equipment="Commercial gym"):
    return {
        "gender": "male", "proportions": "balanced", "age": 28, "weight_kg": 70.0,
        "height_cm": 175.0, "rep_preference": "balanced", "current_goal": "hypertrophy",
        "long_term_goal": "progressive overload", "weekly_frequency": 3,
        "training_age_years": 3.0, "equipment_access": equipment,
        "injuries_or_limitations": limitations, "stress_and_sleep": "normal",
        "weak_points": None, "movement_restrictions": restrictions,
    }


def _curation_for(ledger, exercise_id):
    row = ledger.ledger.conn.execute(
        "SELECT primary_action, secondary_actions FROM catalog.exercise_curated_fields WHERE exercise_id = ?",
        (exercise_id,),
    ).fetchone()
    return dict(row) if row else {"primary_action": None, "secondary_actions": []}


def test_unrestricted_muscles_keep_weekly_sets_when_slots_are_dropped(fresh_store):
    from agent.program_generator import ProgramGenerationRequest, generate_program_draft_pipeline
    from tests.test_coach_pattern_rubric import MUSCLE_GROUPS

    db = fresh_store
    request = ProgramGenerationRequest(user_split_override="ppl", frequency_override=3)
    unrestricted = generate_program_draft_pipeline(request, ledger=db.ledger, profile=_profile([]))[0]
    restricted = generate_program_draft_pipeline(
        request, ledger=db.ledger, profile=_profile(["Knee flexion", "Hip adduction"])
    )[0]

    def weekly_sets(program, slots):
        return sum(
            exercise.target_sets
            for day in program.days
            for exercise in day.exercises
            if exercise.slot_key in slots
        )

    for muscle, slots in MUSCLE_GROUPS.items():
        if muscle in {"hamstrings", "adductors"}:
            continue
        assert weekly_sets(restricted, slots) == weekly_sets(unrestricted, slots), muscle
    assert weekly_sets(restricted, MUSCLE_GROUPS["calves"]) == weekly_sets(
        unrestricted, MUSCLE_GROUPS["calves"]
    )


def test_fully_restricted_focus_variant_is_unavailable_with_restriction_reason(fresh_store):
    from agent.program_generator import ProgramGenerationRequest, generate_program_draft_pipeline

    profile = _profile(["Hip adduction"])
    profile["weak_points"] = [{"muscle": "adductors", "source": "named"}]
    program = generate_program_draft_pipeline(
        ProgramGenerationRequest(user_split_override="ppl", frequency_override=3),
        ledger=fresh_store.ledger,
        profile=profile,
    )[0]
    focus = next(item for item in program.program_rationale["focus_muscles"] if item["muscle"] == "adductors")
    assert focus["status"] == "unavailable"
    assert focus["reason"]["params"]["restriction"] == "Hip adduction"


def test_chat_restriction_offer_expires_after_thirty_minutes(fresh_store, monkeypatch):
    from datetime import UTC, timedelta
    import database.ledger.chat as chat_ledger

    ledger = fresh_store.ledger
    ledger.set_pending_movement_restriction_offer(["Knee flexion"], "offer")
    real_datetime = chat_ledger.datetime

    class ExpiredClock:
        @staticmethod
        def now(tz=None):
            return real_datetime.now(tz or UTC) + timedelta(minutes=31)

        @staticmethod
        def fromisoformat(value):
            return real_datetime.fromisoformat(value)

    monkeypatch.setattr(chat_ledger, "datetime", ExpiredClock)
    assert ledger.get_pending_movement_restriction_offer() is None
