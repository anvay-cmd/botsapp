from datetime import datetime
from uuid import UUID

from pydantic import BaseModel


class CallIntentResponse(BaseModel):
    id: UUID
    user_id: UUID
    chat_id: UUID
    reminder_id: UUID | None
    status: str
    ring_message: str | None
    scheduled_for: datetime | None
    ringing_at: datetime | None
    accepted_at: datetime | None
    ended_at: datetime | None
    end_reason: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class CallStatusUpdateRequest(BaseModel):
    status: str
    end_reason: str | None = None

