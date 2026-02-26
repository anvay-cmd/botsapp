from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class BotCreateRequest(BaseModel):
    name: str
    system_prompt: str = "You are a helpful AI assistant."
    voice_name: str = "Kore"
    integrations_config: dict | None = None
    proactive_minutes: int | None = 0


class BotUpdateRequest(BaseModel):
    name: str | None = None
    system_prompt: str | None = None
    voice_name: str | None = None
    integrations_config: dict | None = None
    avatar_url: str | None = None
    proactive_minutes: int | None = None


class ImageGenerateRequest(BaseModel):
    prompt: str


class BotResponse(BaseModel):
    id: UUID
    creator_id: UUID
    name: str
    avatar_url: str | None
    system_prompt: str
    voice_name: str
    integrations_config: dict | None
    proactive_minutes: int | None = 0
    is_default: bool
    created_at: datetime

    model_config = {"from_attributes": True}
