import asyncio
import json
import logging
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select

from app.database import async_session
from app.models.bot import Bot
from app.models.chat import Chat
from app.models.message import Message
from app.models.outbound_call_intent import OutboundCallIntent
from app.services.call_service import apply_status_transition
from app.services.voice_service import GeminiVoiceBridge
from app.utils.auth import decode_access_token

logger = logging.getLogger(__name__)
router = APIRouter(tags=["voice"])


@router.websocket("/ws/voice/{chat_id}")
async def voice_call(websocket: WebSocket, chat_id: str):
    """
    Voice call via WebSocket binary frames.

    Protocol:
    1. Client connects with ?token=JWT
    2. Server sends {"type": "ready"} when Gemini session is up
    3. Client sends raw PCM audio as binary frames (16kHz, 16-bit, mono)
    4. Server sends back Gemini's audio responses as binary frames
    5. Client sends {"type": "end_call"} to terminate
    """
    token = websocket.query_params.get("token")
    if not token:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    user_id = decode_access_token(token)
    if user_id is None:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    await websocket.accept()
    logger.info("Voice WS accepted for chat %s", chat_id)
    call_id = websocket.query_params.get("call_id")

    async with async_session() as db:
        result = await db.execute(
            select(Chat)
            .where(Chat.id == UUID(chat_id), Chat.user_id == UUID(user_id))
        )
        chat = result.scalar_one_or_none()
        if chat is None:
            await websocket.send_text(json.dumps({"type": "error", "message": "Chat not found"}))
            await websocket.close()
            return

        result = await db.execute(select(Bot).where(Bot.id == chat.bot_id))
        bot = result.scalar_one_or_none()
        system_prompt = bot.system_prompt if bot else "You are a helpful assistant."
        voice_name = bot.voice_name if bot and bot.voice_name else "Kore"

        # Fetch conversation history
        messages_result = await db.execute(
            select(Message)
            .where(Message.chat_id == UUID(chat_id))
            .order_by(Message.created_at.asc())
        )
        messages = messages_result.scalars().all()
        conversation_history = [
            {"role": msg.role, "content": msg.content}
            for msg in messages
            if msg.content_type == "text"  # Only include text messages
        ]

        call_intent_message = None
        if call_id:
            intent_result = await db.execute(
                select(OutboundCallIntent).where(
                    OutboundCallIntent.id == UUID(call_id),
                    OutboundCallIntent.user_id == UUID(user_id),
                )
            )
            intent = intent_result.scalar_one_or_none()
            if intent:
                apply_status_transition(intent, "accepted")
                db.add(intent)
                call_intent_message = intent.ring_message

        await db.commit()

    bridge = GeminiVoiceBridge(
        system_prompt=system_prompt,
        voice_name=voice_name,
        conversation_history=conversation_history,
        call_intent_message=call_intent_message,
    )

    try:
        logger.info("Starting Gemini Live session...")
        await bridge.start_session()
        logger.info("Gemini Live session ready, notifying client")
        await websocket.send_text(json.dumps({"type": "ready"}))

        audio_chunks_received = 0
        audio_chunks_sent = 0

        async def receive_from_client():
            nonlocal audio_chunks_received
            try:
                while True:
                    data = await websocket.receive()
                    if "text" in data:
                        msg = json.loads(data["text"])
                        if msg.get("type") == "end_call":
                            logger.info("Client ended call")
                            if call_id:
                                async with async_session() as db:
                                    intent_result = await db.execute(
                                        select(OutboundCallIntent).where(
                                            OutboundCallIntent.id == UUID(call_id),
                                            OutboundCallIntent.user_id == UUID(user_id),
                                        )
                                    )
                                    intent = intent_result.scalar_one_or_none()
                                    if intent:
                                        apply_status_transition(intent, "completed", "user_end")
                                        db.add(intent)
                            break
                        if msg.get("type") == "user_turn_end":
                            logger.info("Client turn ended")
                            await bridge.end_user_turn()
                    elif "bytes" in data:
                        audio_chunks_received += 1
                        if audio_chunks_received % 50 == 1:
                            logger.info("Audio chunks from client: %d (chunk size: %d bytes)",
                                        audio_chunks_received, len(data["bytes"]))
                        await bridge.send_audio(data["bytes"])
            except WebSocketDisconnect:
                logger.info("Client disconnected")

        async def send_to_client():
            nonlocal audio_chunks_sent
            try:
                async for kind, data in bridge.receive_audio():
                    if kind == "audio":
                        audio_chunks_sent += 1
                        if audio_chunks_sent % 20 == 1:
                            logger.info("Audio chunks to client: %d (chunk size: %d bytes)",
                                        audio_chunks_sent, len(data))
                        await websocket.send_bytes(data)
                    elif kind == "transcript_user":
                        await websocket.send_text(
                            json.dumps(
                                {"type": "voice", "role": "user", "text": data}
                            )
                        )
                    elif kind == "transcript_bot":
                        await websocket.send_text(
                            json.dumps(
                                {"type": "voice", "role": "assistant", "text": data}
                            )
                        )
                    elif kind == "turn_complete":
                        logger.info("Sending turn_complete to client")
                        await websocket.send_text(json.dumps({"type": "turn_complete"}))
            except Exception as e:
                logger.error("Error in send_to_client: %s", e)

        recv_task = asyncio.create_task(receive_from_client())
        send_task = asyncio.create_task(send_to_client())

        done, pending = await asyncio.wait(
            [recv_task, send_task],
            return_when=asyncio.FIRST_COMPLETED,
        )
        for task in pending:
            task.cancel()

        logger.info("Voice call ended. Received %d chunks, sent %d chunks",
                     audio_chunks_received, audio_chunks_sent)

    except Exception as e:
        logger.error("Voice call error: %s", e, exc_info=True)
    finally:
        await bridge.close()
        try:
            await websocket.close()
        except Exception:
            pass
