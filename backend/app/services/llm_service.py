import json
import logging
import re
from datetime import datetime, timezone, timedelta
from typing import AsyncGenerator
from uuid import UUID

from google import genai
from google.genai import types
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.bot import Bot
from app.models.chat import Chat
from app.models.integration import Integration
from app.models.message import Message
from app.models.reminder import Reminder
from app.models.user import User
from app.services.call_service import (
    apply_status_transition,
    build_call_payload,
    create_call_intent,
    send_voip_push,
)
from app.services.reminder_service import schedule_reminder

logger = logging.getLogger(__name__)
settings = get_settings()
client = genai.Client(api_key=settings.GEMINI_API_KEY)

IST = timezone(timedelta(hours=5, minutes=30))

SCHEDULE_CALL_DECL = types.FunctionDeclaration(
    name="schedule_call",
    description=(
        "Schedule a phone call from this bot to the user at a specific date and time. "
        "Use this when the user asks you to call them, remind them via call, or schedule a call."
    ),
    parameters=types.Schema(
        type=types.Type.OBJECT,
        properties={
            "time": types.Schema(
                type=types.Type.STRING,
                description=(
                    "ISO 8601 datetime for the call in Indian Standard Time (IST, UTC+05:30). "
                    "Example: '2026-02-26T09:00:00+05:30'. Always include the +05:30 offset."
                ),
            ),
            "message": types.Schema(
                type=types.Type.STRING,
                description="Brief reason for the call, e.g. 'Morning wake-up call' or 'Reminder to take medicine'.",
            ),
        },
        required=["time", "message"],
    ),
)

CANCEL_SCHEDULE_DECL = types.FunctionDeclaration(
    name="cancel_schedule",
    description=(
        "Cancel a previously scheduled call. Use when the user wants to cancel or remove a scheduled call."
    ),
    parameters=types.Schema(
        type=types.Type.OBJECT,
        properties={
            "message_keyword": types.Schema(
                type=types.Type.STRING,
                description="A keyword or phrase from the scheduled call's message to identify which one to cancel.",
            ),
        },
        required=["message_keyword"],
    ),
)

CALL_NOW_DECL = types.FunctionDeclaration(
    name="call_now",
    description=(
        "Start an immediate call from this bot to the user right now. "
        "Use this when the user asks to call now, ring now, or call immediately."
    ),
    parameters=types.Schema(
        type=types.Type.OBJECT,
        properties={
            "message": types.Schema(
                type=types.Type.STRING,
                description="Short reason for the call ring screen.",
            ),
        },
        required=["message"],
    ),
)


async def _load_chat_history(db: AsyncSession, chat_id: UUID, limit: int = 50) -> list[Message]:
    result = await db.execute(
        select(Message)
        .where(Message.chat_id == chat_id)
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    return list(reversed(result.scalars().all()))


def _build_contents(history: list[Message], user_message: str) -> list[types.Content]:
    contents: list[types.Content] = []
    for msg in history:
        role = "user" if msg.role == "user" else "model"
        if not msg.content:
            continue
        normalized = _normalize_message_for_context(msg)
        if not normalized:
            continue
        contents.append(types.Content(role=role, parts=[types.Part(text=normalized)]))

    if not contents or contents[-1].role != "user" or contents[-1].parts[0].text != user_message:
        contents.append(types.Content(role="user", parts=[types.Part(text=user_message)]))
    return contents


def _normalize_message_for_context(msg: Message) -> str:
    if msg.content_type != "voice_call":
        return msg.content
    try:
        payload = json.loads(msg.content)
        if not isinstance(payload, dict):
            raise ValueError("voice payload is not a dict")
        duration = str(payload.get("duration", "")).strip()
        transcript = payload.get("transcript") or []
        lines: list[str] = []
        if isinstance(transcript, list):
            for item in transcript:
                if not isinstance(item, dict):
                    continue
                role = str(item.get("role", "assistant")).strip().lower()
                text = str(item.get("text", "")).strip()
                if not text:
                    continue
                speaker = "User" if role == "user" else "Assistant"
                lines.append(f"{speaker}: {text}")
        if lines:
            header = f"We had a voice call earlier (duration {duration or 'unknown'})."
            convo = "\n".join(lines)
            return f"{header}\nThis is what we talked about:\n{convo}"
        return f"We had a voice call earlier (duration {duration or 'unknown'}), but no detailed notes were captured."
    except Exception:
        return "We had a voice call earlier."


async def _is_web_integration_active(db: AsyncSession, chat_id: UUID) -> bool:
    chat_result = await db.execute(select(Chat).where(Chat.id == chat_id))
    chat = chat_result.scalar_one_or_none()
    if chat is None:
        return False
    integration_result = await db.execute(
        select(Integration).where(
            Integration.user_id == chat.user_id,
            Integration.provider == "web_search",
            Integration.is_active.is_(True),
        )
    )
    return integration_result.scalar_one_or_none() is not None


def _parse_schedule_time(time_str: str) -> datetime:
    """Parse an ISO-ish datetime string, defaulting to IST if no tz info."""
    dt = datetime.fromisoformat(time_str)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=IST)
    return dt


def _looks_like_schedule_intent(user_message: str) -> bool:
    text = user_message.lower()
    asks_for_call = ("call" in text) or ("ring" in text)
    asks_for_schedule = any(k in text for k in ["schedule", "remind", "at ", "tomorrow", "tonight"])
    return asks_for_call and asks_for_schedule


def _infer_schedule_args_from_text(user_message: str) -> dict | None:
    text = user_message.lower()
    m = re.search(r"\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b", text)
    if not m:
        return None

    hour = int(m.group(1))
    minute = int(m.group(2) or "0")
    ampm = m.group(3)
    if hour < 1 or hour > 12 or minute < 0 or minute > 59:
        return None

    if ampm == "pm" and hour != 12:
        hour += 12
    if ampm == "am" and hour == 12:
        hour = 0

    now_ist = datetime.now(IST)
    target = now_ist.replace(hour=hour, minute=minute, second=0, microsecond=0)
    if "tomorrow" in text:
        target = target + timedelta(days=1)
    elif target <= now_ist:
        # If user gave only a time and it's already passed today, assume next day.
        target = target + timedelta(days=1)

    return {
        "time": target.isoformat(),
        "message": user_message.strip() or "Scheduled call",
    }


async def _execute_schedule_call(
    db: AsyncSession, chat_id: UUID, user_id: UUID, args: dict
) -> dict:
    time_str = args.get("time", "")
    message = args.get("message", "Scheduled call")
    try:
        trigger_at = _parse_schedule_time(time_str)
    except Exception:
        return {"success": False, "error": f"Could not parse time: {time_str}"}

    trigger_utc = trigger_at.astimezone(timezone.utc)
    now_utc = datetime.now(tz=timezone.utc)
    if trigger_utc <= now_utc:
        return {"success": False, "error": "Cannot schedule a call in the past."}

    trigger_naive = trigger_utc.replace(tzinfo=None)

    reminder = Reminder(
        chat_id=chat_id,
        user_id=user_id,
        message=message,
        reminder_type="call",
        trigger_at=trigger_naive,
    )
    db.add(reminder)
    await db.commit()
    await schedule_reminder(reminder)

    display_time = trigger_at.astimezone(IST).strftime("%d %b %Y, %I:%M %p IST")
    logger.info("Scheduled call for chat %s at %s: %s", chat_id, display_time, message)
    return {"success": True, "scheduled_time": display_time, "message": message}


async def _execute_cancel_schedule(
    db: AsyncSession, chat_id: UUID, user_id: UUID, args: dict
) -> dict:
    keyword = args.get("message_keyword", "").lower()
    result = await db.execute(
        select(Reminder).where(
            Reminder.chat_id == chat_id,
            Reminder.user_id == user_id,
            Reminder.reminder_type == "call",
            Reminder.is_completed.is_(False),
        )
    )
    reminders = result.scalars().all()
    for r in reminders:
        if keyword in (r.message or "").lower():
            from app.services.reminder_service import scheduler

            try:
                scheduler.remove_job(f"reminder_{r.id}")
            except Exception:
                pass
            r.is_completed = True
            db.add(r)
            return {"success": True, "cancelled_message": r.message}
    return {"success": False, "error": f"No upcoming scheduled call matching '{keyword}' found."}


async def _execute_call_now(
    db: AsyncSession, chat_id: UUID, user_id: UUID, args: dict
) -> dict:
    message = (args.get("message") or "Incoming call").strip()

    user_result = await db.execute(select(User).where(User.id == user_id))
    user = user_result.scalar_one_or_none()
    if user is None:
        return {"success": False, "error": "User not found."}

    chat_result = await db.execute(select(Chat).where(Chat.id == chat_id))
    chat = chat_result.scalar_one_or_none()
    if chat is None:
        return {"success": False, "error": "Chat not found."}

    bot_result = await db.execute(select(Bot).where(Bot.id == chat.bot_id))
    bot = bot_result.scalar_one_or_none()
    bot_name = bot.name if bot else "AI Assistant"
    bot_avatar = bot.avatar_url if bot else None

    call_intent = await create_call_intent(
        db,
        user_id=user_id,
        chat_id=chat_id,
        reminder_id=None,
        ring_message=message,
        scheduled_for=datetime.utcnow(),
    )
    apply_status_transition(call_intent, "ringing")
    db.add(call_intent)
    await db.commit()

    sent = False
    if user.voip_token:
        payload = build_call_payload(
            call_id=str(call_intent.id),
            chat_id=str(chat_id),
            bot_name=bot_name,
            bot_avatar=bot_avatar,
            message=message,
        )
        sent = await send_voip_push(voip_token=user.voip_token, payload=payload)

    if not sent:
        apply_status_transition(call_intent, "failed", "voip_push_failed")
        db.add(call_intent)
        await db.commit()
        return {"success": False, "error": "Could not send call ring to device."}

    return {
        "success": True,
        "call_id": str(call_intent.id),
        "status": "ringing",
        "message": message,
    }


async def _execute_function_call(
    db: AsyncSession, chat_id: UUID, user_id: UUID, fc: types.FunctionCall
) -> dict:
    args = dict(fc.args) if fc.args else {}
    if fc.name == "schedule_call":
        return await _execute_schedule_call(db, chat_id, user_id, args)
    elif fc.name == "cancel_schedule":
        return await _execute_cancel_schedule(db, chat_id, user_id, args)
    elif fc.name == "call_now":
        return await _execute_call_now(db, chat_id, user_id, args)
    return {"error": f"Unknown function: {fc.name}"}


async def get_ai_response_stream(
    db: AsyncSession,
    chat_id: UUID,
    bot_id: UUID,
    user_message: str,
    user_id: UUID | None = None,
) -> AsyncGenerator[str, None]:
    """Stream AI response tokens, handling function calls transparently."""
    result = await db.execute(select(Bot).where(Bot.id == bot_id))
    bot = result.scalar_one_or_none()
    system_prompt = bot.system_prompt if bot else "You are a helpful AI assistant."

    history = await _load_chat_history(db, chat_id)
    contents = _build_contents(history, user_message)
    web_enabled = await _is_web_integration_active(db, chat_id)

    now_ist = datetime.now(IST).strftime("%A, %d %B %Y, %I:%M %p IST")
    system_prompt += f"\n\nCurrent date and time: {now_ist}"

    tools: list[types.Tool] = []
    if web_enabled:
        tools.append(types.Tool(google_search=types.GoogleSearch()))
        system_prompt += (
            "\n\nYou have real-time web search. Use it for any questions about current events, "
            "latest news, live data, or anything that needs up-to-date information."
        )

    tools.append(
        types.Tool(function_declarations=[SCHEDULE_CALL_DECL, CANCEL_SCHEDULE_DECL, CALL_NOW_DECL])
    )
    system_prompt += (
        "\n\nYou can schedule calls to the user using the schedule_call tool. "
        "When the user asks you to call them at a certain time, use this tool. "
        "When the user asks to call right now, use the call_now tool immediately. "
        "Always schedule times in Indian Standard Time (IST, +05:30). "
        "You can also cancel scheduled calls with cancel_schedule. "
        "Never claim a call is scheduled unless the schedule_call tool is actually executed successfully. "
        "Never claim you are calling now unless the call_now tool is actually executed successfully."
    )

    if user_id is None:
        chat_result = await db.execute(select(Chat).where(Chat.id == chat_id))
        chat_obj = chat_result.scalar_one_or_none()
        if chat_obj:
            user_id = chat_obj.user_id

    config = types.GenerateContentConfig(
        system_instruction=system_prompt,
        temperature=0.7,
        tools=tools if tools else None,
        automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
    )

    response = await client.aio.models.generate_content(
        model="gemini-3-flash-preview",
        contents=contents,
        config=config,
    )

    function_calls: list[types.FunctionCall] = []
    text_parts: list[str] = []

    if response.candidates:
        for part in response.candidates[0].content.parts:
            if part.function_call:
                function_calls.append(part.function_call)
            elif part.text:
                text_parts.append(part.text)

    if not function_calls:
        if user_id is not None and _looks_like_schedule_intent(user_message):
            inferred = _infer_schedule_args_from_text(user_message)
            if inferred is not None:
                logger.info("Schedule fallback path used for message: %s", user_message)
                fc_result = await _execute_schedule_call(db, chat_id, user_id, inferred)
                logger.info("Schedule fallback result: %s", fc_result)
                if fc_result.get("success"):
                    yield (
                        f"Done. Scheduled your call for {fc_result['scheduled_time']}."
                    )
                    return
        for t in text_parts:
            yield t
        return

    if user_id is None:
        for t in text_parts:
            yield t
        return

    function_response_parts: list[types.Part] = []
    for fc in function_calls:
        logger.info("Executing tool call: %s(%s)", fc.name, fc.args)
        fc_result = await _execute_function_call(db, chat_id, user_id, fc)
        logger.info("Tool call result: %s", fc_result)
        function_response_parts.append(
            types.Part(function_response=types.FunctionResponse(name=fc.name, response=fc_result))
        )

    contents.append(types.Content(role="model", parts=response.candidates[0].content.parts))
    contents.append(types.Content(role="user", parts=function_response_parts))

    stream2 = await client.aio.models.generate_content_stream(
        model="gemini-3-flash-preview",
        contents=contents,
        config=config,
    )
    async for chunk in stream2:
        if chunk.text:
            yield chunk.text


async def get_ai_response(
    db: AsyncSession,
    chat_id: UUID,
    bot_id: UUID,
    user_message: str,
) -> str:
    full_response = ""
    async for token in get_ai_response_stream(db, chat_id, bot_id, user_message):
        full_response += token
    return full_response


async def get_proactive_message(
    db: AsyncSession,
    chat_id: UUID,
    bot_id: UUID,
) -> str:
    """Generate a short proactive check-in without tool calls."""
    result = await db.execute(select(Bot).where(Bot.id == bot_id))
    bot = result.scalar_one_or_none()
    system_prompt = bot.system_prompt if bot else "You are a helpful AI assistant."
    system_prompt += (
        "\n\nYou are proactively checking in with the user. "
        "Write one short, warm, useful message (max 2 sentences), no markdown."
    )

    history = await _load_chat_history(db, chat_id, limit=30)
    contents: list[types.Content] = []
    for msg in history:
        role = "user" if msg.role == "user" else "model"
        normalized = _normalize_message_for_context(msg)
        if not normalized:
            continue
        contents.append(types.Content(role=role, parts=[types.Part(text=normalized)]))
    contents.append(
        types.Content(
            role="user",
            parts=[
                types.Part(
                    text=(
                        "Send a proactive check-in message now. "
                        "Do not ask more than one question."
                    )
                )
            ],
        )
    )

    response = await client.aio.models.generate_content(
        model="gemini-3-flash-preview",
        contents=contents,
        config=types.GenerateContentConfig(
            system_instruction=system_prompt,
            temperature=0.8,
            automatic_function_calling=types.AutomaticFunctionCallingConfig(disable=True),
        ),
    )
    return (response.text or "").strip()
