import logging
from datetime import datetime, timedelta
from uuid import UUID

from jose import JWTError, jwt
from google.oauth2 import id_token as google_id_token
from google.auth.transport import requests as google_requests

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()


def create_access_token(user_id: UUID) -> str:
    expire = datetime.utcnow() + timedelta(hours=settings.JWT_EXPIRATION_HOURS)
    payload = {"sub": str(user_id), "exp": expire}
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)


def decode_access_token(token: str) -> str | None:
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
        return payload.get("sub")
    except JWTError:
        return None


def verify_google_token(token: str) -> dict | None:
    """Verify Google ID token and return user info dict."""
    audiences = [
        cid for cid in [settings.GOOGLE_CLIENT_ID, settings.GOOGLE_IOS_CLIENT_ID] if cid
    ]
    logger.info(
        "Verifying Google token, allowed audiences=%s",
        [a[:20] + "..." for a in audiences],
    )
    try:
        if not audiences:
            logger.error("Google token verification failed: no GOOGLE_CLIENT_ID configured")
            return None
        idinfo = google_id_token.verify_oauth2_token(
            token,
            google_requests.Request(),
            audiences,
        )
        logger.info(f"Token verified for {idinfo.get('email')}")
        return {
            "google_id": idinfo["sub"],
            "email": idinfo["email"],
            "name": idinfo.get("name", idinfo["email"].split("@")[0]),
            "picture": idinfo.get("picture"),
        }
    except Exception as e:
        logger.error(f"Google token verification failed: {type(e).__name__}: {e}")
        return None
