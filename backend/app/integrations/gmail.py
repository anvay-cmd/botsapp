import base64
from typing import Type

import httpx
from pydantic import BaseModel, Field

from app.integrations.base import BaseIntegrationTool


class GmailInput(BaseModel):
    action: str = Field(description="Action: 'list' to list recent emails, 'send' to send an email")
    to: str = Field(default="", description="Recipient email (for send)")
    subject: str = Field(default="", description="Email subject (for send)")
    body: str = Field(default="", description="Email body (for send)")
    max_results: int = Field(default=5, description="Max emails to return (for list)")


class GmailTool(BaseIntegrationTool):
    name: str = "gmail"
    description: str = "Interact with Gmail. List recent emails or send new ones."
    args_schema: Type[BaseModel] = GmailInput

    def _run(self, **kwargs) -> str:
        raise NotImplementedError("Use async version")

    async def _arun(
        self,
        action: str = "list",
        to: str = "",
        subject: str = "",
        body: str = "",
        max_results: int = 5,
    ) -> str:
        access_token = self.credentials.get("access_token", "")
        if not access_token:
            return "Gmail not connected. Please connect it in Integrations settings."

        headers = {"Authorization": f"Bearer {access_token}"}

        try:
            async with httpx.AsyncClient() as client:
                if action == "list":
                    response = await client.get(
                        "https://www.googleapis.com/gmail/v1/users/me/messages",
                        headers=headers,
                        params={"maxResults": max_results},
                        timeout=10.0,
                    )
                    if response.status_code == 200:
                        messages = response.json().get("messages", [])
                        results = []
                        for msg in messages[:max_results]:
                            detail = await client.get(
                                f"https://www.googleapis.com/gmail/v1/users/me/messages/{msg['id']}",
                                headers=headers,
                                params={"format": "metadata", "metadataHeaders": ["Subject", "From"]},
                                timeout=10.0,
                            )
                            if detail.status_code == 200:
                                headers_data = detail.json().get("payload", {}).get("headers", [])
                                subj = next((h["value"] for h in headers_data if h["name"] == "Subject"), "No subject")
                                frm = next((h["value"] for h in headers_data if h["name"] == "From"), "Unknown")
                                results.append(f"- From: {frm}\n  Subject: {subj}")
                        return "\n".join(results) if results else "No emails found."
                    return f"Failed to list emails: {response.status_code}"

                elif action == "send":
                    raw_message = f"To: {to}\r\nSubject: {subject}\r\n\r\n{body}"
                    encoded = base64.urlsafe_b64encode(raw_message.encode()).decode()
                    response = await client.post(
                        "https://www.googleapis.com/gmail/v1/users/me/messages/send",
                        headers=headers,
                        json={"raw": encoded},
                        timeout=10.0,
                    )
                    if response.status_code in (200, 201):
                        return f"Email sent to {to} successfully."
                    return f"Failed to send email: {response.status_code}"

                return f"Unknown action: {action}"
        except Exception as e:
            return f"Gmail error: {str(e)}"
