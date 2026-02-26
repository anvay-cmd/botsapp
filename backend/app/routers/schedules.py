from datetime import datetime, timezone, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.chat import Chat
from app.models.reminder import Reminder
from app.models.user import User
from app.services.reminder_service import scheduler
from app.utils.deps import get_current_user

IST = timezone(timedelta(hours=5, minutes=30))

router = APIRouter(prefix="/schedules", tags=["schedules"])


class ScheduleItem(BaseModel):
    id: UUID
    chat_id: UUID
    bot_name: str
    bot_avatar: str | None
    message: str
    scheduled_for: datetime
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}


def _derive_status(reminder: Reminder) -> str:
    if reminder.is_completed:
        return "completed"
    now = datetime.now(tz=timezone.utc)
    trigger = reminder.trigger_at
    if trigger.tzinfo is None:
        trigger = trigger.replace(tzinfo=timezone.utc)
    if trigger < now:
        return "missed"
    return "upcoming"


@router.get("", response_model=list[ScheduleItem])
async def list_schedules(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Reminder)
        .where(
            Reminder.user_id == user.id,
            Reminder.reminder_type == "call",
        )
        .order_by(Reminder.trigger_at.desc())
    )
    reminders = result.scalars().all()

    items: list[ScheduleItem] = []
    for r in reminders:
        chat_result = await db.execute(
            select(Chat).where(Chat.id == r.chat_id).options(selectinload(Chat.bot))
        )
        chat = chat_result.scalar_one_or_none()
        bot_name = chat.bot.name if chat and chat.bot else "Unknown Bot"
        bot_avatar = chat.bot.avatar_url if chat and chat.bot else None

        trigger_ist = r.trigger_at
        if trigger_ist.tzinfo is None:
            trigger_ist = trigger_ist.replace(tzinfo=timezone.utc)

        items.append(
            ScheduleItem(
                id=r.id,
                chat_id=r.chat_id,
                bot_name=bot_name,
                bot_avatar=bot_avatar,
                message=r.message,
                scheduled_for=trigger_ist,
                status=_derive_status(r),
                created_at=r.created_at,
            )
        )
    return items


@router.delete("/{schedule_id}")
async def delete_schedule(
    schedule_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Reminder).where(
            Reminder.id == schedule_id,
            Reminder.user_id == user.id,
        )
    )
    reminder = result.scalar_one_or_none()
    if reminder is None:
        raise HTTPException(status_code=404, detail="Schedule not found")

    job_id = f"reminder_{reminder.id}"
    try:
        scheduler.remove_job(job_id)
    except Exception:
        pass

    await db.delete(reminder)
    return {"status": "deleted"}
