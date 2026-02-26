from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.integration import Integration
from app.models.user import User
from app.utils.deps import get_current_user

router = APIRouter(prefix="/integrations", tags=["integrations"])

AVAILABLE_INTEGRATIONS = [
    {
        "provider": "web_search",
        "name": "Web Search",
        "description": "Vertex/Gemini web search with URL scraping support",
        "icon": "search",
        "requires_oauth": False,
    },
    {
        "provider": "google_calendar",
        "name": "Google Calendar",
        "description": "Read and create calendar events",
        "icon": "calendar_today",
        "requires_oauth": True,
    },
    {
        "provider": "gmail",
        "name": "Gmail",
        "description": "Read and send emails",
        "icon": "email",
        "requires_oauth": True,
    },
    {
        "provider": "spotify",
        "name": "Spotify",
        "description": "Search and control music playback",
        "icon": "music_note",
        "requires_oauth": True,
    },
    {
        "provider": "github",
        "name": "GitHub",
        "description": "Manage repos, issues, and pull requests",
        "icon": "code",
        "requires_oauth": True,
    },
    {
        "provider": "google_drive",
        "name": "Google Drive",
        "description": "Search and read files from Drive",
        "icon": "folder",
        "requires_oauth": True,
    },
    {
        "provider": "news",
        "name": "News",
        "description": "Get latest headlines and news articles",
        "icon": "newspaper",
        "requires_oauth": False,
    },
]


@router.get("")
async def list_integrations(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Integration).where(Integration.user_id == user.id)
    )
    user_integrations = {i.provider: i for i in result.scalars().all()}

    response = []
    for integration in AVAILABLE_INTEGRATIONS:
        user_int = user_integrations.get(integration["provider"])
        response.append({
            **integration,
            "is_connected": user_int is not None and user_int.is_active if user_int else False,
            "integration_id": str(user_int.id) if user_int else None,
        })
    return response


@router.post("/{provider}/connect")
async def connect_integration(
    provider: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    valid_providers = [i["provider"] for i in AVAILABLE_INTEGRATIONS]
    if provider not in valid_providers:
        raise HTTPException(status_code=400, detail="Unknown integration provider")

    result = await db.execute(
        select(Integration).where(
            Integration.user_id == user.id,
            Integration.provider == provider,
        )
    )
    existing = result.scalar_one_or_none()

    if existing:
        existing.is_active = True
        db.add(existing)
        return {"status": "connected", "integration_id": str(existing.id)}

    integration = Integration(
        user_id=user.id,
        provider=provider,
        is_active=True,
    )
    db.add(integration)
    await db.flush()
    return {"status": "connected", "integration_id": str(integration.id)}


@router.delete("/{provider}")
async def disconnect_integration(
    provider: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Integration).where(
            Integration.user_id == user.id,
            Integration.provider == provider,
        )
    )
    integration = result.scalar_one_or_none()
    if integration is None:
        raise HTTPException(status_code=404, detail="Integration not found")

    integration.is_active = False
    db.add(integration)
    return {"status": "disconnected"}
