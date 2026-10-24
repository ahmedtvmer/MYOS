"""Player Nutrition setup and read endpoints."""

import asyncio
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request

from service import analytics, nutrition as nutrition_service
from svc.dependencies import account_id_of, get_ledger, get_verified_player
from svc.schemas import NutritionActivityIn, NutritionSetupIn

router = APIRouter(prefix="/nutrition", tags=["nutrition"])


@router.post("/setup")
async def setup_nutrition(
    request: Request,
    body: NutritionSetupIn,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
):
    try:
        result = await asyncio.to_thread(
            nutrition_service.setup, ledger,
            {**body.model_dump(), "screening": body.screening.model_dump(),
             "language": "ar" if request.headers.get("accept-language", "").lower().startswith("ar") else "en"},
        )
    except (ValueError, KeyError) as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from None
    if result["state"] != "incomplete":
        analytics.capture_for_request(
            request,
            analytics.AnalyticsEvent(
                account_id=account_id_of(player), event="nutrition_setup_completed",
                domain_key=f"{player}:{result.get('state')}:{result.get('goal', 'blocked')}",
                role="player", properties={"blocked": result["state"] in ("blocked", "under_18")},
            ),
        )
    return result


@router.get("")
async def read_nutrition(
    request: Request,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
):
    language = "ar" if request.headers.get("accept-language", "").lower().startswith("ar") else "en"
    return await asyncio.to_thread(nutrition_service.read, ledger, language)


@router.put("/activity")
async def update_activity(
    body: NutritionActivityIn,
    player: Annotated[Any, Depends(get_verified_player)],
    ledger: Annotated[Any, Depends(get_ledger)],
):
    return await asyncio.to_thread(nutrition_service.update_activity, ledger, body.daily_activity)
