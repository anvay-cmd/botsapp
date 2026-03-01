from uuid import UUID

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.chat import Chat
from app.models.lifecycle_message import LifecycleMessage
from app.models.user import User
from app.schemas.lifecycle import LifecycleMessageResponse
from app.utils.deps import get_current_user

router = APIRouter(prefix="/lifecycle", tags=["lifecycle"])


@router.get("/chats/{chat_id}/messages", response_model=list[LifecycleMessageResponse])
async def get_lifecycle_messages(
    chat_id: UUID,
    session_id: int | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get lifecycle messages for a chat, optionally filtered by session_id"""
    # Verify chat belongs to user
    chat_result = await db.execute(select(Chat).where(Chat.id == chat_id, Chat.user_id == user.id))
    chat = chat_result.scalar_one_or_none()
    if chat is None:
        return []

    query = select(LifecycleMessage).where(LifecycleMessage.chat_id == chat_id)
    if session_id is not None:
        query = query.where(LifecycleMessage.session_id == session_id)

    query = query.order_by(LifecycleMessage.created_at.asc())

    result = await db.execute(query)
    messages = result.scalars().all()
    return [LifecycleMessageResponse.model_validate(msg) for msg in messages]
