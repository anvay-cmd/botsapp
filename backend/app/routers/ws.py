import json
import logging
from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import async_session
from app.models.chat import Chat
from app.models.message import Message
from app.models.user import User
from app.services.llm_service import get_ai_response_stream
from app.services.notification_service import send_notification_pubsub
from app.utils.auth import decode_access_token

logger = logging.getLogger(__name__)
router = APIRouter(tags=["websocket"])


class ConnectionManager:
    """Manages active WebSocket connections per user."""

    def __init__(self):
        self.active_connections: dict[str, list[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, user_id: str):
        await websocket.accept()
        if user_id not in self.active_connections:
            self.active_connections[user_id] = []
        self.active_connections[user_id].append(websocket)
        logger.info("WS connect user=%s total=%s", user_id, len(self.active_connections[user_id]))

    def disconnect(self, websocket: WebSocket, user_id: str):
        if user_id in self.active_connections:
            if websocket in self.active_connections[user_id]:
                self.active_connections[user_id].remove(websocket)
            if not self.active_connections[user_id]:
                del self.active_connections[user_id]
            logger.info("WS disconnect user=%s remaining=%s", user_id, len(self.active_connections.get(user_id, [])))

    async def send_to_user(self, user_id: str, message: dict) -> int:
        if user_id not in self.active_connections:
            return 0
        data = json.dumps(message, default=str)
        delivered = 0
        stale: list[WebSocket] = []
        for ws in list(self.active_connections[user_id]):
            try:
                await ws.send_text(data)
                delivered += 1
            except Exception:
                stale.append(ws)
        for ws in stale:
            self.disconnect(ws, user_id)
        return delivered

    def is_online(self, user_id: str) -> bool:
        return user_id in self.active_connections and len(self.active_connections[user_id]) > 0


manager = ConnectionManager()


async def _authenticate_ws(websocket: WebSocket) -> str | None:
    token = websocket.query_params.get("token")
    if not token:
        return None
    user_id = decode_access_token(token)
    return user_id


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    user_id = await _authenticate_ws(websocket)
    if user_id is None:
        await websocket.close(code=4001, reason="Unauthorized")
        return

    await manager.connect(websocket, user_id)
    try:
        while True:
            data = await websocket.receive_text()
            msg = json.loads(data)
            msg_type = msg.get("type")

            if msg_type == "message":
                chat_id = UUID(msg["chat_id"])
                content = msg.get("content", "")
                content_type = msg.get("content_type", "text")
                attachment_url = msg.get("attachment_url")

                async with async_session() as db:
                    result = await db.execute(
                        select(Chat)
                        .where(Chat.id == chat_id, Chat.user_id == UUID(user_id))
                        .options(selectinload(Chat.bot))
                    )
                    chat = result.scalar_one_or_none()
                    if chat is None:
                        await manager.send_to_user(user_id, {"type": "error", "message": "Chat not found"})
                        continue

                    user_msg = Message(
                        chat_id=chat_id,
                        role="user",
                        content=content,
                        content_type=content_type,
                        attachment_url=attachment_url,
                    )
                    db.add(user_msg)
                    chat.unread_count = 0
                    await db.flush()

                    await manager.send_to_user(user_id, {
                        "type": "message",
                        "chat_id": str(chat_id),
                        "message_id": str(user_msg.id),
                        "role": "user",
                        "content": content,
                        "content_type": content_type,
                        "attachment_url": attachment_url,
                        "created_at": user_msg.created_at.isoformat(),
                    })

                    await manager.send_to_user(user_id, {
                        "type": "typing",
                        "chat_id": str(chat_id),
                    })

                    full_response = ""
                    try:
                        async for token in get_ai_response_stream(db, chat_id, chat.bot_id, content, user_id=UUID(user_id)):
                            full_response += token
                            await manager.send_to_user(user_id, {
                                "type": "stream",
                                "chat_id": str(chat_id),
                                "token": token,
                            })
                    except Exception as llm_err:
                        logger.exception("LLM streaming error: %s", llm_err)
                        await manager.send_to_user(user_id, {
                            "type": "error",
                            "chat_id": str(chat_id),
                            "message": f"AI error: {llm_err}",
                        })

                    ai_msg = Message(
                        chat_id=chat_id,
                        role="assistant",
                        content=full_response,
                        content_type="text",
                    )
                    db.add(ai_msg)
                    chat.last_message_at = datetime.utcnow()
                    chat.unread_count = (chat.unread_count or 0) + 1
                    db.add(chat)
                    await db.commit()

                    # Offline push notification for new AI replies.
                    user_online = manager.is_online(user_id)
                    if (
                        not user_online
                        and not chat.is_muted
                        and full_response.strip()
                    ):
                        user_result = await db.execute(
                            select(User).where(User.id == UUID(user_id))
                        )
                        db_user = user_result.scalar_one_or_none()
                        if db_user and db_user.fcm_token:
                            title = chat.bot.name if chat.bot else "New message"
                            body = full_response[:160]
                            await send_notification_pubsub(
                                user_fcm_token=db_user.fcm_token,
                                title=title,
                                body=body,
                                chat_id=str(chat_id),
                                avatar_url=chat.bot.avatar_url if chat.bot else None,
                            )

                    await manager.send_to_user(user_id, {
                        "type": "message_complete",
                        "chat_id": str(chat_id),
                        "message_id": str(ai_msg.id),
                        "role": "assistant",
                        "content": full_response,
                        "content_type": "text",
                        "created_at": ai_msg.created_at.isoformat(),
                    })

            elif msg_type == "typing":
                pass  # Could broadcast typing indicators

    except WebSocketDisconnect:
        manager.disconnect(websocket, user_id)
    except Exception:
        manager.disconnect(websocket, user_id)
