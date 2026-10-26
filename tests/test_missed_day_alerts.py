"""Missed expected-day alert tests (ticket #31, ADR 030).

Exercises the deterministic, idempotent evaluation and sweep against real
temporary SQLite catalogs and ledgers: alert creation on a two-day streak, the
coach notice, retry safety, streak extension, system auto-resolution when the
streak breaks, the catalog-side roster summary, and sweep resilience.
"""

import sqlite3
import uuid
from datetime import UTC, date, datetime, timedelta
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from agent.ProgramState import ProgramDaySchema, ProgramExerciseSchema
from database.database_manager import DatabaseManager
from database.ledger.nutrition import NutritionPlanVersion, NutritionSetup
from service import alert_sweep
from service import coach as coach_service
from service import missed_day_alerts as alerts_service
from service import nutrition_alerts
from service import workouts as workouts_service
from service.weight_history import player_local_date
from svc.app import create_app
from svc.dependencies import get_db

TEST_JWT_SECRET = "test-secret-key-0123456789abcdef"
ALL_DAYS = [1, 2, 3, 4, 5, 6, 7]


@pytest.fixture
def api(tmp_path: Path, monkeypatch):
    monkeypatch.setenv("SKIP_LLM_LOAD", "true")
    monkeypatch.setenv("TESTING", "1")
    monkeypatch.setenv("JWT_SECRET", TEST_JWT_SECRET)
    from svc.rate_limit import limiter

    limiter._storage.reset()
    catalog_path = tmp_path / "catalog.db"
    cat_conn = sqlite3.connect(catalog_path)
    cat_conn.execute(
        "CREATE TABLE exercises (id TEXT PRIMARY KEY, name TEXT, body_part TEXT, target_muscle TEXT,"
        " equipment TEXT, image_path TEXT, gif_path TEXT, instructions TEXT);"
    )
    cat_conn.execute("CREATE TABLE exercise_secondary_muscles (exercise_id TEXT, muscle TEXT);")
    cat_conn.execute(
        "INSERT INTO exercises (id, name, body_part, target_muscle) VALUES"
        " ('sq', 'Squat', 'Upper Legs', 'Quads'), ('bp', 'Bench Press', 'Chest', 'Chest');"
    )
    cat_conn.commit()
    cat_conn.close()
    db = DatabaseManager(
        catalog_path=catalog_path,
        ledgers_dir=tmp_path / "users",
        backups_dir=tmp_path / "backups",
        default_ledger_id="bootstrap",
    )
    app = create_app()
    app.dependency_overrides[get_db] = lambda: db
    try:
        with TestClient(app) as client:
            yield client, db
    finally:
        if db.ledger_conn is not None:
            db.ledger_conn.close()
        db.catalog_conn.close()


def _register(client, username, password="correct-horse-1"):
    resp = client.post("/auth/register", json={"trainee_id": username, "password": password})
    assert resp.status_code == 201, resp.text
    return resp.json()


def _authed(token):
    return {"Authorization": f"Bearer {token}"}


def _make_coach(client, db, username, capacity=10):
    registered = _register(client, username)
    headers = _authed(registered["access_token"])
    issued = coach_service.issue_coach_invite(db, username, actor="cli")
    assert issued["ok"], issued
    assert client.post("/coach/invite/redeem", headers=headers, json={"token": issued["token"]}).status_code == 200
    assert (
        client.put(
            "/coach/profile",
            headers=headers,
            json={"display_name": f"Coach {username}", "bio": "b", "specialization": "s", "capacity": capacity},
        ).status_code
        == 200
    )
    return headers


def _assign(api, coach_name="coach", player_name="p1"):
    client, db = api
    coach_headers = _make_coach(client, db, coach_name, capacity=5)
    token = client.post("/coach/assignments/invites", headers=coach_headers).json()["token"]
    player = _register(client, player_name)
    player_headers = _authed(player["access_token"])
    redeemed = client.post(
        "/assignments/invites/redeem", headers=player_headers, json={"token": token, "consent": True}
    )
    assert redeemed.status_code == 200, redeemed.text
    assignment_id = redeemed.json()["assignment"]["assignment_id"]
    coach_account_id = db.get_active_account_by_username(coach_name)["account_id"]
    return coach_headers, player_headers, assignment_id, coach_account_id


def _backdate_assignment(db, assignment_id, started_at):
    db.catalog_conn.execute(
        "UPDATE assignments SET started_at = ? WHERE assignment_id = ?",
        (started_at.isoformat(), assignment_id),
    )
    db.catalog_conn.commit()


def _seed_schedule(db, player, weekdays, effective_from):
    db.switch_user(player)
    db.ledger.append_training_schedule(
        player, weekdays, "UTC", effective_from.isoformat(), "2026-01-01T00:00:00+00:00"
    )


def _seed_session(db, player, session_date):
    db.switch_user(player)
    now_iso = session_date.isoformat() + "T10:00:00+00:00"
    db.ledger.log_workout_session(
        uuid.uuid4().hex, session_date.isoformat(), "Full A", now_iso, now_iso, 4, ""
    )


def _notices(db, coach_account_id, kind=alerts_service.MISSED_DAY_KIND):
    return [
        notice
        for notice in db.list_assignment_notices(coach_account_id, limit=50)
        if notice["kind"] == kind
    ]


def test_nutrition_patterns_are_deduplicated_and_resolve_on_a_good_day(api):
    _, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    assignment = db.get_active_assignment_for_coach(coach_account_id, assignment_id)
    player = db.get_account(assignment["player_account_id"])
    now = datetime(2026, 10, 25, 12, tzinfo=UTC)
    today = now.date()
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.save_nutrition_plan(NutritionPlanVersion(
            "maintain", {"code": "default"}, None, "mostly_sitting", {"calories": 2000},
            created_at=(today - timedelta(days=10)).isoformat() + "T00:00:00+00:00",
        ))
        for offset in (2, 1, 0):
            ledger.upsert_nutrition_adherence((today - timedelta(days=offset)).isoformat(), "off")

    assert nutrition_alerts.evaluate_assignment(db, assignment, now)["alerts_created"] == 1
    assert nutrition_alerts.evaluate_assignment(db, assignment, now)["alerts_created"] == 0
    off_alerts = [row for row in db.list_coach_alerts(coach_account_id, ("new",))
                  if row["kind"] == nutrition_alerts.OFF_KIND]
    assert len(off_alerts) == 1
    assert off_alerts[0]["details"]["episode_start_date"] == (today - timedelta(days=2)).isoformat()
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.upsert_nutrition_adherence(today.isoformat(), "on_target")
    nutrition_alerts.evaluate_assignment(db, assignment, now)
    resolved = [row for row in db.list_coach_alerts(coach_account_id, ("resolved",))
                if row["kind"] == nutrition_alerts.OFF_KIND]
    assert len(resolved) == 1

    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.conn.execute("DELETE FROM nutrition_adherence")
        ledger.conn.commit()
    assert nutrition_alerts.evaluate_assignment(db, assignment, now)["alerts_created"] == 1
    assert nutrition_alerts.evaluate_assignment(db, assignment, now)["alerts_created"] == 0
    unlogged_alerts = [row for row in db.list_coach_alerts(coach_account_id, ("new",))
                       if row["kind"] == nutrition_alerts.UNLOGGED_KIND]
    assert len(unlogged_alerts) == 1
    assert unlogged_alerts[0]["details"]["episode_start_date"] == (today - timedelta(days=9)).isoformat()


def test_fiber_water_targets_do_not_change_adherence_or_create_alerts(api):
    client, db = api
    _, player_headers, assignment_id, coach_account_id = _assign(api)
    assignment = db.get_active_assignment_for_coach(coach_account_id, assignment_id)
    player = db.get_account(assignment["player_account_id"])
    with db.open_ledger(player["ledger_id"]) as ledger:
        today = player_local_date(ledger, str(player["ledger_id"]))
        ledger.save_nutrition_plan(NutritionPlanVersion(
            "maintain", {"code": "default"}, None, "mostly_sitting",
            {"calories": 2000, "protein_g": 100, "carbs_g": 250, "fat_g": 67,
             "fiber_g": 80, "fiber_g_source": "coach", "water_ml": 6000,
             "water_ml_source": "coach", "training_day_water_ml": 6000,
             "training_day_water_ml_source": "coach"},
            created_at=(today - timedelta(days=10)).isoformat() + "T00:00:00+00:00",
        ))
        for offset in range(10, -1, -1):
            ledger.upsert_nutrition_adherence((today - timedelta(days=offset)).isoformat(), "on_target")
    response = client.get("/nutrition", headers=player_headers)
    assert response.status_code == 200
    assert response.json()["today_adherence"] == "on_target"
    assert nutrition_alerts.evaluate_assignment(
        db, assignment, datetime(2026, 10, 25, 12, tzinfo=UTC)
    )["alerts_created"] == 0
    assert not [row for row in db.list_coach_alerts(coach_account_id, ("new",))
                if row["kind"] in (nutrition_alerts.OFF_KIND, nutrition_alerts.UNLOGGED_KIND)]


def test_unlogged_episode_ignores_the_unfinished_player_local_day(api):
    _, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    assignment = db.get_active_assignment_for_coach(coach_account_id, assignment_id)
    player = db.get_account(assignment["player_account_id"])
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.append_training_schedule(
            player["ledger_id"], ALL_DAYS, "Africa/Cairo", "2026-10-01",
            "2026-10-01T00:00:00+00:00",
        )
        ledger.save_nutrition_plan(NutritionPlanVersion(
            "maintain", {"code": "default"}, None, "mostly_sitting", {"calories": 2000},
            created_at="2026-10-23T20:55:00+00:00",
        ))
    after_one_day = datetime(2026, 10, 24, 21, 1, tzinfo=UTC)
    assert nutrition_alerts.evaluate_assignment(db, assignment, after_one_day)["alerts_created"] == 0
    assert nutrition_alerts.evaluate_assignment(
        db, assignment, datetime(2026, 10, 25, 21, 1, tzinfo=UTC)
    )["alerts_created"] == 0
    assert nutrition_alerts.evaluate_assignment(
        db, assignment, datetime(2026, 10, 26, 21, 1, tzinfo=UTC)
    )["alerts_created"] == 1


def test_off_episode_sweep_uses_latest_logged_day_when_today_is_unlogged(api):
    _, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    assignment = db.get_active_assignment_for_coach(coach_account_id, assignment_id)
    player = db.get_account(assignment["player_account_id"])
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.save_nutrition_plan(NutritionPlanVersion(
            "maintain", {"code": "default"}, None, "mostly_sitting", {"calories": 2000},
            created_at="2026-10-20T00:00:00+00:00",
        ))
        for day in (21, 22, 23):
            ledger.upsert_nutrition_adherence(f"2026-10-{day}", "off")
    result = nutrition_alerts.evaluate_assignment(
        db, assignment, datetime(2026, 10, 24, 12, tzinfo=UTC)
    )
    assert result["alerts_created"] == 1
    alert = next(row for row in db.list_coach_alerts(coach_account_id, ("new",))
                 if row["kind"] == nutrition_alerts.OFF_KIND)
    assert alert["details"]["episode_start_date"] == "2026-10-21"


def test_positive_rescreen_resolves_unlogged_alert_even_with_plan_row(api):
    _, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    assignment = db.get_active_assignment_for_coach(coach_account_id, assignment_id)
    player = db.get_account(assignment["player_account_id"])
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.save_nutrition_plan(NutritionPlanVersion(
            "maintain", {"code": "default"}, None, "mostly_sitting", {"calories": 2000},
            created_at="2026-10-19T00:00:00+00:00",
        ))
    now = datetime(2026, 10, 25, 12, tzinfo=UTC)
    assert nutrition_alerts.evaluate_assignment(db, assignment, now)["alerts_created"] == 1
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.save_nutrition_setup(NutritionSetup(
            "male", "mostly_sitting",
            {"pregnant_or_breastfeeding": False, "medical_condition": True,
             "eating_disorder": False}, None,
        ))
        assert ledger.get_active_nutrition_plan() is not None
    changed = nutrition_alerts.evaluate_assignment(db, assignment, now)
    assert changed["alerts_resolved"] == 1
    assert not [row for row in db.list_coach_alerts(coach_account_id, ("new", "acknowledged"))
                if row["kind"] == nutrition_alerts.UNLOGGED_KIND]


def test_adherence_write_succeeds_when_alert_evaluation_fails(api, monkeypatch):
    client, db = api
    _, player_headers, _, _ = _assign(api)
    account = db.get_active_account_by_username("p1")
    with db.open_ledger(account["ledger_id"]) as ledger:
        ledger.upsert_player_profile({
            "gender": "male", "age": 30, "height_cm": 175, "weight_kg": 75,
            "current_goal": "get stronger", "weekly_frequency": 3,
        })
        ledger.save_nutrition_setup(NutritionSetup(
            "male", "mostly_sitting",
            {"pregnant_or_breastfeeding": False, "medical_condition": False,
             "eating_disorder": False},
            NutritionPlanVersion("maintain", {"code": "default"}, None,
                                 "mostly_sitting", {"calories": 2000}),
        ))

    def fail_evaluation(*_args, **_kwargs):
        raise RuntimeError("catalog unavailable")

    from svc.routers import nutrition as nutrition_router
    monkeypatch.setattr(nutrition_router.nutrition_alerts, "evaluate_assignment", fail_evaluation)
    response = client.put("/nutrition/adherence", headers=player_headers,
                          json={"value": "on_target"})

    assert response.status_code == 200, response.text
    assert response.json()["today_adherence"] == "on_target"


def test_off_does_not_close_an_unlogged_episode(api):
    _, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    assignment = db.get_active_assignment_for_coach(coach_account_id, assignment_id)
    player = db.get_account(assignment["player_account_id"])
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.save_nutrition_plan(NutritionPlanVersion(
            "maintain", {"code": "default"}, None, "mostly_sitting", {"calories": 2000},
            created_at="2026-10-19T00:00:00+00:00",
        ))
    nutrition_alerts.evaluate_assignment(db, assignment, datetime(2026, 10, 23, 12, tzinfo=UTC))
    initial = [row for row in db.list_coach_alerts(coach_account_id, ("new",))
               if row["kind"] == nutrition_alerts.UNLOGGED_KIND]
    assert len(initial) == 1

    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.upsert_nutrition_adherence("2026-10-23", "off")
    nutrition_alerts.evaluate_assignment(db, assignment, datetime(2026, 10, 23, 12, tzinfo=UTC))
    unlogged = [row for row in db.list_coach_alerts(coach_account_id, ("new",))
                if row["kind"] == nutrition_alerts.UNLOGGED_KIND]
    assert len(unlogged) == 1
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.upsert_nutrition_adherence("2026-10-24", "roughly")
    nutrition_alerts.evaluate_assignment(db, assignment, datetime(2026, 10, 24, 12, tzinfo=UTC))
    resolved = [row for row in db.list_coach_alerts(coach_account_id, ("resolved",))
                if row["kind"] == nutrition_alerts.UNLOGGED_KIND]
    assert len(resolved) == 1


def test_missing_day_does_not_restart_an_off_episode(api):
    _, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    assignment = db.get_active_assignment_for_coach(coach_account_id, assignment_id)
    player = db.get_account(assignment["player_account_id"])
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.save_nutrition_plan(NutritionPlanVersion(
            "maintain", {"code": "default"}, None, "mostly_sitting", {"calories": 2000},
            created_at="2026-10-19T00:00:00+00:00",
        ))
        for day in (20, 21, 22):
            ledger.upsert_nutrition_adherence(f"2026-10-{day}", "off")
    nutrition_alerts.evaluate_assignment(db, assignment, datetime(2026, 10, 22, 12, tzinfo=UTC))
    nutrition_alerts.evaluate_assignment(db, assignment, datetime(2026, 10, 23, 12, tzinfo=UTC))
    with db.open_ledger(player["ledger_id"]) as ledger:
        for day in (24, 25, 26):
            ledger.upsert_nutrition_adherence(f"2026-10-{day}", "off")
    nutrition_alerts.evaluate_assignment(db, assignment, datetime(2026, 10, 26, 12, tzinfo=UTC))
    off_alerts = [row for row in db.list_coach_alerts(coach_account_id, ("new",))
                  if row["kind"] == nutrition_alerts.OFF_KIND]
    assert len(off_alerts) == 1
    assert off_alerts[0]["details"]["episode_start_date"] == "2026-10-20"


def test_long_unlogged_episode_keeps_its_original_dedupe_start(api):
    _, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    assignment = db.get_active_assignment_for_coach(coach_account_id, assignment_id)
    player = db.get_account(assignment["player_account_id"])
    with db.open_ledger(player["ledger_id"]) as ledger:
        ledger.save_nutrition_plan(NutritionPlanVersion(
            "maintain", {"code": "default"}, None, "mostly_sitting", {"calories": 2000},
            created_at="2025-10-24T00:00:00+00:00",
        ))
    nutrition_alerts.evaluate_assignment(db, assignment, datetime(2026, 10, 25, 12, tzinfo=UTC))
    nutrition_alerts.evaluate_assignment(db, assignment, datetime(2026, 10, 26, 12, tzinfo=UTC))
    open_alerts = [row for row in db.list_coach_alerts(coach_account_id, ("new",))
                   if row["kind"] == nutrition_alerts.UNLOGGED_KIND]
    assert len(open_alerts) == 1
    assert open_alerts[0]["details"]["episode_start_date"] == "2025-10-25"


def test_assignment_end_resolves_both_nutrition_alert_kinds(api):
    client, db = api
    _, player_headers, assignment_id, coach_account_id = _assign(api)
    alert_ids = []
    for kind in (nutrition_alerts.OFF_KIND, nutrition_alerts.UNLOGGED_KIND):
        inserted = db.insert_coach_alert(
            uuid.uuid4().hex, assignment_id, coach_account_id,
            db.get_active_assignment_for_coach(coach_account_id, assignment_id)["player_account_id"],
            kind, "2026-10-20", {"episode_start_date": "2026-10-20"},
            datetime.now(UTC).isoformat(),
        )
        alert_id = inserted["alert"]["alert_id"]
        alert_ids.append(alert_id)
        if kind == nutrition_alerts.UNLOGGED_KIND:
            db.acknowledge_coach_alert_transition(
                alert_id, coach_account_id, datetime.now(UTC).isoformat()
            )

    ended = client.post("/assignments/me/end", headers=player_headers)

    assert ended.status_code == 200
    ended_alerts = [db.get_coach_alert(alert_id) for alert_id in alert_ids]
    assert all(alert is not None and alert["state"] == "resolved" for alert in ended_alerts)


def test_adherence_write_sweep_and_roster_api_surface_nutrition_alerts(api):
    client, db = api
    coach_headers, player_headers, off_assignment_id, coach_account_id = _assign(
        api, player_name="z_off"
    )
    today = datetime.now(UTC).date()
    invite = client.post("/coach/assignments/invites", headers=coach_headers).json()["token"]
    unlogged_player = _register(client, "y_unlogged")
    unlogged_headers = _authed(unlogged_player["access_token"])
    unlogged_assignment_id = client.post(
        "/assignments/invites/redeem", headers=unlogged_headers,
        json={"token": invite, "consent": True},
    ).json()["assignment"]["assignment_id"]
    invite = client.post("/coach/assignments/invites", headers=coach_headers).json()["token"]
    quiet_player = _register(client, "a_quiet")
    client.post("/assignments/invites/redeem", headers=_authed(quiet_player["access_token"]),
                json={"token": invite, "consent": True})

    for username, values in (("z_off", ("off", "off")), ("y_unlogged", ())):
        account = db.get_active_account_by_username(username)
        with db.open_ledger(account["ledger_id"]) as ledger:
            ledger.save_nutrition_plan(NutritionPlanVersion(
                "maintain", {"code": "default"}, None, "mostly_sitting", {"calories": 2000},
                created_at=(today - timedelta(days=5)).isoformat() + "T00:00:00+00:00",
            ))
            for offset, value in enumerate(values, start=1):
                ledger.upsert_nutrition_adherence((today - timedelta(days=offset)).isoformat(), value)

    write = client.put("/nutrition/adherence", headers=player_headers, json={"value": "off"})
    assert write.status_code == 200
    written_alert = [row for row in db.list_coach_alerts(coach_account_id, ("new",))
                     if row["kind"] == nutrition_alerts.OFF_KIND]
    assert len(written_alert) == 1

    alert_sweep.run_sweep(db, now=datetime.now(UTC))
    swept_alert = [row for row in db.list_coach_alerts(coach_account_id, ("new",))
                   if row["kind"] == nutrition_alerts.UNLOGGED_KIND]
    assert len(swept_alert) == 1
    roster = client.get("/coach/assignments", headers=coach_headers).json()["assignments"]
    assert {row["assignment_id"] for row in roster[:2]} == {
        off_assignment_id, unlogged_assignment_id,
    }
    assert roster[2]["player_username"] == "a_quiet"


def test_sweep_creates_one_alert_and_notice_for_a_two_day_streak(api):
    client, db = api
    coach_headers, _, assignment_id, coach_account_id = _assign(api)
    now = datetime.now(UTC)
    started = now - timedelta(days=10)
    _backdate_assignment(db, assignment_id, started)
    _seed_schedule(db, "p1", ALL_DAYS, started.date() - timedelta(days=1))

    counts = alert_sweep.run_sweep(db, now=now)

    assert counts == {
        "evaluated": 1,
        "skipped": 0,
        "alerts_created": 1,
        "alerts_resolved": 0,
        "follow_ups_created": 1,
        "spend_alert_fired": 0,
        "errors": 0,
    }
    alerts = [
        alert
        for alert in db.list_coach_alerts(coach_account_id, ("new",))
        if alert["kind"] == alerts_service.MISSED_DAY_KIND
    ]
    assert len(alerts) == 1
    alert = alerts[0]
    assert alert["kind"] == alerts_service.MISSED_DAY_KIND
    assert alert["assignment_id"] == assignment_id
    assert alert["details"]["streak_start_date"] == started.date().isoformat()
    assert alert["details"]["missed_count"] == 9
    assert alert["state"] == "new"
    public_alert = next(
        row
        for row in client.get("/coach/alerts", headers=coach_headers).json()["alerts"]
        if row["kind"] == alerts_service.MISSED_DAY_KIND
    )
    assert public_alert["message_code"] == "coach_alert.missed_expected_days.v1"
    assert public_alert["message_params"] == {
        "count": 9,
        "start_date": public_alert["streak_start_date"],
        "end_date": public_alert["last_missed_date"],
    }
    assert public_alert["message_fallback"].startswith("Missed 9 expected training days (")
    notices = _notices(db, coach_account_id)
    assert len(notices) == 1
    assert notices[0]["message_code"] == "assignment_notice.missed_expected_days.v1"
    assert notices[0]["message_params"] == {
        "player_name": "p1",
        "count": 9,
        "start_date": alert["details"]["streak_start_date"],
        "end_date": public_alert["last_missed_date"],
    }
    summary = db.get_roster_alert_badges(coach_account_id)[assignment_id]
    assert summary["current_missed_streak"] == 9
    assert summary["alerts_acknowledged"] == 0
    # The badge count spans every alert kind, so the due follow-up is counted too.
    assert summary["alerts_new"] == 2


def test_sweep_is_idempotent_and_does_not_duplicate_the_notice(api, recording_analytics):
    client, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    now = datetime.now(UTC)
    started = now - timedelta(days=10)
    _backdate_assignment(db, assignment_id, started)
    _seed_schedule(db, "p1", ALL_DAYS, started.date() - timedelta(days=1))

    first = alert_sweep.run_sweep(db, now=now)
    alert_id = [
        alert
        for alert in db.list_coach_alerts(coach_account_id, ("new",))
        if alert["kind"] == alerts_service.MISSED_DAY_KIND
    ][0]["alert_id"]
    second = alert_sweep.run_sweep(db, now=now)

    assert first["alerts_created"] == 1
    assert second["alerts_created"] == 0
    assert first["follow_ups_created"] == 1
    assert second["follow_ups_created"] == 0
    alerts = [
        alert
        for alert in db.list_coach_alerts(coach_account_id, ("new", "acknowledged", "resolved"))
        if alert["kind"] == alerts_service.MISSED_DAY_KIND
    ]
    assert len(alerts) == 1
    assert alerts[0]["alert_id"] == alert_id
    assert len(_notices(db, coach_account_id)) == 1
    created_events = [
        event
        for event in recording_analytics.events
        if event["event"] == "coach_alert_created"
        and event["properties"]["alert_kind"] == "missed_expected_days"
    ]
    assert len(created_events) == 1
    assert created_events[0]["distinct_id"] == coach_account_id


def test_longer_streak_extends_the_same_alert(api):
    client, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    now = datetime.now(UTC)
    started = now - timedelta(days=3)
    _backdate_assignment(db, assignment_id, started)
    _seed_schedule(db, "p1", ALL_DAYS, started.date() - timedelta(days=1))

    alert_sweep.run_sweep(db, now=now)
    first = [
        alert
        for alert in db.list_coach_alerts(coach_account_id, ("new",))
        if alert["kind"] == alerts_service.MISSED_DAY_KIND
    ][0]
    assert first["details"]["missed_count"] == 2

    alert_sweep.run_sweep(db, now=now + timedelta(days=1))
    alerts = [
        alert
        for alert in db.list_coach_alerts(coach_account_id, ("new", "acknowledged", "resolved"))
        if alert["kind"] == alerts_service.MISSED_DAY_KIND
    ]
    assert len(alerts) == 1
    assert alerts[0]["alert_id"] == first["alert_id"]
    assert alerts[0]["details"]["missed_count"] == 3
    assert alerts[0]["details"]["last_missed_date"] == (now.date() - timedelta(days=1)).isoformat()
    assert len(_notices(db, coach_account_id)) == 1


def test_streak_breaks_and_the_open_alert_auto_resolves(api):
    client, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    now = datetime.now(UTC)
    started = now - timedelta(days=3)
    _backdate_assignment(db, assignment_id, started)
    _seed_schedule(db, "p1", ALL_DAYS, started.date() - timedelta(days=1))

    alert_sweep.run_sweep(db, now=now)
    assert len(db.list_coach_alerts(coach_account_id, ("new",))) == 1

    _seed_session(db, "p1", now.date() - timedelta(days=1))
    counts = alert_sweep.run_sweep(db, now=now)

    assert counts["alerts_resolved"] == 1
    open_alerts = db.list_coach_alerts(coach_account_id, ("new", "acknowledged"))
    assert open_alerts == []
    resolved = db.list_coach_alerts(coach_account_id, ("resolved",))
    assert len(resolved) == 1
    assert resolved[0]["resolved_by"] == "system"
    assert resolved[0]["resolved_at"] is not None
    assert db.get_roster_alert_badges(coach_account_id)[assignment_id]["current_missed_streak"] == 0


def test_commit_hook_resolves_alert_when_an_expected_day_is_satisfied(api):
    client, db = api
    _, _, assignment_id, coach_account_id = _assign(api)
    now = datetime.now(UTC)
    started = now - timedelta(days=3)
    _backdate_assignment(db, assignment_id, started)
    _seed_schedule(db, "p1", ALL_DAYS, started.date() - timedelta(days=1))
    assert alert_sweep.run_sweep(db, now=now)["alerts_created"] == 1
    assert len(db.list_coach_alerts(coach_account_id, ("new",))) == 1

    db.switch_user("p1")
    db.ledger.upsert_player_profile({"current_goal": "Strength"})
    player_account_id = db.get_active_account_by_username("p1")["account_id"]
    day_plan = ProgramDaySchema(
        day_name="Full A",
        day_order=1,
        exercises=[
            ProgramExerciseSchema(exercise_id="sq", exercise_name="Squat", target_reps_min=5, target_reps_max=8),
            ProgramExerciseSchema(exercise_id="bp", exercise_name="Bench Press", target_reps_min=5, target_reps_max=8),
            ProgramExerciseSchema(exercise_id="row", exercise_name="Row", target_reps_min=5, target_reps_max=8),
        ],
    )

    # A workout today satisfies an expected day; the commit hook resolves at once.
    workouts_service.commit_session(
        db,
        "p1",
        day_plan,
        readiness=4,
        session_notes="",
        sets_by_exercise=[],
        account_id=player_account_id,
    )

    open_alerts = db.list_coach_alerts(coach_account_id, ("new", "acknowledged"))
    assert open_alerts == []
    resolved = db.list_coach_alerts(coach_account_id, ("resolved",))
    assert len(resolved) == 1
    assert resolved[0]["resolved_by"] == "system"


def test_commit_session_defaults_to_the_player_local_today(api, monkeypatch):
    client, db = api
    _register(client, "p1")
    db.switch_user("p1")
    db.ledger.append_training_schedule(
        "p1", ALL_DAYS, "Pacific/Kiritimati", "2026-01-01", "2026-01-01T00:00:00+00:00"
    )
    db.ledger.upsert_player_profile({"current_goal": "Strength"})
    # UTC 2026-09-20T12:00Z is already 2026-09-21 for a UTC+14 player.
    local_day = date(2026, 9, 21)
    monkeypatch.setattr(workouts_service, "local_today", lambda db_arg, player, **kwargs: local_day)
    day_plan = ProgramDaySchema(
        day_name="Full A",
        day_order=1,
        exercises=[
            ProgramExerciseSchema(exercise_id="sq", exercise_name="Squat", target_reps_min=5, target_reps_max=8),
            ProgramExerciseSchema(exercise_id="bp", exercise_name="Bench Press", target_reps_min=5, target_reps_max=8),
            ProgramExerciseSchema(exercise_id="row", exercise_name="Row", target_reps_min=5, target_reps_max=8),
        ],
    )

    result = workouts_service.commit_session(
        db, "p1", day_plan, readiness=4, session_notes="", sets_by_exercise=[]
    )

    row = db.conn.execute(
        "SELECT session_date FROM workout_sessions WHERE id = ?", (result.body["session_id"],)
    ).fetchone()
    assert row[0] == local_day.isoformat()


def test_sweep_skips_a_player_without_a_ledger_and_never_creates_one(api):
    client, db = api
    now = datetime.now(UTC)
    account_id = db.create_account("ghost")
    assert account_id is not None
    db.catalog_conn.execute(
        "INSERT INTO assignments"
        " (assignment_id, coach_account_id, player_account_id, status, started_at, ended_at, ended_by)"
        " VALUES (?, ?, ?, 'active', ?, NULL, NULL)",
        ("ghost-assignment", "coach-x", account_id, (now - timedelta(days=5)).isoformat()),
    )
    db.catalog_conn.commit()
    assert not db.ledger_exists("ghost")

    counts = alert_sweep.run_sweep(db, now=now)

    assert counts["skipped"] == 1
    assert counts["evaluated"] == 0
    assert not db.ledger_exists("ghost")


def test_sweep_opens_no_thread_local_ledger(api):
    """Phase B1: the sweep uses explicit ledger handles, not the thread-local mount."""
    client, db = api
    _, _, assignment_id, _ = _assign(api)
    now = datetime.now(UTC)
    started = now - timedelta(days=3)
    _backdate_assignment(db, assignment_id, started)
    _seed_schedule(db, "p1", ALL_DAYS, started.date() - timedelta(days=1))

    mounted_before = db.ledger_conn
    active_before = db._test_ledger_id
    alert_sweep.run_sweep(db, now=now)

    # The sweep never mounts (or unmounts) a player ledger on the thread.
    assert db.ledger_conn is mounted_before
    assert db._test_ledger_id == active_before


def test_sweep_opens_no_thread_local_ledger_even_when_evaluation_raises(api, monkeypatch):
    client, db = api
    _, _, assignment_id, _ = _assign(api)
    now = datetime.now(UTC)
    started = now - timedelta(days=3)
    _backdate_assignment(db, assignment_id, started)
    _seed_schedule(db, "p1", ALL_DAYS, started.date() - timedelta(days=1))

    def boom(db_arg, assignment, now=None):
        raise RuntimeError("boom")

    mounted_before = db.ledger_conn
    monkeypatch.setattr(alert_sweep, "evaluate_assignment", boom)
    counts = alert_sweep.run_sweep(db, now=now)

    assert counts["errors"] == 1
    assert db.ledger_conn is mounted_before


def test_sweep_continues_after_one_player_failure(api, monkeypatch):
    client, db = api
    _, _, first_assignment, _ = _assign(api, coach_name="coach1", player_name="p1")
    _, _, second_assignment, _ = _assign(api, coach_name="coach2", player_name="p2")
    now = datetime.now(UTC)
    started = now - timedelta(days=5)
    for assignment_id, player in ((first_assignment, "p1"), (second_assignment, "p2")):
        _backdate_assignment(db, assignment_id, started)
        _seed_schedule(db, player, ALL_DAYS, started.date() - timedelta(days=1))

    real_evaluate = alerts_service.evaluate_assignment

    def flaky(db_arg, assignment, now=None):
        if assignment["assignment_id"] == first_assignment:
            raise RuntimeError("boom")
        return real_evaluate(db_arg, assignment, now=now)

    monkeypatch.setattr(alert_sweep, "evaluate_assignment", flaky)
    counts = alert_sweep.run_sweep(db, now=now)

    assert counts["errors"] == 1
    assert counts["evaluated"] == 1
    assert len(db.list_coach_alerts(db.get_active_account_by_username("coach2")["account_id"], ("new",))) == 1


def test_sweep_closes_every_handle_it_opens_even_when_evaluation_raises(api, monkeypatch):
    """Every handle the sweep opens is closed, including when one player raises (defect #5)."""
    client, db = api
    _, _, first_assignment, _ = _assign(api, coach_name="coach1", player_name="p1")
    _, _, second_assignment, _ = _assign(api, coach_name="coach2", player_name="p2")
    now = datetime.now(UTC)
    started = now - timedelta(days=5)
    for assignment_id, player in ((first_assignment, "p1"), (second_assignment, "p2")):
        _backdate_assignment(db, assignment_id, started)
        _seed_schedule(db, player, ALL_DAYS, started.date() - timedelta(days=1))

    opened = []
    real_open = db.open_ledger

    def tracking_open(ledger_id):
        handle = real_open(ledger_id)
        opened.append(handle)
        return handle

    monkeypatch.setattr(db, "open_ledger", tracking_open)

    # p2 raises *after* its handle is opened, so the failure unwinds through the
    # with-block that owns the handle.
    from database.ledger.schedule import LedgerScheduleMixin

    real_pauses = LedgerScheduleMixin.list_training_pauses

    def flaky_pauses(self, ledger_id):
        if self.ledger_id == "p2":
            raise RuntimeError("boom")
        return real_pauses(self, ledger_id)

    monkeypatch.setattr(LedgerScheduleMixin, "list_training_pauses", flaky_pauses)

    counts = alert_sweep.run_sweep(db, now=now)

    def is_open(handle):
        try:
            handle.conn
        except RuntimeError:
            return False
        return True

    assert counts["errors"] >= 1
    assert opened
    assert all(not is_open(handle) for handle in opened)
