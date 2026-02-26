"""
Push notification service using GCP Pub/Sub + FCM.

Architecture:
1. Backend publishes notification events to a Pub/Sub topic
2. A Cloud Function subscribes to the topic and forwards to FCM
3. Flutter app receives push notifications via firebase_messaging

For MVP/development, this also supports direct FCM sending via firebase-admin SDK.

Setup Guide:
-----------
1. Create a GCP project and enable Pub/Sub + Cloud Functions + FCM APIs
2. gcloud pubsub topics create botsapp-notifications
3. Deploy the Cloud Function (see cloud_function/ directory or inline below):

   exports.sendPushNotification = async (message) => {
     const admin = require('firebase-admin');
     admin.initializeApp();
     const data = JSON.parse(Buffer.from(message.data, 'base64').toString());
     await admin.messaging().send({
       token: data.fcm_token,
       notification: { title: data.title, body: data.body },
       data: data.data,
     });
   };

4. gcloud functions deploy sendPushNotification \\
     --trigger-topic=botsapp-notifications \\
     --runtime=nodejs20

5. Set GOOGLE_APPLICATION_CREDENTIALS in .env pointing to your service account JSON
6. In Flutter: add firebase_messaging, call FirebaseMessaging.instance.getToken()
   and POST it to /api/auth/fcm-token
"""

import json
import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import httpx
from jose import jwt

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()

_pubsub_publisher = None
_fcm_app = None


def _get_pubsub_publisher():
    global _pubsub_publisher
    if _pubsub_publisher is None:
        try:
            from google.cloud import pubsub_v1
            _pubsub_publisher = pubsub_v1.PublisherClient()
        except Exception as e:
            logger.warning(f"Could not initialize Pub/Sub publisher: {e}")
    return _pubsub_publisher


def _get_fcm_app():
    global _fcm_app
    if _fcm_app is None:
        try:
            import firebase_admin
            from firebase_admin import credentials
            if settings.GOOGLE_APPLICATION_CREDENTIALS:
                cred = credentials.Certificate(settings.GOOGLE_APPLICATION_CREDENTIALS)
                _fcm_app = firebase_admin.initialize_app(cred)
            else:
                _fcm_app = firebase_admin.initialize_app()
        except Exception as e:
            logger.warning(f"Could not initialize Firebase Admin: {e}")
    return _fcm_app


def _looks_like_apns_token(token: str) -> bool:
    if not token:
        return False
    token = token.strip().lower()
    if len(token) != 64:
        return False
    return all(c in "0123456789abcdef" for c in token)


def _can_send_apns_direct() -> bool:
    return all(
        [
            settings.APNS_TEAM_ID,
            settings.APNS_KEY_ID,
            settings.APNS_AUTH_KEY_PATH,
            settings.APNS_BUNDLE_ID,
        ]
    )


def _build_apns_jwt() -> str:
    issued_at = int(datetime.now(tz=timezone.utc).timestamp())
    key_path = Path(settings.APNS_AUTH_KEY_PATH)
    if not key_path.exists():
        raise FileNotFoundError(f"APNs key not found at: {settings.APNS_AUTH_KEY_PATH}")
    private_key = key_path.read_text()
    return jwt.encode(
        {"iss": settings.APNS_TEAM_ID, "iat": issued_at},
        private_key,
        algorithm="ES256",
        headers={"kid": settings.APNS_KEY_ID},
    )


def _apns_base_url() -> str:
    if settings.APNS_USE_SANDBOX:
        return "https://api.sandbox.push.apple.com"
    return "https://api.push.apple.com"


def _absolute_avatar_url(avatar_url: Optional[str]) -> str:
    if not avatar_url:
        return ""
    url = avatar_url.strip()
    if url.startswith("http://") or url.startswith("https://"):
        return url
    if settings.PUBLIC_BASE_URL:
        base = settings.PUBLIC_BASE_URL.rstrip("/")
        path = url if url.startswith("/") else f"/{url}"
        return f"{base}{path}"
    return ""


async def send_notification_apns_direct(
    apns_token: str,
    title: str,
    body: str,
    chat_id: Optional[str] = None,
    avatar_url: Optional[str] = None,
):
    """Send standard APNs alert notification directly (no Firebase)."""
    if not _can_send_apns_direct():
        logger.warning("APNs direct notification skipped: credentials not configured")
        return

    auth_token = _build_apns_jwt()
    url = f"{_apns_base_url()}/3/device/{apns_token}"
    headers = {
        "authorization": f"bearer {auth_token}",
        "apns-topic": settings.APNS_BUNDLE_ID,
        "apns-push-type": "alert",
        "apns-priority": "10",
    }
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
            "badge": 1,
            "mutable-content": 1,
            "category": "CHAT_MESSAGE",
        },
        "chat_id": chat_id or "",
        "avatar_url": _absolute_avatar_url(avatar_url),
    }

    async with httpx.AsyncClient(timeout=8.0, http2=True) as client:
        response = await client.post(url, headers=headers, json=payload)
        if response.status_code != 200:
            logger.warning(
                "APNs direct message push failed: %s %s",
                response.status_code,
                response.text,
            )
        else:
            logger.info("APNs direct message push sent")


async def send_notification_pubsub(
    user_fcm_token: str,
    title: str,
    body: str,
    chat_id: Optional[str] = None,
    avatar_url: Optional[str] = None,
):
    """Publish a notification event to Pub/Sub for async processing."""
    if _looks_like_apns_token(user_fcm_token):
        await send_notification_apns_direct(
            apns_token=user_fcm_token,
            title=title,
            body=body,
            chat_id=chat_id,
            avatar_url=avatar_url,
        )
        return

    publisher = _get_pubsub_publisher()
    if publisher is None:
        logger.warning("Pub/Sub publisher not available, falling back to direct FCM")
        await send_notification_direct(user_fcm_token, title, body, chat_id)
        return

    topic_path = publisher.topic_path(settings.GCP_PROJECT_ID, settings.PUBSUB_TOPIC)
    message_data = json.dumps({
        "fcm_token": user_fcm_token,
        "title": title,
        "body": body,
        "data": {"chat_id": chat_id or ""},
        "avatar_url": _absolute_avatar_url(avatar_url),
    }).encode("utf-8")

    try:
        publisher.publish(topic_path, data=message_data)
        logger.info(f"Published notification to Pub/Sub for token {user_fcm_token[:20]}...")
    except Exception as e:
        logger.error(f"Failed to publish to Pub/Sub: {e}")
        await send_notification_direct(user_fcm_token, title, body, chat_id, avatar_url)


async def send_notification_direct(
    user_fcm_token: str,
    title: str,
    body: str,
    chat_id: Optional[str] = None,
    avatar_url: Optional[str] = None,
):
    """Send FCM notification directly via firebase-admin SDK (fallback/MVP)."""
    app = _get_fcm_app()
    if app is None:
        logger.warning("Firebase Admin not available, skipping notification")
        return

    try:
        from firebase_admin import messaging

        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={"chat_id": chat_id or "", "avatar_url": _absolute_avatar_url(avatar_url)},
            token=user_fcm_token,
        )
        messaging.send(message)
        logger.info(f"Sent FCM notification to {user_fcm_token[:20]}...")
    except Exception as e:
        logger.error(f"Failed to send FCM notification: {e}")
