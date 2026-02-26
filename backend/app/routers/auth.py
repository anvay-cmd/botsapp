from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.bot import Bot
from app.models.chat import Chat
from app.schemas.user import (
    GoogleAuthRequest,
    DevLoginRequest,
    AuthResponse,
    UserResponse,
    ProfileUpdateRequest,
    FCMTokenRequest,
    VoIPTokenRequest,
    APNSTokenRequest,
)
from app.utils.auth import verify_google_token, create_access_token
from app.utils.deps import get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])


async def _create_default_bots_and_chats(db: AsyncSession, user: User) -> None:
    """Create the default 'You' and 'General' bots and their chats for a new user."""
    you_bot = Bot(
        creator_id=user.id,
        name="You",
        system_prompt=(
            "You are the user's personal AI assistant named 'You'. "
            "You help with personal tasks, reminders, notes, and anything the user needs. "
            "Be friendly, concise, and proactive."
        ),
        is_default=True,
    )
    general_bot = Bot(
        creator_id=user.id,
        name="General",
        system_prompt=(
            "You are a general-purpose AI assistant named 'General'. "
            "You answer questions on any topic, help with research, writing, coding, math, "
            "and general knowledge. Be thorough and helpful."
        ),
        is_default=True,
    )
    db.add_all([you_bot, general_bot])
    await db.flush()

    you_chat = Chat(user_id=user.id, bot_id=you_bot.id)
    general_chat = Chat(user_id=user.id, bot_id=general_bot.id)
    db.add_all([you_chat, general_chat])


@router.post("/google", response_model=AuthResponse)
async def google_auth(request: GoogleAuthRequest, db: AsyncSession = Depends(get_db)):
    user_info = verify_google_token(request.id_token)
    if user_info is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid Google token")

    result = await db.execute(select(User).where(User.google_id == user_info["google_id"]))
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            google_id=user_info["google_id"],
            email=user_info["email"],
            display_name=user_info["name"],
            avatar_url=user_info.get("picture"),
        )
        db.add(user)
        await db.flush()
        await _create_default_bots_and_chats(db, user)

    token = create_access_token(user.id)
    return AuthResponse(access_token=token, user=UserResponse.model_validate(user))


@router.post("/dev-login", response_model=AuthResponse)
async def dev_login(request: DevLoginRequest, db: AsyncSession = Depends(get_db)):
    """Dev-only login that bypasses Google OAuth. Do NOT use in production."""
    google_id = f"dev_{request.email}"

    result = await db.execute(select(User).where(User.google_id == google_id))
    user = result.scalar_one_or_none()

    if user is None:
        user = User(
            google_id=google_id,
            email=request.email,
            display_name=request.display_name,
        )
        db.add(user)
        await db.flush()
        await _create_default_bots_and_chats(db, user)

    token = create_access_token(user.id)
    return AuthResponse(access_token=token, user=UserResponse.model_validate(user))


@router.get("/me", response_model=UserResponse)
async def get_me(user: User = Depends(get_current_user)):
    return UserResponse.model_validate(user)


@router.patch("/me", response_model=UserResponse)
async def update_profile(
    request: ProfileUpdateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    if request.display_name is not None:
        user.display_name = request.display_name
    if request.avatar_url is not None:
        user.avatar_url = request.avatar_url
    db.add(user)
    return UserResponse.model_validate(user)


@router.post("/fcm-token")
async def update_fcm_token(
    request: FCMTokenRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user.fcm_token = request.fcm_token
    db.add(user)
    return {"status": "ok"}


@router.post("/voip-token")
async def update_voip_token(
    request: VoIPTokenRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    user.voip_token = request.voip_token
    db.add(user)
    return {"status": "ok"}


@router.post("/apns-token")
async def update_apns_token(
    request: APNSTokenRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    # Reuse fcm_token storage as generic "message push token" for iOS APNs direct path.
    user.fcm_token = request.apns_token
    db.add(user)
    return {"status": "ok"}
