"""In-process coverage for the standalone remote load-test runner."""

import asyncio
from pathlib import Path

import httpx
import pytest
from fastapi.responses import JSONResponse

from scripts import load_test
from svc.app import create_app
from svc.dependencies import get_db


def test_load_runner_exercises_two_players_and_reports_workout_saves(fresh_store, monkeypatch):
    monkeypatch.setenv("JWT_SECRET", "test-secret-key-0123456789abcdef")
    db = fresh_store
    app = create_app()
    app.dependency_overrides[get_db] = lambda: db
    transport = httpx.ASGITransport(app=app)

    async def exercise():
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await load_test.run(client, base_url="http://testserver", players=2,
                                       duration=2, account_prefix="loadtest-script-",
                                       think_time=(0.01, 0.02))

    summary = asyncio.run(exercise())
    assert {"setup_seconds", "players_ready", "setup_errors_by_status_code",
            "total_requests", "requests_per_second", "errors_by_status_code",
            "requests_by_type", "latency_ms"} <= summary.keys()
    assert summary["players_ready"] == 2
    assert summary["requests_by_type"]["workout_save"] > 0
    assert summary["errors_by_type"].get("workout_save", {}) == {}
    assert summary["latency_ms"]["workout_save"]["median"] is not None
    assert summary["latency_ms"]["workout_save"]["p95"] is not None


def test_setup_retries_register_rate_limit_and_all_players_become_ready(fresh_store, monkeypatch):
    monkeypatch.setenv("JWT_SECRET", "test-secret-key-0123456789abcdef")
    db = fresh_store
    app = create_app()
    app.dependency_overrides[get_db] = lambda: db
    original = app.router
    retry_count = {"remaining": 2}
    from starlette.middleware.base import BaseHTTPMiddleware

    class LowRegisterLimit(BaseHTTPMiddleware):
        async def dispatch(self, request, call_next):
            if request.url.path == "/auth/register" and retry_count["remaining"]:
                retry_count["remaining"] -= 1
                return JSONResponse({"detail": "rate limited"}, status_code=429,
                                    headers={"Retry-After": "0"})
            return await call_next(request)

    app.add_middleware(LowRegisterLimit)
    transport = httpx.ASGITransport(app=app)

    async def exercise():
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await load_test.run(client, base_url="http://testserver", players=2,
                                       duration=0.1, account_prefix="loadtest-retry-",
                                       think_time=(0.001, 0.002), setup_timeout=30)

    summary = asyncio.run(exercise())
    assert summary["players_ready"] == 2
    assert summary["setup_errors_by_status_code"]["429"] == 2


def test_production_host_refusal():
    assert load_test.is_production_url("https://api.mayos.online")
    with pytest.raises(ValueError, match="production host"):
        asyncio.run(_refuse_production())


async def _refuse_production():
    await load_test.run(httpx.AsyncClient(), base_url="https://mayos-api.fly.dev", duration=1)
