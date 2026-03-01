import json
import logging
from datetime import datetime
from uuid import UUID

from apscheduler.triggers.interval import IntervalTrigger
from langchain_core.messages import HumanMessage, AIMessage, SystemMessage, ToolMessage
from langchain_core.tools import tool
from langchain_google_genai import ChatGoogleGenerativeAI
from sqlalchemy import select
from sqlalchemy.orm import selectinload

from app.config import get_settings
from app.database import async_session
from app.models.bot import Bot
from app.models.chat import Chat
from app.models.lifecycle_message import LifecycleMessage
from app.models.message import Message
from app.models.proactive_state import ProactiveState
from app.models.user import User
from app.services.llm_service import (
    _get_integration,
    _is_web_integration_active,
    _execute_schedule_call,
    _execute_cancel_schedule,
    _execute_call_now,
    _execute_web_search,
    _execute_gmail_list,
    _execute_gmail_search,
    _execute_gmail_send,
    IST,
)
from app.services.notification_service import send_notification_pubsub
from app.services.reminder_service import scheduler

logger = logging.getLogger(__name__)
settings = get_settings()

# Global context for tools (same pattern as langchain service)
_current_db = None
_current_chat_id = None
_current_user_id = None
_current_bot = None
_current_state = None

DEFAULT_PROACTIVE_MINUTES = 0
MIN_PROACTIVE_MINUTES = 1


# ========== Tool Definitions (same as main agent) ==========

@tool
async def schedule_call_tool(time: str, message: str) -> dict:
    """Schedule a phone call from this bot to the user at a specific date and time.

    Args:
        time: ISO 8601 datetime in IST (UTC+05:30). Example: '2026-03-01T09:00:00+05:30'
        message: Brief reason for the call
    """
    return await _execute_schedule_call(
        _current_db, _current_chat_id, _current_user_id, {"time": time, "message": message}
    )


@tool
async def cancel_schedule_tool(message_keyword: str) -> dict:
    """Cancel a previously scheduled call.

    Args:
        message_keyword: Keyword from the scheduled call's message
    """
    return await _execute_cancel_schedule(
        _current_db, _current_chat_id, _current_user_id, {"message_keyword": message_keyword}
    )


@tool
async def call_now_tool(message: str) -> dict:
    """Start an immediate call from this bot to the user right now.

    Args:
        message: Short reason for the call
    """
    return await _execute_call_now(
        _current_db, _current_chat_id, _current_user_id, {"message": message}
    )


@tool
async def web_search_tool(query: str) -> dict:
    """Search the web for current information, news, or real-time data.

    Args:
        query: The search query
    """
    return await _execute_web_search(query)


@tool
async def scrape_url_tool(url: str) -> dict:
    """Scrape and extract text content from a web URL.

    Args:
        url: The URL to scrape
    """
    import httpx
    from bs4 import BeautifulSoup
    try:
        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.get(url, follow_redirects=True)
            response.raise_for_status()

            soup = BeautifulSoup(response.text, 'html.parser')
            for script in soup(["script", "style"]):
                script.decompose()

            text = soup.get_text()
            lines = (line.strip() for line in text.splitlines())
            chunks = (phrase.strip() for line in lines for phrase in line.split("  "))
            text = '\n'.join(chunk for chunk in chunks if chunk)

            if len(text) > 3000:
                text = text[:3000] + "..."

            return {"success": True, "url": url, "content": text}
    except Exception as e:
        logger.error(f"Scrape URL error: {e}")
        return {"success": False, "error": str(e)}


@tool
async def gmail_list_emails_tool(max_results: int = 10) -> dict:
    """List recent emails from the user's Gmail inbox.

    Args:
        max_results: Maximum number of emails (default 10, max 20)
    """
    return await _execute_gmail_list(_current_db, _current_chat_id, {"max_results": max_results})


@tool
async def gmail_search_emails_tool(query: str, max_results: int = 5) -> dict:
    """Search Gmail emails using a query string.

    Args:
        query: Gmail search query (e.g., 'from:john@example.com', 'subject:meeting')
        max_results: Maximum number of emails (default 5)
    """
    return await _execute_gmail_search(
        _current_db, _current_chat_id, {"query": query, "max_results": max_results}
    )


@tool
async def gmail_send_email_tool(to: str, subject: str, body: str) -> dict:
    """Send an email from the user's Gmail account.

    Args:
        to: Recipient email address
        subject: Email subject line
        body: Email body text
    """
    return await _execute_gmail_send(
        _current_db, _current_chat_id, {"to": to, "subject": subject, "body": body}
    )


@tool
async def send_message_tool(message: str) -> dict:
    """Send a message to the user in the main conversation.

    IMPORTANT: Only use this if you have something truly important to tell the user.
    Do NOT use this for routine checks or if nothing significant was found.

    Args:
        message: The message to send to the user
    """
    global _current_bot, _current_chat_id, _current_state

    if not message or not message.strip():
        return {"success": False, "error": "Message cannot be empty"}

    # This will be caught and handled by the ReACT loop to push to main conversation
    return {
        "success": True,
        "action": "push_to_main",
        "message": message.strip(),
        "note": "Message will be sent to user in main conversation"
    }


def _proactive_minutes(bot: Bot) -> int | None:
    """Get proactive interval from bot config. Checks proactive_interval_minutes first, then falls back to proactive_minutes."""
    cfg = bot.integrations_config or {}
    # Try new proactive_interval_minutes first
    val = cfg.get("proactive_interval_minutes")
    if val is not None:
        try:
            m = int(val)
            if m <= 0:
                return None
            return max(m, MIN_PROACTIVE_MINUTES)
        except Exception:
            pass
    # Fall back to old proactive_minutes
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


def _get_max_messages(bot: Bot) -> int:
    """Get max proactive messages before user response."""
    cfg = bot.integrations_config or {}
    val = cfg.get("proactive_max_messages", 5)
    try:
        return max(int(val), 1)
    except Exception:
        return 5


def _get_proactivity_prompt(bot: Bot) -> str:
    """Get custom proactivity prompt."""
    cfg = bot.integrations_config or {}
    return cfg.get("proactivity_prompt") or "Check if anything has changed since last check and message the user only if needed."


def _job_id(bot_id: UUID) -> str:
    return f"proactive_bot_{bot_id}"


async def trigger_proactive_bot(bot_id: str):
    """Trigger proactive bot check-in using lifecycle conversation pattern."""
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

        max_messages = _get_max_messages(bot)
        proactivity_prompt = _get_proactivity_prompt(bot)

        logger.info(
            "Proactive: running bot=%s name=%s interval=%s max_msg=%s chats=%s",
            bot.id,
            bot.name,
            minutes,
            max_messages,
            len(bot.chats),
        )

        for chat in bot.chats:
            try:
                await _process_proactive_chat(db, bot, chat, max_messages, proactivity_prompt)
            except Exception as e:
                logger.warning("Proactive: failed for chat %s: %s", chat.id, e, exc_info=True)
                await db.rollback()


async def _process_proactive_chat(db, bot: Bot, chat: Chat, max_messages: int, proactivity_prompt: str):
    """Process proactive check with full ReACT loop and all tools."""
    global _current_db, _current_chat_id, _current_user_id, _current_bot, _current_state

    # Get or create proactive state
    state_result = await db.execute(select(ProactiveState).where(ProactiveState.chat_id == chat.id))
    state = state_result.scalar_one_or_none()
    if state is None:
        state = ProactiveState(chat_id=chat.id, message_count=0, session_counter=0)
        db.add(state)
        await db.flush()

    # Check if we've exceeded max messages
    if state.message_count >= max_messages:
        logger.info(
            "Proactive: chat %s exceeded max messages (%s/%s), skipping",
            chat.id,
            state.message_count,
            max_messages,
        )
        return

    # Increment session counter
    state.session_counter += 1
    session_id = state.session_counter
    db.add(state)
    await db.flush()

    # Set global context for tools
    _current_db = db
    _current_chat_id = chat.id
    _current_user_id = chat.user_id
    _current_bot = bot
    _current_state = state

    logger.info("=" * 80)
    logger.info("🔄 Proactive ReACT: chat=%s session=%s msg_count=%s", chat.id, session_id, state.message_count)

    # Load recent main conversation history
    history_result = await db.execute(
        select(Message)
        .where(Message.chat_id == chat.id)
        .order_by(Message.created_at.desc())
        .limit(50)
    )
    history = list(reversed(history_result.scalars().all()))

    # Check integrations
    web_enabled = await _is_web_integration_active(db, chat.id)
    gmail_integration = await _get_integration(db, chat.id, "gmail")
    gmail_enabled = gmail_integration is not None and gmail_integration.credentials is not None

    # Get bot's enabled tools
    bot_enabled_tools = bot.integrations_config or {}

    # Build system prompt with context
    now_ist = datetime.now(IST).strftime("%A, %d %B %Y, %I:%M %p IST")
    system_prompt = f"""{bot.system_prompt}

Current date and time: {now_ist}

=== PROACTIVE CHECK MODE ===
You are running a proactive check based on this instruction:
"{proactivity_prompt}"

Your task:
1. Use available tools to gather information (check emails, search web, etc.)
2. Think step-by-step about whether the user should be notified
3. ONLY use send_message_tool if you find something truly important

Remember: The user did NOT ask for this. Only interrupt them if it's worth it.
"""

    # Build tools list - ALWAYS include send_message_tool and call tools
    tools = [send_message_tool, schedule_call_tool, cancel_schedule_tool, call_now_tool]

    # Add web search tools if enabled
    web_search_enabled_tools = bot_enabled_tools.get('web_search', [])
    if web_enabled:
        if 'web_search' in web_search_enabled_tools:
            tools.append(web_search_tool)
            system_prompt += "\n\nYou have real-time web search. Use it to check for latest information."
        if 'scrape_url' in web_search_enabled_tools:
            tools.append(scrape_url_tool)

    # Add Gmail tools if enabled
    gmail_enabled_tools = bot_enabled_tools.get('gmail', [])
    if gmail_enabled:
        available_gmail_tools = {
            'gmail_list_emails': gmail_list_emails_tool,
            'gmail_search_emails': gmail_search_emails_tool,
            'gmail_send_email': gmail_send_email_tool,
        }
        enabled_tools_list = []
        for tool_id, tool_func in available_gmail_tools.items():
            if tool_id in gmail_enabled_tools:
                tools.append(tool_func)
                enabled_tools_list.append(tool_id.replace('_', ' ').title())

        if enabled_tools_list:
            system_prompt += f"\n\nGmail tools: {', '.join(enabled_tools_list)}"

    # Save system prompt to lifecycle
    system_msg = LifecycleMessage(
        chat_id=chat.id,
        bot_id=bot.id,
        session_id=session_id,
        role="system",
        content=system_prompt,
        content_type="system_prompt",
    )
    db.add(system_msg)
    await db.flush()

    # Build messages with history
    messages = [SystemMessage(content=system_prompt)]

    for msg in history:
        if msg.content:
            if msg.role == "user":
                messages.append(HumanMessage(content=msg.content))
            elif msg.role == "assistant":
                messages.append(AIMessage(content=msg.content))

    messages.append(HumanMessage(content=proactivity_prompt))

    # Save user prompt to lifecycle
    user_msg = LifecycleMessage(
        chat_id=chat.id,
        bot_id=bot.id,
        session_id=session_id,
        role="user",
        content=proactivity_prompt,
        content_type="text",
    )
    db.add(user_msg)
    await db.flush()

    # Create LLM with tools
    llm = ChatGoogleGenerativeAI(
        model="gemini-3-flash-preview",
        google_api_key=settings.GEMINI_API_KEY,
        temperature=0.7,
    )
    llm_with_tools = llm.bind_tools(tools)

    try:
        # Run ReACT loop
        await _react_loop(db, bot, chat, session_id, state, llm_with_tools, messages)
    except Exception as e:
        logger.error("Proactive ReACT loop failed for chat %s: %s", chat.id, e, exc_info=True)
    finally:
        await db.commit()


async def _react_loop(db, bot: Bot, chat: Chat, session_id: int, state: ProactiveState, llm_with_tools, messages):
    """Run the ReACT loop: Reason → Act → Observe → repeat."""
    iteration = 0
    max_iterations = 10  # Safety limit
    messages_to_push = []  # Collect messages to push to main conversation

    while iteration < max_iterations:
        iteration += 1
        logger.info("📍 Iteration %s", iteration)

        # Invoke LLM
        try:
            response = await llm_with_tools.ainvoke(messages)
        except Exception as e:
            logger.error("LLM invoke error: %s", e)
            break

        # Save reasoning text to lifecycle
        if response.content:
            reasoning_text = str(response.content).strip()
            if reasoning_text:
                logger.info("💭 Reasoning: %s", reasoning_text[:200])
                lifecycle_msg = LifecycleMessage(
                    chat_id=chat.id,
                    bot_id=bot.id,
                    session_id=session_id,
                    role="assistant",
                    content=reasoning_text,
                    content_type="text",
                )
                db.add(lifecycle_msg)
                await db.flush()

        # Check for tool calls
        if not response.tool_calls:
            logger.info("✅ No more tool calls. ReACT loop complete.")
            break

        logger.info(f"🔧 Found {len(response.tool_calls)} tool call(s)")

        # Execute each tool call
        tool_messages = []
        for tool_call in response.tool_calls:
            tool_name = tool_call["name"]
            tool_args = tool_call["args"]
            logger.info(f"  ⚙️  {tool_name}({tool_args})")

            # Save tool call to lifecycle
            tool_call_msg = LifecycleMessage(
                chat_id=chat.id,
                bot_id=bot.id,
                session_id=session_id,
                role="assistant",
                content=f"{tool_name}({json.dumps(tool_args)})",
                content_type="tool_call",
            )
            db.add(tool_call_msg)
            await db.flush()

            # Execute the tool
            tool_result = await _execute_tool(tool_call)
            logger.info(f"  📊 Result: {str(tool_result)[:200]}")

            # Save tool result to lifecycle
            tool_result_msg = LifecycleMessage(
                chat_id=chat.id,
                bot_id=bot.id,
                session_id=session_id,
                role="tool",
                content=json.dumps(tool_result),
                content_type="tool_result",
            )
            db.add(tool_result_msg)
            await db.flush()

            # Check if this is send_message_tool
            if tool_name == "send_message_tool" and tool_result.get("success") and tool_result.get("action") == "push_to_main":
                message_to_push = tool_result.get("message")
                if message_to_push:
                    messages_to_push.append(message_to_push)
                    logger.info("📤 Queued message to push to main conversation")

            # Add tool message to conversation
            tool_messages.append(
                ToolMessage(
                    content=json.dumps(tool_result),
                    tool_call_id=tool_call["id"],
                )
            )

        # Add AI message and tool messages to history
        messages.append(response)
        messages.extend(tool_messages)

        # If we hit send_message, we're done
        if messages_to_push:
            logger.info("✅ send_message called. Ending ReACT loop.")
            break

    # Push all queued messages to main conversation
    for message_text in messages_to_push:
        await _push_to_main_conversation(db, bot, chat, message_text, state)

    logger.info("=" * 80)
    logger.info(f"🏁 ReACT complete: {iteration} iterations, {len(messages_to_push)} messages pushed")


async def _execute_tool(tool_call):
    """Execute a single tool call."""
    tool_name = tool_call["name"]
    tool_args = tool_call["args"]

    try:
        if tool_name == "schedule_call_tool":
            return await schedule_call_tool.ainvoke(tool_args)
        elif tool_name == "cancel_schedule_tool":
            return await cancel_schedule_tool.ainvoke(tool_args)
        elif tool_name == "call_now_tool":
            return await call_now_tool.ainvoke(tool_args)
        elif tool_name == "web_search_tool":
            return await web_search_tool.ainvoke(tool_args)
        elif tool_name == "scrape_url_tool":
            return await scrape_url_tool.ainvoke(tool_args)
        elif tool_name == "gmail_list_emails_tool":
            return await gmail_list_emails_tool.ainvoke(tool_args)
        elif tool_name == "gmail_search_emails_tool":
            return await gmail_search_emails_tool.ainvoke(tool_args)
        elif tool_name == "gmail_send_email_tool":
            return await gmail_send_email_tool.ainvoke(tool_args)
        elif tool_name == "send_message_tool":
            return await send_message_tool.ainvoke(tool_args)
        else:
            return {"error": f"Unknown tool: {tool_name}"}
    except Exception as e:
        logger.error(f"Tool {tool_name} error: {e}", exc_info=True)
        return {"error": str(e)}


async def _push_to_main_conversation(db, bot: Bot, chat: Chat, message_text: str, state: ProactiveState):
    """Push a message from lifecycle to main conversation and notify user."""
    # Get user
    user_result = await db.execute(select(User).where(User.id == chat.user_id))
    user = user_result.scalar_one_or_none()
    if user is None:
        logger.warning("Proactive: user not found for chat %s", chat.id)
        return

    # Create message in main conversation
    ai_msg = Message(
        chat_id=chat.id,
        role="assistant",
        content=message_text,
        content_type="text",
    )
    db.add(ai_msg)
    chat.last_message_at = datetime.utcnow()
    chat.unread_count = (chat.unread_count or 0) + 1
    db.add(chat)

    # Increment message count
    state.message_count += 1
    db.add(state)
    await db.flush()

    created_at = ai_msg.created_at.isoformat() if ai_msg.created_at else datetime.utcnow().isoformat()
    message_id = str(ai_msg.id)

    # Send via websocket and push notification
    try:
        from app.routers.ws import manager

        delivered = await manager.send_to_user(
            str(user.id),
            {
                "type": "message_complete",
                "chat_id": str(chat.id),
                "message_id": message_id,
                "role": "assistant",
                "content": message_text,
                "content_type": "text",
                "created_at": created_at,
            },
        )
        logger.info(
            "Proactive: ws delivery user=%s chat=%s delivered=%s",
            user.id,
            chat.id,
            delivered,
        )

        if user.fcm_token and not chat.is_muted:
            await send_notification_pubsub(
                user_fcm_token=user.fcm_token,
                title=bot.name,
                body=message_text[:160],
                chat_id=str(chat.id),
                avatar_url=bot.avatar_url,
            )
            logger.info("Proactive: push notification sent user=%s chat=%s", user.id, chat.id)
    except Exception as e:
        logger.warning("Proactive: notification failed for chat %s: %s", chat.id, e)


async def reset_proactive_counter(chat_id: UUID):
    """Reset proactive message counter when user sends a message."""
    async with async_session() as db:
        result = await db.execute(select(ProactiveState).where(ProactiveState.chat_id == chat_id))
        state = result.scalar_one_or_none()
        if state and state.message_count > 0:
            state.message_count = 0
            state.last_reset_at = datetime.utcnow()
            db.add(state)
            await db.commit()
            logger.info("Proactive: reset counter for chat %s", chat_id)


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

