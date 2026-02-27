import base64
import logging
from email.mime.text import MIMEText
from typing import Any

from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build

logger = logging.getLogger(__name__)


def _get_gmail_service(access_token: str, refresh_token: str):
    """Create Gmail API service with OAuth credentials."""
    creds = Credentials(
        token=access_token,
        refresh_token=refresh_token,
        token_uri="https://oauth2.googleapis.com/token",
    )
    if creds.expired and creds.refresh_token:
        creds.refresh(Request())
    return build("gmail", "v1", credentials=creds)


async def list_emails(access_token: str, refresh_token: str, max_results: int = 10) -> dict[str, Any]:
    """List recent emails from inbox."""
    try:
        service = _get_gmail_service(access_token, refresh_token)
        results = service.users().messages().list(
            userId="me",
            maxResults=max_results,
            labelIds=["INBOX"]
        ).execute()

        messages = results.get("messages", [])
        emails = []

        for msg in messages[:max_results]:
            message = service.users().messages().get(userId="me", id=msg["id"]).execute()
            headers = message["payload"]["headers"]
            subject = next((h["value"] for h in headers if h["name"] == "Subject"), "No Subject")
            sender = next((h["value"] for h in headers if h["name"] == "From"), "Unknown")
            date = next((h["value"] for h in headers if h["name"] == "Date"), "Unknown")

            # Get email body
            body = ""
            if "parts" in message["payload"]:
                for part in message["payload"]["parts"]:
                    if part["mimeType"] == "text/plain":
                        body = base64.urlsafe_b64decode(part["body"]["data"]).decode("utf-8")
                        break
            elif "body" in message["payload"] and "data" in message["payload"]["body"]:
                body = base64.urlsafe_b64decode(message["payload"]["body"]["data"]).decode("utf-8")

            emails.append({
                "id": msg["id"],
                "subject": subject,
                "from": sender,
                "date": date,
                "snippet": message.get("snippet", ""),
                "body": body[:500] if body else message.get("snippet", "")
            })

        return {"success": True, "emails": emails, "count": len(emails)}
    except Exception as e:
        logger.error(f"Failed to list emails: {e}")
        return {"success": False, "error": str(e)}


async def search_emails(access_token: str, refresh_token: str, query: str, max_results: int = 5) -> dict[str, Any]:
    """Search emails by query."""
    try:
        service = _get_gmail_service(access_token, refresh_token)
        results = service.users().messages().list(
            userId="me",
            q=query,
            maxResults=max_results
        ).execute()

        messages = results.get("messages", [])
        emails = []

        for msg in messages[:max_results]:
            message = service.users().messages().get(userId="me", id=msg["id"]).execute()
            headers = message["payload"]["headers"]
            subject = next((h["value"] for h in headers if h["name"] == "Subject"), "No Subject")
            sender = next((h["value"] for h in headers if h["name"] == "From"), "Unknown")

            emails.append({
                "id": msg["id"],
                "subject": subject,
                "from": sender,
                "snippet": message.get("snippet", "")
            })

        return {"success": True, "emails": emails, "count": len(emails)}
    except Exception as e:
        logger.error(f"Failed to search emails: {e}")
        return {"success": False, "error": str(e)}


async def send_email(access_token: str, refresh_token: str, to: str, subject: str, body: str) -> dict[str, Any]:
    """Send an email."""
    try:
        service = _get_gmail_service(access_token, refresh_token)

        message = MIMEText(body)
        message["to"] = to
        message["subject"] = subject

        raw = base64.urlsafe_b64encode(message.as_bytes()).decode("utf-8")
        send_message = {"raw": raw}

        result = service.users().messages().send(userId="me", body=send_message).execute()

        return {"success": True, "message_id": result["id"]}
    except Exception as e:
        logger.error(f"Failed to send email: {e}")
        return {"success": False, "error": str(e)}
