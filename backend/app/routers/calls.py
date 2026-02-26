from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.outbound_call_intent import OutboundCallIntent
from app.models.user import User
from app.schemas.call import CallIntentResponse, CallStatusUpdateRequest
from app.services.call_service import apply_status_transition, CALL_METRICS
from app.utils.deps import get_current_user

router = APIRouter(prefix="/calls", tags=["calls"])


@router.get("/metrics/summary")
async def call_metrics_summary(
    user: User = Depends(get_current_user),
):
    # Exposed as a lightweight debug endpoint for reliability verification.
    return {"user_id": str(user.id), "metrics": CALL_METRICS}


@router.get("/{call_id}", response_model=CallIntentResponse)
async def get_call_intent(
    call_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(OutboundCallIntent).where(
            OutboundCallIntent.id == call_id,
            OutboundCallIntent.user_id == user.id,
        )
    )
    intent = result.scalar_one_or_none()
    if intent is None:
        raise HTTPException(status_code=404, detail="Call not found")
    return CallIntentResponse.model_validate(intent)


@router.patch("/{call_id}/status", response_model=CallIntentResponse)
async def update_call_status(
    call_id: UUID,
    request: CallStatusUpdateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(OutboundCallIntent).where(
            OutboundCallIntent.id == call_id,
            OutboundCallIntent.user_id == user.id,
        )
    )
    intent = result.scalar_one_or_none()
    if intent is None:
        raise HTTPException(status_code=404, detail="Call not found")

    apply_status_transition(intent, request.status, request.end_reason)
    db.add(intent)
    return CallIntentResponse.model_validate(intent)

