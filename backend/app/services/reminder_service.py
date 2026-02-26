import logging
from datetime import datetime, timezone
from uuid import UUID

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.date import DateTrigger
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.database import async_session
from app.models.chat import Chat
from app.models.reminder import Reminder
from app.models.user import User
from app.services.notification_service import send_notification_pubsub
from app.services.call_service import (
    build_call_payload,
    create_call_intent,
    send_voip_push,
    apply_status_transition,
)

logger = logging.getLogger(__name__)

scheduler = AsyncIOScheduler(timezone="UTC")


async def trigger_reminder(reminder_id: str):
    """Called by APScheduler when a reminder is due."""
    async with async_session() as db:
        result = await db.execute(
            select(Reminder).where(Reminder.id == UUID(reminder_id))
        )
        reminder = result.scalar_one_or_none()
        if reminder is None or reminder.is_completed:
            return

        result = await db.execute(select(User).where(User.id == reminder.user_id))
        user = result.scalar_one_or_none()
        if user is None:
            return

        from app.routers.ws import manager

        if reminder.reminder_type == "call":
            chat_result = await db.execute(
                select(Chat)
                .where(Chat.id == reminder.chat_id)
                .options(selectinload(Chat.bot))
            )
            chat = chat_result.scalar_one_or_none()
            bot_name = chat.bot.name if chat and chat.bot else "AI Assistant"
            bot_avatar = chat.bot.avatar_url if chat and chat.bot else None

            call_intent = await create_call_intent(
                db,
                user_id=user.id,
                chat_id=reminder.chat_id,
                reminder_id=reminder.id,
                ring_message=reminder.message,
                scheduled_for=reminder.trigger_at,
            )
            apply_status_transition(call_intent, "ringing")
            db.add(call_intent)

            if user.voip_token:
                payload = build_call_payload(
                    call_id=str(call_intent.id),
                    chat_id=str(reminder.chat_id),
                    bot_name=bot_name,
                    bot_avatar=bot_avatar,
                    message=reminder.message,
                )
                sent = await send_voip_push(
                    voip_token=user.voip_token,
                    payload=payload,
                )
                if not sent and user.fcm_token:
                    await send_notification_pubsub(
                        user_fcm_token=user.fcm_token,
                        title=f"Scheduled call from {bot_name}",
                        body=reminder.message or "Tap to open BotsApp and start the call.",
                        chat_id=str(reminder.chat_id),
                    )
            elif user.fcm_token:
                await send_notification_pubsub(
                    user_fcm_token=user.fcm_token,
                    title=f"Scheduled call from {bot_name}",
                    body=reminder.message or "Open the app to answer your AI call.",
                    chat_id=str(reminder.chat_id),
                )
            # Foreground fallback for currently-online clients.
            if manager.is_online(str(user.id)):
                await manager.send_to_user(
                    str(user.id),
                    {
                        "type": "scheduled_call",
                        "call_id": str(call_intent.id),
                        "chat_id": str(reminder.chat_id),
                        "bot_name": bot_name,
                        "bot_avatar": bot_avatar,
                        "message": reminder.message,
                    },
                )
        else:
            if manager.is_online(str(user.id)):
                await manager.send_to_user(str(user.id), {
                    "type": "reminder",
                    "chat_id": str(reminder.chat_id),
                    "message": reminder.message,
                    "reminder_type": reminder.reminder_type,
                    "reminder_id": str(reminder.id),
                })
            elif user.fcm_token:
                await send_notification_pubsub(
                    user_fcm_token=user.fcm_token,
                    title="Reminder",
                    body=reminder.message,
                    chat_id=str(reminder.chat_id),
                )

        reminder.is_completed = True
        db.add(reminder)
        await db.commit()


async def schedule_reminder(reminder: Reminder):
    """Schedule a reminder with APScheduler."""
    run_date = reminder.trigger_at
    if run_date.tzinfo is None:
        run_date = run_date.replace(tzinfo=timezone.utc)
    scheduler.add_job(
        trigger_reminder,
        trigger=DateTrigger(run_date=run_date, timezone="UTC"),
        args=[str(reminder.id)],
        id=f"reminder_{reminder.id}",
        replace_existing=True,
    )


async def load_pending_reminders():
    """Load all pending reminders from DB and schedule them on startup."""
    async with async_session() as db:
        result = await db.execute(
            select(Reminder).where(
                Reminder.is_completed == False,
                Reminder.trigger_at > datetime.utcnow(),
            )
        )
        reminders = result.scalars().all()
        for reminder in reminders:
            await schedule_reminder(reminder)
        logger.info(f"Loaded {len(reminders)} pending reminders")


def start_scheduler():
    if not scheduler.running:
        scheduler.start()


def stop_scheduler():
    if scheduler.running:
        scheduler.shutdown()
