import logging
from datetime import datetime
from uuid import UUID

from apscheduler.triggers.interval import IntervalTrigger
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.database import async_session
from app.models.bot import Bot
from app.models.chat import Chat
from app.models.message import Message
from app.models.user import User
from app.services.llm_service import get_proactive_message
from app.services.notification_service import send_notification_pubsub
from app.services.reminder_service import scheduler

logger = logging.getLogger(__name__)

DEFAULT_PROACTIVE_MINUTES = 0
MIN_PROACTIVE_MINUTES = 1


def _proactive_minutes(bot: Bot) -> int | None:
    cfg = bot.integrations_config or {}
    val = cfg.get("proactive_minutes", DEFAULT_PROACTIVE_MINUTES)
    if val is None:
        return None
    try:
        m = int(val)
    except Exception:
        return DEFAULT_PROACTIVE_MINUTES
    if m <= 0:
        return None
    return max(m, MIN_PROACTIVE_MINUTES)


def _job_id(bot_id: UUID) -> str:
    return f"proactive_bot_{bot_id}"


async def trigger_proactive_bot(bot_id: str):
    async with async_session() as db:
        result = await db.execute(
            select(Bot)
            .where(Bot.id == UUID(bot_id))
            .options(selectinload(Bot.chats))
        )
        bot = result.scalar_one_or_none()
        if bot is None:
            logger.info("Proactive: bot %s not found, skipping", bot_id)
            return

        minutes = _proactive_minutes(bot)
        if minutes is None:
            logger.info("Proactive: bot %s disabled, skipping", bot_id)
            return
        logger.info(
            "Proactive: running bot=%s name=%s interval=%s chats=%s",
            bot.id,
            bot.name,
            minutes,
            len(bot.chats),
        )

        for chat in bot.chats:
            user_result = await db.execute(select(User).where(User.id == chat.user_id))
            user = user_result.scalar_one_or_none()
            if user is None:
                logger.info("Proactive: chat %s user missing, skipping", chat.id)
                continue

            try:
                text = await get_proactive_message(db, chat.id, bot.id)
            except Exception as e:
                logger.warning("Proactive generation failed for bot %s: %s", bot.id, e)
                continue

            text = (text or "").strip()
            if not text:
                text = f"Hey, {bot.name} is checking in. How's it going?"
                logger.info("Proactive: empty LLM output, using fallback for chat %s", chat.id)
            else:
                logger.info("Proactive: generated message for chat %s len=%s", chat.id, len(text))

            ai_msg = Message(
                chat_id=chat.id,
                role="assistant",
                content=text,
                content_type="text",
            )
            db.add(ai_msg)
            chat.last_message_at = datetime.utcnow()
            chat.unread_count = (chat.unread_count or 0) + 1
            db.add(chat)
            await db.flush()
            created_at = ai_msg.created_at.isoformat() if ai_msg.created_at else datetime.utcnow().isoformat()
            message_id = str(ai_msg.id)
            await db.commit()

            try:
                from app.routers.ws import manager

                delivered = await manager.send_to_user(
                    str(user.id),
                    {
                        "type": "message_complete",
                        "chat_id": str(chat.id),
                        "message_id": message_id,
                        "role": "assistant",
                        "content": text,
                        "content_type": "text",
                        "created_at": created_at,
                    },
                )
                logger.info(
                    "Proactive: ws delivery result user=%s chat=%s delivered=%s muted=%s has_token=%s",
                    user.id,
                    chat.id,
                    delivered,
                    chat.is_muted,
                    bool(user.fcm_token),
                )
                if user.fcm_token and not chat.is_muted:
                    logger.info(
                        "Proactive: attempting push user=%s token_prefix=%s delivered=%s",
                        user.id,
                        user.fcm_token[:10],
                        delivered,
                    )
                    await send_notification_pubsub(
                        user_fcm_token=user.fcm_token,
                        title=bot.name,
                        body=text[:160],
                        chat_id=str(chat.id),
                        avatar_url=bot.avatar_url,
                    )
                    logger.info("Proactive: push request sent user=%s chat=%s", user.id, chat.id)
            except Exception as e:
                logger.warning("Proactive post-send failed: %s", e)


async def upsert_proactive_job(bot_id: UUID, minutes: int | None):
    job_id = _job_id(bot_id)
    if minutes is None or minutes <= 0:
        try:
            scheduler.remove_job(job_id)
        except Exception:
            pass
        return

    scheduler.add_job(
        trigger_proactive_bot,
        trigger=IntervalTrigger(minutes=max(minutes, MIN_PROACTIVE_MINUTES), timezone="UTC"),
        args=[str(bot_id)],
        id=job_id,
        replace_existing=True,
    )


async def remove_proactive_job(bot_id: UUID):
    try:
        scheduler.remove_job(_job_id(bot_id))
    except Exception:
        pass


async def load_proactive_jobs():
    async with async_session() as db:
        result = await db.execute(select(Bot))
        bots = result.scalars().all()
        count = 0
        for bot in bots:
            minutes = _proactive_minutes(bot)
            if minutes is None:
                continue
            scheduler.add_job(
                trigger_proactive_bot,
                trigger=IntervalTrigger(minutes=minutes, timezone="UTC"),
                args=[str(bot.id)],
                id=_job_id(bot.id),
                replace_existing=True,
            )
            count += 1
        logger.info("Loaded %d proactive bot jobs", count)

