from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.bot import Bot
from app.models.chat import Chat
from app.models.user import User
from app.schemas.bot import BotCreateRequest, BotUpdateRequest, BotResponse, ImageGenerateRequest
from app.services.image_service import generate_bot_avatar
from app.services.proactive_service import (
    DEFAULT_PROACTIVE_MINUTES,
    upsert_proactive_job,
    remove_proactive_job,
)
from app.utils.deps import get_current_user

router = APIRouter(prefix="/bots", tags=["bots"])


def _get_proactive_minutes(bot: Bot) -> int | None:
    cfg = bot.integrations_config or {}
    val = cfg.get("proactive_minutes", DEFAULT_PROACTIVE_MINUTES)
    if val is None:
        return None
    try:
        m = int(val)
    except Exception:
        return DEFAULT_PROACTIVE_MINUTES
    return None if m <= 0 else m


def _to_bot_response(bot: Bot) -> BotResponse:
    payload = BotResponse.model_validate(bot).model_dump()
    payload["proactive_minutes"] = _get_proactive_minutes(bot)
    return BotResponse(**payload)


@router.get("", response_model=list[BotResponse])
async def list_bots(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Bot).where(Bot.creator_id == user.id))
    bots = result.scalars().all()
    return [_to_bot_response(b) for b in bots]


@router.post("", response_model=BotResponse, status_code=status.HTTP_201_CREATED)
async def create_bot(
    request: BotCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    bot = Bot(
        creator_id=user.id,
        name=request.name,
        system_prompt=request.system_prompt,
        voice_name=request.voice_name,
        integrations_config={
            **(request.integrations_config or {}),
            "proactive_minutes": request.proactive_minutes
            if request.proactive_minutes is not None
            else DEFAULT_PROACTIVE_MINUTES,
        },
    )
    db.add(bot)
    await db.flush()

    chat = Chat(user_id=user.id, bot_id=bot.id)
    db.add(chat)
    await db.flush()
    await upsert_proactive_job(bot.id, _get_proactive_minutes(bot))

    return _to_bot_response(bot)


@router.patch("/{bot_id}", response_model=BotResponse)
async def update_bot(
    bot_id: UUID,
    request: BotUpdateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Bot).where(Bot.id == bot_id, Bot.creator_id == user.id))
    bot = result.scalar_one_or_none()
    if bot is None:
        raise HTTPException(status_code=404, detail="Bot not found")

    if request.name is not None:
        bot.name = request.name
    if request.system_prompt is not None:
        bot.system_prompt = request.system_prompt
    if request.voice_name is not None:
        bot.voice_name = request.voice_name
    if request.integrations_config is not None:
        bot.integrations_config = request.integrations_config
    if request.avatar_url is not None:
        bot.avatar_url = request.avatar_url
    if request.proactive_minutes is not None:
        cfg = dict(bot.integrations_config or {})
        cfg["proactive_minutes"] = request.proactive_minutes
        bot.integrations_config = cfg
    db.add(bot)
    await db.flush()
    await upsert_proactive_job(bot.id, _get_proactive_minutes(bot))
    return _to_bot_response(bot)


@router.post("/{bot_id}/generate-image", response_model=BotResponse)
async def generate_image(
    bot_id: UUID,
    request: ImageGenerateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Bot).where(Bot.id == bot_id, Bot.creator_id == user.id))
    bot = result.scalar_one_or_none()
    if bot is None:
        raise HTTPException(status_code=404, detail="Bot not found")

    image_url = await generate_bot_avatar(request.prompt)
    bot.avatar_url = image_url
    db.add(bot)
    return _to_bot_response(bot)


@router.delete("/{bot_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_bot(
    bot_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Bot).where(Bot.id == bot_id, Bot.creator_id == user.id))
    bot = result.scalar_one_or_none()
    if bot is None:
        raise HTTPException(status_code=404, detail="Bot not found")
    if bot.is_default:
        raise HTTPException(status_code=400, detail="Cannot delete default bots")
    await remove_proactive_job(bot.id)
    await db.delete(bot)
