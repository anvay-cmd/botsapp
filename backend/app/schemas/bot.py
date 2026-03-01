from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class BotCreateRequest(BaseModel):
    name: str
    system_prompt: str = "You are a helpful AI assistant."
    voice_name: str = "Kore"
    integrations_config: dict | None = None
    proactive_minutes: int | None = 0
    proactive_interval_minutes: int | None = None  # T - proactive interval, None = never
    proactive_max_messages: int | None = 5  # M - max messages before user response
    proactivity_prompt: str | None = None  # Custom prompt for proactive checks


class BotUpdateRequest(BaseModel):
    name: str | None = None
    system_prompt: str | None = None
    voice_name: str | None = None
    integrations_config: dict | None = None
    avatar_url: str | None = None
    proactive_minutes: int | None = None
    proactive_interval_minutes: int | None = None
    proactive_max_messages: int | None = None
    proactivity_prompt: str | None = None


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
    proactive_interval_minutes: int | None = None
    proactive_max_messages: int | None = 5
    proactivity_prompt: str | None = None
    is_default: bool
    created_at: datetime

    model_config = {"from_attributes": True}
