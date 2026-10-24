"""Player Nutrition setup and read endpoints."""

import asyncio
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request

from service import analytics, nutrition as nutrition_service
from svc.dependencies import account_id_of, get_db, get_ledger, get_verified_player
from svc.schemas import NutritionActivityIn, NutritionAdherenceIn, NutritionSetupIn
from service.schedule import local_today

router = APIRouter(prefix="/nutrition", tags=["nutrition"])


@router.post("/setup")
async def setup_nutrition(
    request: Request,
    body: NutritionSetupIn,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
    db: Annotated[Any, Depends(get_db)],
):
    try:
        setup_state = await asyncio.to_thread(
            nutrition_service.setup, ledger,
            {**body.model_dump(), "screening": body.screening.model_dump(),
             "language": "ar" if request.headers.get("accept-language", "").lower().startswith("ar") else "en"},
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
    today = local_today(db, str(player), ledger=ledger)
    complete_state = await asyncio.to_thread(
        nutrition_service.read, ledger,
        "ar" if request.headers.get("accept-language", "").lower().startswith("ar") else "en",
        today=today,
    )
    complete_state["coach_sees_adherence"] = (
        db.get_active_assignment_for_player(account_id_of(player)) is not None
    )
    return complete_state


@router.get("")
async def read_nutrition(
    request: Request,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
    db: Annotated[Any, Depends(get_db)],
):
    language = "ar" if request.headers.get("accept-language", "").lower().startswith("ar") else "en"
    ledger_id = str(player)
    today = local_today(db, ledger_id, ledger=ledger)
    assignment = db.get_active_assignment_for_player(account_id_of(player))
    nutrition_state = await asyncio.to_thread(nutrition_service.read, ledger, language,
                                              today=today)
    nutrition_state["coach_sees_adherence"] = assignment is not None
    return nutrition_state


@router.put("/adherence")
async def log_adherence(
    request: Request,
    body: NutritionAdherenceIn,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
    db: Annotated[Any, Depends(get_db)],
):
    ledger_id = str(player)
    today = local_today(db, ledger_id, ledger=ledger)
    assignment = db.get_active_assignment_for_player(account_id_of(player))
    nutrition_state, updated_at = await asyncio.to_thread(
        nutrition_service.log_adherence, ledger, body.value, today
    )
    nutrition_state["coach_sees_adherence"] = assignment is not None
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
    today = local_today(db, str(player), ledger=ledger)
    nutrition_state = await asyncio.to_thread(
        nutrition_service.update_activity, ledger, body.daily_activity, today
    )
    nutrition_state["coach_sees_adherence"] = (
        db.get_active_assignment_for_player(account_id_of(player)) is not None
    )
    return nutrition_state
