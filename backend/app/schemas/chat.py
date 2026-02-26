from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class ChatCreateRequest(BaseModel):
    bot_id: UUID


class ChatResponse(BaseModel):
    id: UUID
    user_id: UUID
    bot_id: UUID
    is_muted: bool
    last_message_at: datetime | None
    created_at: datetime
    bot_name: str | None = None
    bot_avatar: str | None = None
    last_message: str | None = None
    unread_count: int = 0

    model_config = {"from_attributes": True}


class MuteRequest(BaseModel):
    is_muted: bool
