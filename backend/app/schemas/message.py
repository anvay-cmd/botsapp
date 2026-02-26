from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class MessageCreateRequest(BaseModel):
    content: str
    content_type: str = "text"
    attachment_url: str | None = None


class MessageResponse(BaseModel):
    id: UUID
    chat_id: UUID
    role: str
    content: str
    content_type: str
    attachment_url: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class WSMessage(BaseModel):
    type: str  # "message", "typing", "stop_typing"
    chat_id: UUID | None = None
    content: str | None = None
    content_type: str = "text"
    attachment_url: str | None = None
