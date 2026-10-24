import sqlite3
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


def test_activity_update_keeps_schedule_local_adherence_day(api, monkeypatch):
    from datetime import date as real_date
    from service import nutrition as nutrition_service
    from svc.routers import nutrition as nutrition_router

    client, db = api
    registered = client.post("/auth/register", json={"trainee_id": "cairo-activity", "password": "correct-horse-1"}).json()
    headers = {"Authorization": f"Bearer {registered['access_token']}"}
    _seed_profile(db, "cairo-activity", age=30, target=None)
    account = db.get_active_account_by_username("cairo-activity")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.append_training_schedule(account["ledger_id"], [0, 1, 2], "Africa/Cairo", "2026-01-01", "2026-01-01T00:00:00Z")
    monkeypatch.setattr(nutrition_router, "local_today", lambda *_args, **_kwargs: real_date(2026, 10, 25))

    class UtcDate:
        @classmethod
        def today(cls):
            return real_date(2026, 10, 24)

    monkeypatch.setattr(nutrition_service, "date", UtcDate)
    client.post("/nutrition/setup", headers=headers, json={
        "sex": "male", "sex_confirmed": True, "daily_activity": "mostly_sitting",
        "screening": {"pregnant_or_breastfeeding": False, "medical_condition": False, "eating_disorder": False},
    })
    assert client.put("/nutrition/adherence", headers=headers, json={"value": "on_target"}).status_code == 200
    updated = client.put("/nutrition/activity", headers=headers, json={"daily_activity": "on_feet"})
    assert updated.status_code == 200
    assert updated.json()["today_adherence"] == "on_target"
    assert updated.json()["adherence_days"][-1] == {"date": "2026-10-25", "value": "on_target"}


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
