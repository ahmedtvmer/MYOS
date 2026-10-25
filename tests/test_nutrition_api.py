import json
import sqlite3
from datetime import date, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from database.database_manager import DatabaseManager
from svc.app import create_app
from svc.dependencies import get_db


@pytest.fixture
def api(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("SKIP_LLM_LOAD", "true")
    monkeypatch.setenv("TESTING", "1")
    monkeypatch.setenv("JWT_SECRET", "test-secret-key-0123456789abcdef")
    from svc.rate_limit import limiter
    limiter._storage.reset()
    path = tmp_path / "catalog.db"
    conn = sqlite3.connect(path)
    conn.execute("CREATE TABLE exercises (id TEXT PRIMARY KEY, name TEXT, body_part TEXT, target_muscle TEXT, equipment TEXT, image_path TEXT, gif_path TEXT, instructions TEXT)")
    conn.execute("CREATE TABLE exercise_secondary_muscles (exercise_id TEXT, muscle TEXT)")
    conn.commit()
    conn.close()
    db = DatabaseManager(catalog_path=path, ledgers_dir=tmp_path / "users", backups_dir=tmp_path / "backups", default_ledger_id="bootstrap")
    app = create_app()
    app.dependency_overrides[get_db] = lambda: db
    try:
        with TestClient(app) as client:
            yield client, db
    finally:
        if db.ledger_conn is not None:
            db.ledger_conn.close()
        db.catalog_conn.close()


def test_setup_persists_targets_and_returns_goal_reason(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "nutrition-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "nutrition-player", age=30, target=60)
    response = client.post("/nutrition/setup", headers=headers, json={
        "sex": "female", "sex_confirmed": True,
        "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["state"] == "ready"
    assert body["goal"] == "lose"
    assert body["goal_reason"]["code"] == "target_weight"
    assert body["goal_reason"]["target_weight_kg"] == 60
    assert body["targets"]["calories"] > 0
    account = db.get_active_account_by_username("nutrition-player")
    with db.open_ledger(account["ledger_id"]) as ledger:
        with pytest.raises(sqlite3.IntegrityError, match="immutable"):
            ledger.conn.execute("UPDATE nutrition_plan_versions SET goal='gain'")
    active = client.get("/nutrition", headers=headers)
    assert active.json()["targets"] == body["targets"]
    arabic = client.get("/nutrition", headers={**headers, "Accept-Language": "ar"}).json()
    assert arabic["goal_reason"]["code"] == "target_weight"
    weight = client.post("/profile/weight", headers=headers, json={"weight_kg": 71})
    assert weight.status_code == 200
    assert client.get("/nutrition", headers=headers).json()["targets"] == body["targets"]


def test_coach_nutrition_requires_assignment_and_takeover_confirmation(api):
    client, db = api
    coach = client.post("/auth/register", json={"trainee_id": "nutrition-coach", "password": "correct-horse-1"}).json()
    coach_headers = {"Authorization": f"Bearer {coach['access_token']}"}
    from service import coach as coach_service
    issued = coach_service.issue_coach_invite(db, "nutrition-coach", actor="cli")
    assert client.post("/coach/invite/redeem", headers=coach_headers, json={"token": issued["token"]}).status_code == 200
    assert client.put("/coach/profile", headers=coach_headers, json={"display_name":"Coach", "bio":"b", "specialization":"s", "capacity":5}).status_code == 200
    player = client.post("/auth/register", json={"trainee_id": "nutrition-client", "password": "correct-horse-1"}).json()
    player_headers = {"Authorization": f"Bearer {player['access_token']}"}
    denied = client.get("/coach/assignments/nope/nutrition", headers=coach_headers)
    assert denied.status_code == 403
    token = client.post("/coach/assignments/invites", headers=coach_headers).json()["token"]
    redeemed = client.post("/assignments/invites/redeem", headers=player_headers, json={"token":token,"consent":True}).json()
    assignment_id = redeemed["assignment"]["assignment_id"]
    _seed_profile(db, "nutrition-client", age=30, target=None)
    setup = client.post("/nutrition/setup", headers=player_headers, json={
        "sex":"male", "sex_confirmed":True, "daily_activity":"mostly_sitting",
        "screening":{"pregnant_or_breastfeeding":False,"medical_condition":False,"eating_disorder":False}})
    assert setup.status_code == 200
    from agent.ProgramState import GeneratedProgramSchema, ProgramDaySchema, ProgramExerciseSchema
    coach_account_id = db.get_active_account_by_username("nutrition-coach")["account_id"]
    player_account = db.get_active_account_by_username("nutrition-client")
    db.catalog_conn.executemany(
        "INSERT INTO exercises (id, name, body_part, target_muscle, equipment) VALUES (?, ?, 'Test', 'Test', 'Test')",
        [("sq", "Squat"), ("bp", "Bench Press"), ("row", "Row")],
    )
    db.catalog_conn.commit()
    program = GeneratedProgramSchema(
        program_name="Published training program", split_type="Full Body", weekly_frequency=4,
        days=[ProgramDaySchema(day_name="Full A", day_order=1, exercises=[
                ProgramExerciseSchema(exercise_id="sq", exercise_name="Squat", target_reps_min=5, target_reps_max=8),
                ProgramExerciseSchema(exercise_id="bp", exercise_name="Bench Press", target_reps_min=5, target_reps_max=8),
                ProgramExerciseSchema(exercise_id="row", exercise_name="Row", target_reps_min=5, target_reps_max=8),
        ])],
    )
    with db.open_ledger(player_account["ledger_id"]) as ledger:
        ledger.save_training_program(program.model_dump())
    published = client.post(f"/coach/assignments/{assignment_id}/program/approve",
                            headers=coach_headers, json={"expected_active_version": 1})
    assert published.status_code == 200, published.text
    assert client.get("/nutrition", headers=player_headers).json()["authority"] == "player"
    payload = {"goal":"lose", "targets":{"calories":2000, "protein_g":126, "carbs_g":248, "fat_g":56}}
    path = f"/coach/assignments/{assignment_id}/nutrition"
    initial_read = client.get(path, headers=coach_headers)
    assert initial_read.json()["authority"] == "player"
    assert len(initial_read.json()["adherence_days"]) == 14
    charts_read = client.get(f"{path}?days=28", headers=coach_headers).json()
    assert len(charts_read["adherence_days"]) == 28
    assert isinstance(charts_read["weight_trend"], list)
    assert isinstance(initial_read.json()["weight_trend"], list)
    assert "weekly_rate_pct" in initial_read.json()["targets"]
    missing_confirmation = client.put(path, headers=coach_headers, json=payload)
    assert missing_confirmation.status_code == 400
    assert "confirm" in missing_confirmation.json()["detail"].lower()
    payload["confirm_takeover"] = True
    saved = client.put(path, headers=coach_headers, json=payload)
    assert saved.status_code == 200, saved.text
    assert saved.json()["authority"] == "coach"
    activity_change = client.put("/nutrition/activity", headers=player_headers,
                                 json={"daily_activity": "physical_job"})
    assert activity_change.status_code == 403
    payload["confirm_takeover"] = False
    repeated = client.put(path, headers=coach_headers, json=payload)
    assert repeated.status_code == 200, repeated.text
    assert repeated.json()["authority"] == "coach"
    planned_read = client.get(f"{path}?days=28", headers=coach_headers).json()
    assert planned_read["planned_weekly_rate_pct"] < 0
    assert planned_read["planned_weekly_rate_pct"] == pytest.approx(-0.39, abs=0.03)
    string_targets = {key: str(value) for key, value in payload["targets"].items()}
    normalized = client.put(path, headers=coach_headers, json={**payload, "targets": string_targets})
    assert normalized.status_code == 200, normalized.text
    assert all(isinstance(value, int) for value in normalized.json()["targets"].values())
    with db.open_ledger(db.get_active_account_by_username("nutrition-client")["ledger_id"]) as ledger:
        saved_targets = json.loads(ledger.get_active_nutrition_plan()["targets_json"])["daily"]
    assert all(isinstance(value, int) for value in saved_targets.values())
    with db.open_ledger(db.get_active_account_by_username("nutrition-client")["ledger_id"]) as ledger:
        ledger.save_training_program(program.model_dump(), published_by_coach_account_id=coach_account_id)
    assert client.get(path, headers=coach_headers).json()["authority"] == "coach"
    assert client.get("/nutrition", headers=player_headers).json()["authority"] == "coach"
    assert client.post(f"/coach/assignments/{assignment_id}/revoke", headers=coach_headers).status_code == 200
    returned = client.get("/nutrition", headers=player_headers).json()
    assert returned["authority"] == "player"


@pytest.mark.parametrize("goal", ["maintain", "gain"])
def test_coach_can_save_maintain_or_gain_targets_for_under_18_player(api, goal):
    client, db = api
    coach = client.post("/auth/register", json={"trainee_id": f"minor-coach-{goal}", "password": "correct-horse-1"}).json()
    coach_headers = {"Authorization": f"Bearer {coach['access_token']}"}
    from service import coach as coach_service
    issued = coach_service.issue_coach_invite(db, f"minor-coach-{goal}", actor="cli")
    assert client.post("/coach/invite/redeem", headers=coach_headers, json={"token": issued["token"]}).status_code == 200
    assert client.put("/coach/profile", headers=coach_headers, json={"display_name":"Coach", "bio":"b", "specialization":"s", "capacity":5}).status_code == 200
    player_name = f"minor-player-{goal}"
    player = client.post("/auth/register", json={"trainee_id": player_name, "password": "correct-horse-1"}).json()
    player_headers = {"Authorization": f"Bearer {player['access_token']}"}
    token = client.post("/coach/assignments/invites", headers=coach_headers).json()["token"]
    assignment = client.post("/assignments/invites/redeem", headers=player_headers,
                             json={"token": token, "consent": True}).json()["assignment"]
    _seed_profile(db, player_name, age=17, target=None)
    target_calories = 2450 if goal == "gain" else 2000
    target_carbs = 362 if goal == "gain" else 250
    saved = client.put(f"/coach/assignments/{assignment['assignment_id']}/nutrition",
                       headers=coach_headers, json={"goal": goal, "confirm_takeover": True,
                       "targets": {"calories": target_calories, "protein_g": 100,
                                   "carbs_g": target_carbs, "fat_g": 67}})
    assert saved.status_code == 200, saved.text
    assert saved.json()["goal"] == goal


@pytest.mark.parametrize(("case", "profile", "body", "expected"), [
    ("incomplete profile", None, {"goal": "maintain", "confirm_takeover": True,
     "targets": {"calories": 2000, "protein_g": 100, "carbs_g": 250, "fat_g": 67}}, "Training profile"),
    ("screening block", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "maintain", "confirm_takeover": True, "targets": {"calories": 2000, "protein_g": 100, "carbs_g": 250, "fat_g": 67}}, "dietitian"),
    ("under-18 loss", {"age": 17, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "lose", "confirm_takeover": True, "targets": {"calories": 2000, "protein_g": 100, "carbs_g": 250, "fat_g": 67}}, "under 18"),
    ("missing confirmation", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "maintain", "targets": {"calories": 2000, "protein_g": 100, "carbs_g": 250, "fat_g": 67}}, "Confirm"),
    ("missing targets", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "maintain", "confirm_takeover": True}, "Set Nutrition targets"),
    ("calorie floor", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "maintain", "confirm_takeover": True,
      "targets": {"calories": 1500, "protein_g": 100, "carbs_g": 250, "fat_g": 67}}, "Calorie floor"),
    ("macro calories", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "maintain", "confirm_takeover": True,
      "targets": {"calories": 2000, "protein_g": 0, "carbs_g": 0, "fat_g": 0}}, "within 5%"),
    ("negative macro", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "maintain", "confirm_takeover": True,
      "targets": {"calories": 2000, "protein_g": -1, "carbs_g": 250, "fat_g": 67}}, "protein_g must be a whole number"),
    ("boolean calories", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "maintain", "confirm_takeover": True,
      "targets": {"calories": True, "protein_g": 100, "carbs_g": 250, "fat_g": 67}}, "calories must be a whole number"),
    ("gain rate cap", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "gain", "confirm_takeover": True,
      "targets": {"calories": 3000, "protein_g": 150, "carbs_g": 400, "fat_g": 89}}, "0.5% per week"),
    ("maintain surplus rate cap", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "maintain", "confirm_takeover": True,
      "targets": {"calories": 5000, "protein_g": 200, "carbs_g": 825, "fat_g": 100}}, "0.5% per week"),
    ("lose rate cap", {"age": 30, "height_cm": 165, "weight_kg": 70, "gender": "male"},
     {"goal": "lose", "daily_activity": "physical_job", "confirm_takeover": True,
      "targets": {"calories": 1600, "protein_g": 100, "carbs_g": 149, "fat_g": 67}}, "1% per week"),
])
def test_coach_nutrition_validation_rules(case, profile, body, expected, api):
    client, db = api
    suffix = case.lower().replace(" ", "-")
    coach = client.post("/auth/register", json={"trainee_id": f"coach-{suffix}", "password": "correct-horse-1"}).json()
    coach_headers = {"Authorization": f"Bearer {coach['access_token']}"}
    from service import coach as coach_service
    invite = coach_service.issue_coach_invite(db, f"coach-{suffix}", actor="cli")
    assert client.post("/coach/invite/redeem", headers=coach_headers, json={"token": invite["token"]}).status_code == 200
    assert client.put("/coach/profile", headers=coach_headers, json={
        "display_name": "Coach", "bio": "b", "specialization": "s", "capacity": 5,
    }).status_code == 200
    player_name = f"player-{suffix}"
    player = client.post("/auth/register", json={"trainee_id": player_name, "password": "correct-horse-1"}).json()
    player_headers = {"Authorization": f"Bearer {player['access_token']}"}
    token = client.post("/coach/assignments/invites", headers=coach_headers).json()["token"]
    assignment = client.post("/assignments/invites/redeem", headers=player_headers,
                             json={"token": token, "consent": True}).json()["assignment"]
    if profile is not None:
        _seed_profile(db, player_name, age=profile["age"], target=None)
    if case == "screening block":
        client.post("/nutrition/setup", headers=player_headers, json={
            "sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
            "screening": {"pregnant_or_breastfeeding": False, "medical_condition": True,
                          "eating_disorder": False},
        })
    response = client.put(
        f"/coach/assignments/{assignment['assignment_id']}/nutrition",
        headers=coach_headers, json=body,
    )
    assert response.status_code == 400, response.text
    assert expected.lower() in response.json()["detail"].lower()


def test_player_target_uses_training_or_rest_day_schedule_and_assignment_authority(api, monkeypatch):
    from datetime import date
    from database.ledger.nutrition import NutritionPlanVersion
    from svc.routers import nutrition as nutrition_router

    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "nutrition-day-type", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "nutrition-day-type", age=30, target=None)
    account = db.get_active_account_by_username("nutrition-day-type")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.save_nutrition_plan(NutritionPlanVersion(
            goal="maintain", reason={"code": "coach"}, intensity=None,
            daily_activity="mostly_sitting", author="Coach", provenance="coach",
            authority_assignment_id="prior-assignment",
            targets={
                "daily": None,
                "training_day": {"calories": 2200, "protein_g": 120, "carbs_g": 260, "fat_g": 71},
                "rest_day": {"calories": 1900, "protein_g": 120, "carbs_g": 185, "fat_g": 71},
            },
        ))
        ledger.append_training_schedule(account["ledger_id"], [1], "UTC", "2026-10-01", "2026-10-01T00:00:00Z")
    monkeypatch.setattr(nutrition_router, "player_local_date", lambda *_args, **_kwargs: date(2026, 10, 26))
    monkeypatch.setattr(db, "get_active_assignment_for_player", lambda _account: {"assignment_id": "new-assignment"})
    training = client.get("/nutrition", headers=headers).json()
    assert training["targets"]["calories"] == 2200
    assert training["target_day_type"] == "training_day"
    assert training["authority"] == "player"

    monkeypatch.setattr(nutrition_router, "player_local_date", lambda *_args, **_kwargs: date(2026, 10, 27))
    rest = client.get("/nutrition", headers=headers).json()
    assert rest["targets"]["calories"] == 1900
    assert rest["target_day_type"] == "rest_day"


def test_positive_rescreen_blocks_existing_plan_and_profileless_is_incomplete(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "rescreen-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "rescreen-player", age=30, target=None)
    payload = {"sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
               "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False}}
    assert client.post("/nutrition/setup", headers=headers, json=payload).json()["state"] == "ready"
    payload["screening"]["medical_condition"] = True
    assert client.post("/nutrition/setup", headers=headers, json=payload).json()["state"] == "blocked"
    assert client.get("/nutrition", headers=headers).json()["state"] == "blocked"
    fresh = client.post("/auth/register", json={"trainee_id": "no-profile", "password": "correct-horse-1"}).json()
    incomplete = client.get("/nutrition", headers={"Authorization": f"Bearer {fresh['access_token']}"}).json()
    assert incomplete["state"] == "incomplete"
    assert incomplete["message"]
    arabic = client.get("/nutrition", headers={"Authorization": f"Bearer {fresh['access_token']}",
                                               "Accept-Language": "ar"}).json()
    assert "الأهداف الغذائية" in arabic["message"]


def test_stored_female_gender_is_used_for_explicit_confirmation_and_no_silent_flip(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "female-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "female-player", age=30, target=None)
    account = db.get_active_account_by_username("female-player")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.conn.execute("UPDATE user_profile SET gender='female' WHERE id=1")
        ledger.conn.commit()
    assert client.get("/nutrition", headers=headers).json()["sex"] == "female"
    response = client.post("/nutrition/setup", headers=headers, json={
        "sex": "female", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert response.json()["targets"]["bmr"] == 1420.2
    with db.open_ledger(account["ledger_id"]) as ledger:
        assert ledger.conn.execute("SELECT gender FROM user_profile").fetchone()[0] == "female"


def test_positive_screening_blocks_target_generation(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "screened-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "screened-player", age=30, target=None)
    response = client.post("/nutrition/setup", headers=headers, json={
        "sex": "female", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": True, "medical_condition": False, "eating_disorder": False},
    })
    assert response.status_code == 200
    assert response.json()["state"] == "blocked"
    assert "dietitian" in response.json()["message"].lower()
    assert client.get("/nutrition", headers=headers).json()["targets"] is None


def test_under_18_gets_explicit_no_targets_state(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "minor-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "minor-player", age=17, target=60)
    assert client.get("/nutrition", headers=headers).json()["state"] == "under_18"
    response = client.post("/nutrition/setup", headers=headers, json={
        "sex": "male", "sex_confirmed": True, "daily_activity": "on_feet",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert response.status_code == 200
    assert response.json()["state"] == "under_18"
    assert response.json()["targets"] is None
    assert client.get("/nutrition", headers=headers).json()["state"] == "under_18"


def test_target_weight_overrides_conflicting_current_goal(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "conflict-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "conflict-player", age=30, target=80, current_goal="fat loss")
    response = client.post("/nutrition/setup", headers=headers, json={
        "sex": "male", "sex_confirmed": True, "daily_activity": "on_feet",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert response.status_code == 200
    assert response.json()["goal"] == "gain"
    assert response.json()["goal_reason"]["code"] == "target_weight"


def test_silent_goal_without_target_starts_maintain_without_intensity(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "maintain-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "maintain-player", age=30, target=None)
    response = client.post("/nutrition/setup", headers=headers, json={
        "sex": "female", "sex_confirmed": True, "daily_activity": "physical_job",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert response.status_code == 200
    assert response.json()["goal"] == "maintain"
    assert response.json()["intensity"] is None
    assert response.json()["goal_reason"]["code"] == "default"


@pytest.mark.parametrize("target,goal", [(69.0, "maintain"), (71.0, "maintain"), (68.9, "lose"), (71.1, "gain")])
def test_target_weight_one_kg_band_resolves_goal(target, goal, api):
    client, db = api
    username = f"band-{target}"
    registered = client.post("/auth/register", json={"trainee_id": username, "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, username, age=30, target=target, current_goal="get stronger")
    response = client.post("/nutrition/setup", headers=headers, json={
        "sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert response.json()["goal"] == goal
    assert response.json()["goal_reason"]["code"] == "target_weight"


def test_goal_text_reason_is_structured_for_english_and_arabic(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "arabic-goal", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "arabic-goal", age=30, target=None, current_goal="خسارة الدهون")
    response = client.post("/nutrition/setup", headers=headers, json={
        "sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert response.json()["goal_reason"] == {"code": "current_goal", "goal_text": "خسارة الدهون"}
    for language in ("en", "ar"):
        saved = client.get("/nutrition", headers={**headers, "Accept-Language": language}).json()
        assert saved["goal_reason"]["goal_text"] == "خسارة الدهون"


def test_setup_analytics_event_excludes_screening_answers(api, recording_analytics):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "analytics-nutrition", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "analytics-nutrition", age=30, target=None)
    client.post("/nutrition/setup", headers=headers, json={
        "sex": "female", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": True, "medical_condition": False, "eating_disorder": False},
    })
    events = [event for event in recording_analytics.events if event["event"] == "nutrition_setup_completed"]
    assert events[0]["properties"]["blocked"] is True
    assert "screening" not in events[0]["properties"]
    clear = client.post("/auth/register", json={"trainee_id": "analytics-clear", "password": "correct-horse-1"}).json()
    _seed_profile(db, "analytics-clear", age=30, target=None)
    client.post("/nutrition/setup", headers={"Authorization": f"Bearer {clear['access_token']}"}, json={
        "sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert [item["properties"]["blocked"] for item in recording_analytics.events
            if item["event"] == "nutrition_setup_completed"][-1] is False


def test_activity_save_creates_version_and_weight_entry_does_not_change_it(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "activity-plan", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "activity-plan", age=30, target=None)
    client.post("/nutrition/setup", headers=headers, json={
        "sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    changed = client.put("/nutrition/activity", headers=headers, json={"daily_activity": "physical_job"})
    assert changed.json()["daily_activity"] == "physical_job"
    before = changed.json()["targets"]
    client.post("/profile/weight", headers=headers, json={"weight_kg": 71})
    assert client.get("/nutrition", headers=headers).json()["targets"] == before
    account = db.get_active_account_by_username("activity-plan")
    with db.open_ledger(account["ledger_id"]) as ledger:
        assert ledger.conn.execute("SELECT COUNT(*) FROM nutrition_plan_versions").fetchone()[0] == 2


def test_pace_preview_does_not_save_and_goal_save_versions_and_rescreens_lose(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "pace-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "pace-player", age=30, target=None)
    setup = {"sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
             "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False}}
    client.post("/nutrition/setup", headers=headers, json=setup)
    account = db.get_active_account_by_username("pace-player")
    before = client.get("/nutrition", headers=headers).json()
    preview = client.post("/nutrition/preview", headers=headers,
                          json={"goal": "lose", "intensity": "aggressive"})
    assert preview.status_code == 200
    assert preview.json()["targets"]["calories"] >= preview.json()["targets"]["calorie_floor"]
    assert "reach_target_date" in preview.json()
    assert client.get("/nutrition", headers=headers).json() == before
    changed = client.put("/nutrition/goal", headers=headers,
                         json={"goal": "gain", "intensity": "light"})
    assert changed.status_code == 200
    assert changed.json()["goal_reason"] == {"code": "player_choice"}
    assert changed.json().get("pending_goal") is None
    with db.open_ledger(account["ledger_id"]) as ledger:
        assert ledger.conn.execute("SELECT COUNT(*) FROM nutrition_plan_versions").fetchone()[0] == 2
    rescreen = client.put("/nutrition/goal", headers=headers,
                          json={"goal": "lose", "intensity": "moderate"})
    assert rescreen.status_code == 400
    assert "screening" in rescreen.json()["detail"].lower()


def test_nutrition_read_offers_goal_update_after_target_edit(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "offer-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "offer-player", age=30, target=None)
    client.post("/nutrition/setup", headers=headers, json={"sex": "male", "sex_confirmed": True,
        "daily_activity": "mostly_sitting", "screening": {"pregnant_or_breastfeeding": False,
        "medical_condition": False, "eating_disorder": False}})
    account = db.get_active_account_by_username("offer-player")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.conn.execute("UPDATE user_profile SET target_weight_kg=60 WHERE id=1")
        ledger.conn.commit()
    assert client.get("/nutrition", headers=headers).json()["pending_goal"] == "lose"


def test_goal_offer_dismissal_is_stored_until_another_profile_change(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "dismiss-offer", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "dismiss-offer", age=30, target=None)
    client.post("/nutrition/setup", headers=headers, json={"sex": "male", "sex_confirmed": True,
        "daily_activity": "mostly_sitting", "screening": {"pregnant_or_breastfeeding": False,
        "medical_condition": False, "eating_disorder": False}})
    account = db.get_active_account_by_username("dismiss-offer")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.conn.execute("UPDATE user_profile SET target_weight_kg=60 WHERE id=1")
        ledger.conn.commit()
    assert client.get("/nutrition", headers=headers).json()["pending_goal"] == "lose"
    response = client.post("/nutrition/goal-offer/dismiss", headers=headers)
    assert response.status_code == 200
    assert client.get("/nutrition", headers=headers).json().get("pending_goal") is None
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.conn.execute("UPDATE user_profile SET target_weight_kg=80 WHERE id=1")
        ledger.conn.commit()
    assert client.get("/nutrition", headers=headers).json()["pending_goal"] == "gain"


def test_preview_requires_confirmed_sex_and_screening(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "preview-setup", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "preview-setup", age=30, target=60)
    response = client.post("/nutrition/preview", headers=headers,
                           json={"goal": "lose", "intensity": "aggressive"})
    assert response.status_code == 200
    assert response.json()["state"] == "setup_required"
    assert response.json()["targets"] is None


def test_reach_target_date_uses_real_player_schedule_timezone(api, monkeypatch):
    from datetime import datetime, timezone
    from service import weight_history

    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "tokyo-local-date", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "tokyo-local-date", age=30, target=60)
    account = db.get_active_account_by_username("tokyo-local-date")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.append_training_schedule(account["ledger_id"], [0, 1], "Asia/Tokyo", "2026-01-01", "2026-01-01T00:00:00Z")
    class FrozenDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return cls(2026, 10, 24, 22, 30, tzinfo=timezone.utc).astimezone(tz)
    monkeypatch.setattr(weight_history, "datetime", FrozenDateTime)
    client.post("/nutrition/setup", headers=headers, json={"sex": "male", "sex_confirmed": True,
        "daily_activity": "mostly_sitting", "screening": {"pregnant_or_breastfeeding": False,
        "medical_condition": False, "eating_disorder": False}})
    response = client.post("/nutrition/preview", headers=headers,
                           json={"goal": "lose", "intensity": "moderate"}).json()
    rate = response["targets"]["weekly_rate_pct"]
    days = round(abs(60 - 70) / (70 * rate / 100) * 7)
    assert response["reach_target_date"] == (date(2026, 10, 25) + timedelta(days=days)).isoformat()


def test_adherence_requires_active_unblocked_nutrition_plan(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "no-plan-adherence", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "no-plan-adherence", age=30, target=None)
    no_plan = client.put("/nutrition/adherence", headers=headers, json={"value": "off"})
    assert no_plan.status_code == 409
    assert "Nutrition plan" in no_plan.json()["detail"]
    client.post("/nutrition/setup", headers=headers, json={"sex": "male", "sex_confirmed": True,
        "daily_activity": "mostly_sitting", "screening": {"pregnant_or_breastfeeding": True,
        "medical_condition": False, "eating_disorder": False}})
    blocked = client.put("/nutrition/adherence", headers=headers, json={"value": "off"})
    assert blocked.status_code == 409
    assert "screening" in blocked.json()["detail"].lower()


def test_saving_unchanged_nutrition_goal_is_noop(api, recording_analytics):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "same-pace", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "same-pace", age=30, target=60)
    client.post("/nutrition/setup", headers=headers, json={"sex": "male", "sex_confirmed": True,
        "daily_activity": "mostly_sitting", "screening": {"pregnant_or_breastfeeding": False,
        "medical_condition": False, "eating_disorder": False}})
    account = db.get_active_account_by_username("same-pace")
    with db.open_ledger(account["ledger_id"]) as ledger:
        before = ledger.conn.execute("SELECT COUNT(*) FROM nutrition_plan_versions").fetchone()[0]
    response = client.put("/nutrition/goal", headers=headers, json={"goal": "lose", "intensity": "moderate"})
    assert response.status_code == 200
    with db.open_ledger(account["ledger_id"]) as ledger:
        after = ledger.conn.execute("SELECT COUNT(*) FROM nutrition_plan_versions").fetchone()[0]
    events = [event for event in recording_analytics.events if event["event"] == "nutrition_goal_saved"]
    assert after == before
    assert events == []


def test_goal_save_analytics_uuid_tracks_each_plan_version(api, recording_analytics):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "goal-event", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "goal-event", age=30, target=None)
    client.post("/nutrition/setup", headers=headers, json={"sex": "male", "sex_confirmed": True,
        "daily_activity": "mostly_sitting", "screening": {"pregnant_or_breastfeeding": False,
        "medical_condition": False, "eating_disorder": False}})
    for goal, intensity in (("gain", "light"), ("maintain", "moderate"), ("gain", "light")):
        response = client.put("/nutrition/goal", headers=headers,
                              json={"goal": goal, "intensity": intensity})
        assert response.status_code == 200
    events = [event for event in recording_analytics.events if event["event"] == "nutrition_goal_saved"]
    assert len(events) == 3
    assert len({event["uuid"] for event in events}) == 3


def test_coach_authored_plan_without_active_assignment_does_not_withhold_player_authority(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "coach-plan", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "coach-plan", age=30, target=None)
    client.post("/nutrition/setup", headers=headers, json={"sex": "male", "sex_confirmed": True,
        "daily_activity": "mostly_sitting", "screening": {"pregnant_or_breastfeeding": False,
        "medical_condition": False, "eating_disorder": False}})
    account = db.get_active_account_by_username("coach-plan")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.conn.execute("DROP TRIGGER nutrition_plan_versions_no_update")
        ledger.conn.execute("UPDATE nutrition_plan_versions SET author='Coach' WHERE id=(SELECT MAX(id) FROM nutrition_plan_versions)")
        ledger.conn.commit()
    response = client.put("/nutrition/goal", headers=headers,
                          json={"goal": "gain", "intensity": "light"})
    assert response.status_code == 200, response.text
    assert response.json()["authority"] == "player"


def _seed_profile(db, username, *, age, target, current_goal="get stronger"):
    account = db.get_active_account_by_username(username)
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.conn.execute("""INSERT OR REPLACE INTO user_profile (
            id, gender, sex_confirmed, daily_activity, proportions, age, weight_kg,
            target_weight_kg, height_cm, rep_preference, current_goal, long_term_goal,
            weekly_frequency, training_age_years, equipment_access, injuries_or_limitations,
            stress_and_sleep, coach_tone, custom_instructions, created_at, updated_at
        ) VALUES (1, 'male', 0, NULL, 'average', ?, 70, ?, 165, 'balanced',
            ?, '', 4, 1, 'Commercial gym', 'None', '', '', '', 'now', 'now')""", (age, target, current_goal))
        ledger.conn.commit()


def test_adherence_write_replaces_today_and_returns_seven_day_state(api, recording_analytics):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "adherence-player", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "adherence-player", age=30, target=60)
    client.post("/nutrition/setup", headers=headers, json={
        "sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    first = client.put("/nutrition/adherence", headers=headers, json={"value": "off"})
    assert first.status_code == 200, first.text
    second = client.put("/nutrition/adherence", headers=headers, json={"value": "on_target"})
    assert second.status_code == 200, second.text
    state = client.get("/nutrition", headers=headers).json()
    assert state["today_adherence"] == "on_target"
    assert len(state["adherence_days"]) == 7
    assert sum(day["value"] == "on_target" for day in state["adherence_days"]) == 1
    account = db.get_active_account_by_username("adherence-player")
    with db.open_ledger(account["ledger_id"]) as ledger:
        assert ledger.conn.execute("SELECT COUNT(*) FROM nutrition_adherence").fetchone()[0] == 1
    events = [event for event in recording_analytics.events if event["event"] == "nutrition_adherence_logged"]
    assert [event["properties"]["value"] for event in events] == ["off", "on_target"]
    assert events[0]["uuid"] != events[1]["uuid"]


def test_adherence_rejects_non_today_date(api):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "adherence-date", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    response = client.put("/nutrition/adherence", headers=headers, json={"value": "off", "date": "2000-01-01"})
    assert response.status_code == 422


def test_adherence_write_uses_real_player_schedule_timezone(api, monkeypatch):
    from datetime import datetime, timezone
    from service import weight_history

    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "tokyo-adherence", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "tokyo-adherence", age=30, target=None)
    account = db.get_active_account_by_username("tokyo-adherence")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.append_training_schedule(account["ledger_id"], [0, 1], "Asia/Tokyo", "2026-01-01", "2026-01-01T00:00:00Z")
    class FrozenDateTime(datetime):
        @classmethod
        def now(cls, tz=None):
            return cls(2026, 10, 24, 22, 30, tzinfo=timezone.utc).astimezone(tz)
    monkeypatch.setattr(weight_history, "datetime", FrozenDateTime)
    client.post("/nutrition/setup", headers=headers, json={"sex": "male", "sex_confirmed": True,
        "daily_activity": "mostly_sitting", "screening": {"pregnant_or_breastfeeding": False,
        "medical_condition": False, "eating_disorder": False}})
    updated = client.put("/nutrition/adherence", headers=headers, json={"value": "on_target"})
    assert updated.status_code == 200
    assert updated.json()["today_adherence"] == "on_target"
    assert updated.json()["adherence_days"][-1] == {"date": "2026-10-25", "value": "on_target"}
    with db.open_ledger(account["ledger_id"]) as ledger:
        assert ledger.conn.execute("SELECT entry_date FROM nutrition_adherence").fetchone()[0] == "2026-10-25"


def test_setup_and_activity_return_complete_assigned_nutrition_state(api, monkeypatch):
    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "complete-nutrition", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "complete-nutrition", age=30, target=65)
    monkeypatch.setattr(db, "get_active_assignment_for_player", lambda _account: {"assignment_id": "active"})
    payload = {"sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
               "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False}}
    setup = client.post("/nutrition/setup", headers=headers, json=payload).json()
    for state in (setup, client.put("/nutrition/activity", headers=headers,
                                    json={"daily_activity": "on_feet"}).json()):
        assert len(state["adherence_days"]) == 7
        assert state["latest_weight"] == 70
        assert state["target_weight"] == 65
        assert state["coach_sees_adherence"] is True
