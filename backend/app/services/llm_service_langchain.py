"""
LangChain-based LLM service - provider-agnostic implementation
Supports: Google Gemini, Anthropic Claude, and other LangChain-compatible models
"""
import json
import logging
from datetime import datetime, timezone, timedelta
from typing import AsyncGenerator
from uuid import UUID

from langchain_core.messages import HumanMessage, AIMessage, SystemMessage, ToolMessage
from langchain_core.tools import tool
from langchain_google_genai import ChatGoogleGenerativeAI
# from langchain_anthropic import ChatAnthropic  # Uncomment to use Claude
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.bot import Bot
from app.models.chat import Chat
from app.models.integration import Integration
from app.models.message import Message
from app.services.llm_service import (
    _load_chat_history,
    _normalize_message_for_context,
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

logger = logging.getLogger(__name__)
settings = get_settings()

# Global context for tools
_current_db: AsyncSession | None = None
_current_chat_id: UUID | None = None
_current_user_id: UUID | None = None


# Define LangChain tools
@tool
async def schedule_call_tool(time: str, message: str) -> dict:
    """Schedule a phone call from this bot to the user at a specific date and time.

    Args:
        time: ISO 8601 datetime in IST (UTC+05:30). Example: '2026-02-26T09:00:00+05:30'
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

            # Remove script and style elements
            for script in soup(["script", "style"]):
                script.decompose()

            # Get text
            text = soup.get_text()

            # Clean up text
            lines = (line.strip() for line in text.splitlines())
            chunks = (phrase.strip() for line in lines for phrase in line.split("  "))
            text = '\n'.join(chunk for chunk in chunks if chunk)

            # Limit to first 3000 characters
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


def _get_llm_model(model_type: str = "gemini"):
    """Get LangChain model instance based on type."""
    if model_type == "gemini":
        return ChatGoogleGenerativeAI(
            model="gemini-3-flash-preview",
            google_api_key=settings.GEMINI_API_KEY,
            temperature=0.7,
        )
    elif model_type == "claude":
        from langchain_anthropic import ChatAnthropic
        return ChatAnthropic(
            model="claude-3-5-sonnet-20241022",
            anthropic_api_key=settings.ANTHROPIC_API_KEY,
            temperature=0.7,
        )
    else:
        raise ValueError(f"Unknown model type: {model_type}")


def _build_messages(history: list[Message], user_message: str, system_prompt: str):
    """Convert chat history to LangChain messages.

    Note: We skip the last user message in history because it's already
    saved to DB before this function is called, and we append it separately
    to avoid duplication.
    """
    messages = [SystemMessage(content=system_prompt)]

    for i, msg in enumerate(history):
        if not msg.content:
            continue
        normalized = _normalize_message_for_context(msg)
        if not normalized:
            continue

        # Skip the last user message if it matches the current user_message
        if msg.role == "user":
            if i == len(history) - 1 and normalized.strip() == user_message.strip():
                continue
            messages.append(HumanMessage(content=normalized))
        elif msg.role == "assistant" and msg.content_type != "tool_call":
            messages.append(AIMessage(content=normalized))

    messages.append(HumanMessage(content=user_message))
    return messages


async def get_ai_response_stream_langchain(
    db: AsyncSession,
    chat_id: UUID,
    bot_id: UUID,
    user_message: str,
    user_id: UUID | None = None,
    model_type: str = None,
) -> AsyncGenerator[dict | str, None]:
    """Stream AI response using LangChain."""
    global _current_db, _current_chat_id, _current_user_id

    # Use configured provider if not specified
    if model_type is None:
        model_type = settings.LLM_PROVIDER

    # Set global context for tools
    _current_db = db
    _current_chat_id = chat_id
    if user_id is None:
        chat_result = await db.execute(select(Chat).where(Chat.id == chat_id))
        chat_obj = chat_result.scalar_one_or_none()
        if chat_obj:
            user_id = chat_obj.user_id
    _current_user_id = user_id

    # Load bot and history
    result = await db.execute(select(Bot).where(Bot.id == bot_id))
    bot = result.scalar_one_or_none()
    system_prompt = bot.system_prompt if bot else "You are a helpful AI assistant."

    history = await _load_chat_history(db, chat_id)

    # Build system prompt with context
    now_ist = datetime.now(IST).strftime("%A, %d %B %Y, %I:%M %p IST")
    system_prompt += f"\n\nCurrent date and time: {now_ist}"

    # Check integrations
    web_enabled = await _is_web_integration_active(db, chat_id)
    gmail_integration = await _get_integration(db, chat_id, "gmail")
    gmail_enabled = gmail_integration is not None and gmail_integration.credentials is not None

    # Get bot's enabled tools from integrations_config
    bot_enabled_tools = {}
    if bot and bot.integrations_config:
        bot_enabled_tools = bot.integrations_config

    # Build tools list - always include call scheduling tools
    tools = [schedule_call_tool, cancel_schedule_tool, call_now_tool]

    # Add web search tools if integration is active AND bot has them enabled
    web_search_enabled_tools = bot_enabled_tools.get('web_search', [])
    if web_enabled:
        if 'web_search' in web_search_enabled_tools:
            tools.append(web_search_tool)
            system_prompt += (
                "\n\nYou have real-time web search. Use it for current events, "
                "latest news, live data, or recent information."
            )
        if 'scrape_url' in web_search_enabled_tools:
            tools.append(scrape_url_tool)
            system_prompt += "\n\nYou can scrape web URLs to extract their content."

    # Add Gmail tools if integration is active AND bot has them enabled
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
            system_prompt += (
                f"\n\nYou have access to the user's Gmail with these capabilities: "
                f"{', '.join(enabled_tools_list)}. "
                "Use these tools when the user asks about emails."
            )

    system_prompt += (
        "\n\nYou can schedule calls using schedule_call_tool. "
        "Use call_now_tool for immediate calls. "
        "Always use Indian Standard Time (IST, +05:30). "
        "Never claim a call is scheduled unless the tool executed successfully."
    )

    # Create LLM with tools
    llm = _get_llm_model(model_type)
    llm_with_tools = llm.bind_tools(tools)

    # Build messages
    messages = _build_messages(history, user_message, system_prompt)

    # First call to get initial response
    response = await llm_with_tools.ainvoke(messages)

    # Helper to extract text from content
    def extract_text(content):
        if not content:
            return ""
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            # LangChain can return list of content blocks
            text_parts = []
            for part in content:
                if isinstance(part, str):
                    text_parts.append(part)
                elif isinstance(part, dict) and "text" in part:
                    text_parts.append(part["text"])
                elif hasattr(part, "text"):
                    text_parts.append(part.text)
            return " ".join(text_parts)
        return str(content)

    # Helper to execute a single tool call
    async def execute_tool(tool_call):
        tool_name = tool_call["name"]
        tool_result = None

        try:
            if tool_name == "schedule_call_tool":
                tool_result = await schedule_call_tool.ainvoke(tool_call["args"])
            elif tool_name == "cancel_schedule_tool":
                tool_result = await cancel_schedule_tool.ainvoke(tool_call["args"])
            elif tool_name == "call_now_tool":
                tool_result = await call_now_tool.ainvoke(tool_call["args"])
            elif tool_name == "web_search_tool":
                tool_result = await web_search_tool.ainvoke(tool_call["args"])
            elif tool_name == "scrape_url_tool":
                tool_result = await scrape_url_tool.ainvoke(tool_call["args"])
            elif tool_name == "gmail_list_emails_tool":
                tool_result = await gmail_list_emails_tool.ainvoke(tool_call["args"])
            elif tool_name == "gmail_search_emails_tool":
                tool_result = await gmail_search_emails_tool.ainvoke(tool_call["args"])
            elif tool_name == "gmail_send_email_tool":
                tool_result = await gmail_send_email_tool.ainvoke(tool_call["args"])

            logger.info(f"Tool {tool_name} result: {tool_result}")
        except Exception as e:
            logger.error(f"Tool {tool_name} error: {e}")
            tool_result = {"error": str(e)}

        return tool_result

    # Loop through tool calls until there are none left
    iteration = 0
    max_iterations = 10  # Safety limit to prevent infinite loops

    logger.info("=" * 80)
    logger.info("🔄 Starting ReACT loop")

    while response.tool_calls and iteration < max_iterations:
        iteration += 1
        logger.info("=" * 80)
        logger.info(f"📍 ITERATION {iteration}")
        logger.info(f"🔧 Found {len(response.tool_calls)} tool call(s)")

        # Yield text content first if present
        if response.content:
            content_str = extract_text(response.content)
            if content_str.strip():
                logger.info(f"💬 LLM reasoning text: {content_str[:100]}{'...' if len(content_str) > 100 else ''}")
                paragraphs = content_str.split("\n\n")
                for para in paragraphs:
                    lines = para.split("\n")
                    for line in lines:
                        if line.strip():
                            yield {"type": "paragraph", "content": line.strip()}

        # Execute all tool calls in this iteration
        tool_messages = []
        for idx, tool_call in enumerate(response.tool_calls, 1):
            logger.info(f"  ⚙️  Tool {idx}/{len(response.tool_calls)}: {tool_call['name']}")
            logger.info(f"      Args: {tool_call['args']}")

            # Yield tool call notification
            yield {
                "type": "tool_call",
                "name": tool_call["name"],
                "args": tool_call["args"],
            }

            # Execute tool
            logger.info(f"      ▶️  Executing {tool_call['name']}...")
            tool_result = await execute_tool(tool_call)

            # Log result preview
            result_str = json.dumps(tool_result)
            logger.info(f"      ✅ Result: {result_str[:150]}{'...' if len(result_str) > 150 else ''}")

            # Create tool message
            tool_messages.append(
                ToolMessage(
                    content=json.dumps(tool_result),
                    tool_call_id=tool_call["id"],
                )
            )

        # Add response and tool results to conversation
        logger.info(f"🔙 Feeding {len(tool_messages)} tool result(s) back to LLM")
        messages.append(response)
        messages.extend(tool_messages)

        # Get next response
        logger.info("🤔 Getting next LLM response...")
        response = await llm_with_tools.ainvoke(messages)

        has_tool_calls = bool(response.tool_calls)
        has_text = bool(response.content and extract_text(response.content).strip())
        logger.info(f"📥 Got response - Text: {has_text}, Tool calls: {has_tool_calls}")
        if has_tool_calls:
            logger.info(f"   Next iteration will have {len(response.tool_calls)} tool call(s)")

    # No more tool calls - stream final text response
    logger.info("=" * 80)
    logger.info("🏁 ReACT loop complete - no more tool calls")
    if response.content:
        content_str = extract_text(response.content)
        if content_str.strip():
            logger.info(f"📝 Final text response: {content_str[:200]}{'...' if len(content_str) > 200 else ''}")
            paragraphs = content_str.split("\n\n")
            for para in paragraphs:
                lines = para.split("\n")
                for line in lines:
                    if line.strip():
                        yield {"type": "paragraph", "content": line.strip()}
    logger.info("=" * 80)
