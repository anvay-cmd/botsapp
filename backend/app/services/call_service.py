import asyncio
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from uuid import UUID

import httpx
from jose import jwt
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.outbound_call_intent import OutboundCallIntent

logger = logging.getLogger(__name__)
settings = get_settings()

CALL_METRICS: dict[str, int] = {
    "scheduled": 0,
    "push_sent": 0,
    "push_failed": 0,
    "accepted": 0,
    "missed": 0,
    "completed": 0,
}


def _inc(metric: str) -> None:
    CALL_METRICS[metric] = CALL_METRICS.get(metric, 0) + 1


def _build_apns_jwt() -> str:
    issued_at = int(datetime.now(tz=timezone.utc).timestamp())
    key_path = Path(settings.APNS_AUTH_KEY_PATH)
    if not key_path.exists():
        raise FileNotFoundError(f"APNs key not found at: {settings.APNS_AUTH_KEY_PATH}")
    private_key = key_path.read_text()
    token = jwt.encode(
        {"iss": settings.APNS_TEAM_ID, "iat": issued_at},
        private_key,
        algorithm="ES256",
        headers={"kid": settings.APNS_KEY_ID},
    )
    return token


def _apns_base_url() -> str:
    if settings.APNS_USE_SANDBOX:
        return "https://api.sandbox.push.apple.com"
    return "https://api.push.apple.com"


def can_send_voip_push() -> bool:
    return all(
        [
            settings.APNS_TEAM_ID,
            settings.APNS_KEY_ID,
            settings.APNS_AUTH_KEY_PATH,
            settings.APNS_BUNDLE_ID,
        ]
    )


def build_call_payload(
    *,
    call_id: str,
    chat_id: str,
    bot_name: str,
    bot_avatar: str | None,
    message: str | None,
) -> dict[str, Any]:
    return {
        "aps": {
            "alert": {"title": bot_name, "body": message or "Scheduled AI call"},
            "sound": "default",
            "content-available": 1,
        },
        "call": {
            "call_id": call_id,
            "chat_id": chat_id,
            "bot_name": bot_name,
            "bot_avatar": bot_avatar or "",
            "message": message or "",
        },
    }


async def send_voip_push(
    *,
    voip_token: str,
    payload: dict[str, Any],
    retries: int = 3,
) -> bool:
    if not can_send_voip_push():
        logger.warning("APNs VoIP credentials are not configured")
        return False

    auth_token = _build_apns_jwt()
    topic = f"{settings.APNS_BUNDLE_ID}.voip"
    url = f"{_apns_base_url()}/3/device/{voip_token}"
    headers = {
        "authorization": f"bearer {auth_token}",
        "apns-topic": topic,
        "apns-push-type": "voip",
        "apns-priority": "10",
    }

    backoff = 0.25
    # APNs provider API requires HTTP/2.
    async with httpx.AsyncClient(timeout=8.0, http2=True) as client:
        for attempt in range(1, retries + 1):
            try:
                response = await client.post(url, headers=headers, json=payload)
                if response.status_code == 200:
                    _inc("push_sent")
                    return True
                logger.warning(
                    "APNs VoIP push failed (attempt %d/%d): %s %s",
                    attempt,
                    retries,
                    response.status_code,
                    response.text,
                )
            except Exception as e:
                logger.warning("APNs VoIP push exception (attempt %d/%d): %s", attempt, retries, e)
            if attempt < retries:
                await asyncio.sleep(backoff)
                backoff *= 2

    _inc("push_failed")
    return False


async def create_call_intent(
    db: AsyncSession,
    *,
    user_id: UUID,
    chat_id: UUID,
    reminder_id: UUID | None,
    ring_message: str | None,
    scheduled_for: datetime | None,
) -> OutboundCallIntent:
    intent = OutboundCallIntent(
        user_id=user_id,
        chat_id=chat_id,
        reminder_id=reminder_id,
        status="queued",
        ring_message=ring_message,
        scheduled_for=scheduled_for,
    )
    db.add(intent)
    await db.flush()
    _inc("scheduled")
    return intent


def apply_status_transition(intent: OutboundCallIntent, status: str, end_reason: str | None = None) -> None:
    now = datetime.utcnow()
    intent.status = status
    if status == "ringing":
        intent.ringing_at = now
    elif status == "accepted":
        intent.accepted_at = now
        _inc("accepted")
    elif status in {"ended", "completed"}:
        intent.ended_at = now
        intent.end_reason = end_reason
        _inc("completed")
    elif status in {"missed", "declined", "failed"}:
        intent.ended_at = now
        intent.end_reason = end_reason or status
        _inc("missed")
