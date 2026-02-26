from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


class GoogleAuthRequest(BaseModel):
    id_token: str


class DevLoginRequest(BaseModel):
    email: str = "dev@botsapp.local"
    display_name: str = "Dev User"


class ProfileUpdateRequest(BaseModel):
    display_name: str | None = None
    avatar_url: str | None = None


class FCMTokenRequest(BaseModel):
    fcm_token: str


class VoIPTokenRequest(BaseModel):
    voip_token: str


class APNSTokenRequest(BaseModel):
    apns_token: str


class UserResponse(BaseModel):
    id: UUID
    google_id: str
    email: str
    display_name: str
    avatar_url: str | None
    voip_token: str | None = None
    created_at: datetime

    model_config = {"from_attributes": True}


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserResponse
