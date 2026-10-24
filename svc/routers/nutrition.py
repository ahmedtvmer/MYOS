"""Player Nutrition setup and read endpoints."""

import asyncio
from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request

from service import analytics, nutrition as nutrition_service
from service import nutrition_alerts
from svc.dependencies import account_id_of, get_db, get_ledger, get_verified_player
from svc.schemas import NutritionActivityIn, NutritionAdherenceIn, NutritionGoalSaveIn, NutritionPaceIn, NutritionSetupIn
from service.weight_history import player_local_date

router = APIRouter(prefix="/nutrition", tags=["nutrition"])


def _player_context(player: Any, ledger: Any, db: Any, request: Request | None = None):
    today = player_local_date(ledger, str(player))
    assigned = db.get_active_assignment_for_player(account_id_of(player)) is not None
    language = "ar" if request and request.headers.get("accept-language", "").lower().startswith("ar") else "en"
    return today, assigned, language


@router.post("/setup")
async def setup_nutrition(
    request: Request,
    body: NutritionSetupIn,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
    db: Annotated[Any, Depends(get_db)],
):
    today, assigned, language = _player_context(player, ledger, db, request)
    try:
        setup_state = await asyncio.to_thread(
            nutrition_service.setup, ledger,
            {**body.model_dump(), "screening": body.screening.model_dump(),
             "language": language},
        )
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None
    if setup_state["state"] != "incomplete":
        analytics.capture_for_request(
            request,
            analytics.AnalyticsEvent(
                account_id=account_id_of(player), event="nutrition_setup_completed",
                domain_key=f"{player}:{setup_state.get('state')}:{setup_state.get('goal', 'blocked')}",
                role="player", properties={"blocked": setup_state["state"] in ("blocked", "under_18")},
            ),
        )
    complete_state = await asyncio.to_thread(
        nutrition_service.read, ledger, language, today=today,
    )
    complete_state["coach_sees_adherence"] = assigned
    return complete_state


@router.get("")
async def read_nutrition(
    request: Request,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
    db: Annotated[Any, Depends(get_db)],
):
    today, assigned, language = _player_context(player, ledger, db, request)
    nutrition_state = await asyncio.to_thread(nutrition_service.read, ledger, language,
                                              today=today)
    nutrition_state["coach_sees_adherence"] = assigned
    return nutrition_state


@router.put("/adherence")
async def log_adherence(
    request: Request,
    body: NutritionAdherenceIn,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
    db: Annotated[Any, Depends(get_db)],
):
    today, assigned, _language = _player_context(player, ledger, db, request)
    try:
        nutrition_state, updated_at = await asyncio.to_thread(
            nutrition_service.log_adherence, ledger, body.value, today
        )
    except ValueError as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from None
    if assigned:
        assignment = db.get_active_assignment_for_player(account_id_of(player))
        if assignment is not None:
            await asyncio.to_thread(nutrition_alerts.evaluate_assignment, db, assignment,
                                    datetime.now(UTC))
    nutrition_state["coach_sees_adherence"] = assigned
    analytics.capture_for_request(request, analytics.AnalyticsEvent(
        account_id=account_id_of(player), event="nutrition_adherence_logged",
        domain_key=f"{player}:{today.isoformat()}:{body.value}:{updated_at}", role="player",
        properties={"value": body.value},
    ))
    return nutrition_state


@router.put("/activity")
async def update_activity(
    body: NutritionActivityIn,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
    db: Annotated[Any, Depends(get_db)],
):
    today, assigned, _language = _player_context(player, ledger, db)
    nutrition_state = await asyncio.to_thread(
        nutrition_service.update_activity, ledger, body.daily_activity, today
    )
    nutrition_state["coach_sees_adherence"] = assigned
    return nutrition_state


@router.post("/preview")
async def preview_nutrition(body: NutritionPaceIn, player: Annotated[Any, Depends(get_verified_player)],
                            ledger: Annotated[Any, Depends(get_ledger)],
                            db: Annotated[Any, Depends(get_db)]):
    today, _assigned, _language = _player_context(player, ledger, db)
    return await asyncio.to_thread(nutrition_service.preview, ledger, body.goal, body.intensity, today)


@router.put("/goal")
async def save_nutrition_goal(request: Request, body: NutritionGoalSaveIn,
                              player: Annotated[Any, Depends(get_verified_player)],
                              ledger: Annotated[Any, Depends(get_ledger)],
                              db: Annotated[Any, Depends(get_db)]):
    today, assigned, _language = _player_context(player, ledger, db, request)
    previous_plan = await asyncio.to_thread(ledger.get_active_nutrition_plan)
    try:
        result = await asyncio.to_thread(nutrition_service.save_goal, ledger, body.goal,
                                         body.intensity, today,
                                         body.screening.model_dump() if body.screening else None)
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None
    result["coach_sees_adherence"] = assigned
    if result.get("state") == "ready":
        active_plan = await asyncio.to_thread(ledger.get_active_nutrition_plan)
        if previous_plan is None or active_plan["id"] != previous_plan["id"]:
            analytics.capture_for_request(request, analytics.AnalyticsEvent(
                account_id=account_id_of(player), event="nutrition_goal_saved",
                domain_key=f"{player}:{active_plan['id']}", role="player",
                properties={"goal": result["goal"], "intensity": result.get("intensity") or "none",
                            "floor_applied": result["targets"]["floor_applied"]}))
    return result


@router.post("/goal-offer/dismiss")
async def dismiss_goal_offer(player: Annotated[Any, Depends(get_verified_player)],
                            ledger: Annotated[Any, Depends(get_ledger)],
                            db: Annotated[Any, Depends(get_db)]):
    today, assigned, _language = _player_context(player, ledger, db)
    result = await asyncio.to_thread(nutrition_service.dismiss_goal_offer, ledger, today)
    result["coach_sees_adherence"] = assigned
    return result
