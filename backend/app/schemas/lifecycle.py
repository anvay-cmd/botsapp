from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class LifecycleMessageResponse(BaseModel):
    id: UUID
    chat_id: UUID
    bot_id: UUID
    session_id: int
    role: str
    content: str
    content_type: str
    created_at: datetime

    model_config = {"from_attributes": True}
