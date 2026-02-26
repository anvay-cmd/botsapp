from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, desc
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models.chat import Chat
from app.models.message import Message
from app.models.user import User
from app.schemas.chat import ChatCreateRequest, ChatResponse, MuteRequest
from app.schemas.message import MessageResponse
from app.utils.deps import get_current_user

router = APIRouter(prefix="/chats", tags=["chats"])


@router.get("", response_model=list[ChatResponse])
async def list_chats(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Chat)
        .where(Chat.user_id == user.id)
        .options(selectinload(Chat.bot), selectinload(Chat.messages))
        .order_by(desc(Chat.last_message_at))
    )
    chats = result.scalars().all()

    responses = []
    for chat in chats:
        last_msg = None
        if chat.messages:
            sorted_msgs = sorted(chat.messages, key=lambda m: m.created_at, reverse=True)
            if sorted_msgs:
                latest = sorted_msgs[0]
                if latest.content_type == "voice_call":
                    last_msg = "Voice call"
                else:
                    last_msg = latest.content[:100]
        responses.append(
            ChatResponse(
                id=chat.id,
                user_id=chat.user_id,
                bot_id=chat.bot_id,
                is_muted=chat.is_muted,
                unread_count=chat.unread_count or 0,
                last_message_at=chat.last_message_at,
                created_at=chat.created_at,
                bot_name=chat.bot.name if chat.bot else None,
                bot_avatar=chat.bot.avatar_url if chat.bot else None,
                last_message=last_msg,
            )
        )
    return responses


@router.post("", response_model=ChatResponse, status_code=status.HTTP_201_CREATED)
async def create_chat(
    request: ChatCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    chat = Chat(user_id=user.id, bot_id=request.bot_id)
    db.add(chat)
    await db.flush()
    await db.refresh(chat, ["bot"])
    return ChatResponse(
        id=chat.id,
        user_id=chat.user_id,
        bot_id=chat.bot_id,
        is_muted=chat.is_muted,
        unread_count=chat.unread_count or 0,
        last_message_at=chat.last_message_at,
        created_at=chat.created_at,
        bot_name=chat.bot.name if chat.bot else None,
        bot_avatar=chat.bot.avatar_url if chat.bot else None,
    )


@router.get("/{chat_id}/messages", response_model=list[MessageResponse])
async def get_messages(
    chat_id: UUID,
    offset: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Chat).where(Chat.id == chat_id, Chat.user_id == user.id))
    chat = result.scalar_one_or_none()
    if chat is None:
        raise HTTPException(status_code=404, detail="Chat not found")
    if chat.unread_count:
        chat.unread_count = 0
        db.add(chat)

    result = await db.execute(
        select(Message)
        .where(Message.chat_id == chat_id)
        .order_by(desc(Message.created_at))
        .offset(offset)
        .limit(limit)
    )
    messages = result.scalars().all()
    return [MessageResponse.model_validate(m) for m in reversed(messages)]


@router.patch("/{chat_id}/mute", response_model=ChatResponse)
async def mute_chat(
    chat_id: UUID,
    request: MuteRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Chat).where(Chat.id == chat_id, Chat.user_id == user.id).options(selectinload(Chat.bot))
    )
    chat = result.scalar_one_or_none()
    if chat is None:
        raise HTTPException(status_code=404, detail="Chat not found")

    chat.is_muted = request.is_muted
    db.add(chat)
    return ChatResponse(
        id=chat.id,
        user_id=chat.user_id,
        bot_id=chat.bot_id,
        is_muted=chat.is_muted,
        unread_count=chat.unread_count or 0,
        last_message_at=chat.last_message_at,
        created_at=chat.created_at,
        bot_name=chat.bot.name if chat.bot else None,
        bot_avatar=chat.bot.avatar_url if chat.bot else None,
    )


@router.post("/{chat_id}/read", status_code=status.HTTP_204_NO_CONTENT)
async def mark_chat_read(
    chat_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Chat).where(Chat.id == chat_id, Chat.user_id == user.id))
    chat = result.scalar_one_or_none()
    if chat is None:
        raise HTTPException(status_code=404, detail="Chat not found")
    chat.unread_count = 0
    db.add(chat)


@router.delete("/{chat_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_chat(
    chat_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Chat).where(Chat.id == chat_id, Chat.user_id == user.id))
    chat = result.scalar_one_or_none()
    if chat is None:
        raise HTTPException(status_code=404, detail="Chat not found")
    await db.delete(chat)
