"""Nutrition plan and private screening operations for a Training ledger."""

import json
from datetime import UTC, datetime
from dataclasses import dataclass


@dataclass(frozen=True)
class NutritionPlanVersion:
    goal: str
    reason: dict
    intensity: str | None
    daily_activity: str
    targets: dict
    created_at: str | None = None


@dataclass(frozen=True)
class NutritionSetup:
    sex: str
    daily_activity: str
    screening: dict
    plan: NutritionPlanVersion | None


class LedgerNutritionMixin:
    def get_nutrition_profile(self):
        row = self.conn.execute("SELECT * FROM user_profile WHERE id=1").fetchone()
        return dict(row) if row else None

    def get_nutrition_screening(self):
        return self.conn.execute(
            "SELECT answers_json, answered_at FROM nutrition_screening WHERE id=1"
        ).fetchone()

    def get_active_nutrition_plan(self):
        return self.conn.execute(
            "SELECT * FROM nutrition_plan_versions ORDER BY id DESC LIMIT 1"
        ).fetchone()

    def get_nutrition_training_days(self, fallback=0):
        row = self.conn.execute(
            "SELECT weekly_frequency FROM training_programs WHERE is_active=1 ORDER BY created_at DESC LIMIT 1"
        ).fetchone()
        return max(0, min(7, int(row[0] if row else fallback or 0)))

    def save_nutrition_setup(self, setup: NutritionSetup):
        now = datetime.now(UTC).isoformat()
        self.conn.execute(
            "UPDATE user_profile SET gender=?, sex_confirmed=1, daily_activity=?, updated_at=? WHERE id=1",
            (setup.sex, setup.daily_activity, now),
        )
        self.conn.execute(
            "INSERT INTO nutrition_screening(id, answers_json, answered_at) VALUES(1, ?, ?) "
            "ON CONFLICT(id) DO UPDATE SET answers_json=excluded.answers_json, answered_at=excluded.answered_at",
            (json.dumps(setup.screening), now),
        )
        if setup.plan is not None:
            self.save_nutrition_plan(NutritionPlanVersion(
                goal=setup.plan.goal, reason=setup.plan.reason, intensity=setup.plan.intensity,
                daily_activity=setup.plan.daily_activity, targets=setup.plan.targets, created_at=now,
            ))

    def save_nutrition_plan(self, plan: NutritionPlanVersion):
        self.conn.execute(
            "INSERT INTO nutrition_plan_versions(author, provenance, goal, goal_reason_data_json, intensity, daily_activity, targets_json, created_at) "
            "VALUES('Player', 'automatic', ?, ?, ?, ?, ?, ?)",
            (plan.goal, json.dumps(plan.reason), plan.intensity, plan.daily_activity,
             json.dumps(plan.targets), plan.created_at or datetime.now(UTC).isoformat()),
        )

    def update_nutrition_activity(self, activity):
        self.conn.execute("UPDATE user_profile SET daily_activity=?, updated_at=? WHERE id=1",
                          (activity, datetime.now(UTC).isoformat()))
