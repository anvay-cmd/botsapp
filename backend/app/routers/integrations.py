from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import HTMLResponse
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import Flow
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.database import get_db
from app.models.integration import Integration
from app.models.user import User
from app.utils.auth import create_access_token
from app.utils.deps import get_current_user

settings = get_settings()

router = APIRouter(prefix="/integrations", tags=["integrations"])

AVAILABLE_INTEGRATIONS = [
    {
        "provider": "web_search",
        "name": "Web Search",
        "description": "Real-time web search powered by Google",
        "icon": "search",
        "requires_oauth": False,
    },
    {
        "provider": "gmail",
        "name": "Gmail",
        "description": "Read and send emails from your Gmail account",
        "icon": "email",
        "requires_oauth": True,
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
        await db.commit()
        return {"status": "connected", "integration_id": str(existing.id)}

    integration = Integration(
        user_id=user.id,
        provider=provider,
        is_active=True,
    )
    db.add(integration)
    await db.commit()
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
    await db.commit()
    return {"status": "disconnected"}


@router.get("/gmail/auth")
async def gmail_auth_start(user: User = Depends(get_current_user)):
    """Start Gmail OAuth flow."""
    if not settings.GOOGLE_CLIENT_ID or not settings.GOOGLE_CLIENT_SECRET:
        raise HTTPException(status_code=500, detail="Gmail OAuth not configured")

    flow = Flow.from_client_config(
        {
            "web": {
                "client_id": settings.GOOGLE_CLIENT_ID,
                "client_secret": settings.GOOGLE_CLIENT_SECRET,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
            }
        },
        scopes=[
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.send",
        ],
        redirect_uri=f"{settings.API_BASE_URL}/api/integrations/gmail/callback",
    )

    # Include user ID in state for callback
    state = create_access_token({"user_id": str(user.id), "type": "gmail_oauth"})
    authorization_url, _ = flow.authorization_url(state=state, access_type="offline", prompt="consent")

    return {"authorization_url": authorization_url}


@router.get("/gmail/callback")
async def gmail_auth_callback(
    code: str = Query(...),
    state: str = Query(...),
    db: AsyncSession = Depends(get_db),
):
    """Handle Gmail OAuth callback."""
    from app.utils.auth import decode_access_token

    # Verify state token
    user_id = decode_access_token(state)
    if not user_id:
        raise HTTPException(status_code=400, detail="Invalid state token")

    flow = Flow.from_client_config(
        {
            "web": {
                "client_id": settings.GOOGLE_CLIENT_ID,
                "client_secret": settings.GOOGLE_CLIENT_SECRET,
                "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                "token_uri": "https://oauth2.googleapis.com/token",
            }
        },
        scopes=[
            "https://www.googleapis.com/auth/gmail.readonly",
            "https://www.googleapis.com/auth/gmail.send",
        ],
        redirect_uri=f"{settings.API_BASE_URL}/api/integrations/gmail/callback",
    )

    flow.fetch_token(code=code)
    credentials = flow.credentials

    # Store credentials in integration
    result = await db.execute(
        select(Integration).where(
            Integration.user_id == UUID(user_id),
            Integration.provider == "gmail",
        )
    )
    integration = result.scalar_one_or_none()

    if integration:
        integration.credentials = {
            "access_token": credentials.token,
            "refresh_token": credentials.refresh_token,
            "token_uri": credentials.token_uri,
            "scopes": credentials.scopes,
        }
        integration.is_active = True
    else:
        integration = Integration(
            user_id=UUID(user_id),
            provider="gmail",
            credentials={
                "access_token": credentials.token,
                "refresh_token": credentials.refresh_token,
                "token_uri": credentials.token_uri,
                "scopes": credentials.scopes,
            },
            is_active=True,
        )
        db.add(integration)

    await db.commit()

    # Return HTML page for browser
    html_content = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>Gmail Connected</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            body {
                font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                display: flex;
                align-items: center;
                justify-content: center;
                height: 100vh;
                margin: 0;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            }
            .container {
                background: white;
                padding: 40px;
                border-radius: 20px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.2);
                text-align: center;
                max-width: 400px;
            }
            .success-icon {
                font-size: 64px;
                margin-bottom: 20px;
            }
            h1 {
                color: #333;
                margin-bottom: 10px;
            }
            p {
                color: #666;
                margin-bottom: 30px;
            }
            .btn {
                background: #10b981;
                color: white;
                border: none;
                padding: 12px 30px;
                border-radius: 8px;
                font-size: 16px;
                cursor: pointer;
            }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="success-icon">✅</div>
            <h1>Gmail Connected!</h1>
            <p>Your Gmail account has been successfully connected. You can now close this window and return to the app.</p>
            <button class="btn" onclick="window.close()">Close Window</button>
        </div>
    </body>
    </html>
    """
    return HTMLResponse(content=html_content)
