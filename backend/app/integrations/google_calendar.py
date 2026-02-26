from typing import Type

import httpx
from pydantic import BaseModel, Field

from app.integrations.base import BaseIntegrationTool


class CalendarInput(BaseModel):
    action: str = Field(description="Action: 'list' to list events, 'create' to create an event")
    summary: str = Field(default="", description="Event title (for create)")
    start_time: str = Field(default="", description="Start time ISO format (for create)")
    end_time: str = Field(default="", description="End time ISO format (for create)")
    max_results: int = Field(default=10, description="Max events to return (for list)")


class GoogleCalendarTool(BaseIntegrationTool):
    name: str = "google_calendar"
    description: str = "Interact with Google Calendar. List upcoming events or create new ones."
    args_schema: Type[BaseModel] = CalendarInput

    def _run(self, **kwargs) -> str:
        raise NotImplementedError("Use async version")

    async def _arun(
        self,
        action: str = "list",
        summary: str = "",
        start_time: str = "",
        end_time: str = "",
        max_results: int = 10,
    ) -> str:
        access_token = self.credentials.get("access_token", "")
        if not access_token:
            return "Google Calendar not connected. Please connect it in Integrations settings."

        headers = {"Authorization": f"Bearer {access_token}"}

        try:
            async with httpx.AsyncClient() as client:
                if action == "list":
                    response = await client.get(
                        "https://www.googleapis.com/calendar/v3/calendars/primary/events",
                        headers=headers,
                        params={"maxResults": max_results, "orderBy": "startTime", "singleEvents": True},
                        timeout=10.0,
                    )
                    if response.status_code == 200:
                        events = response.json().get("items", [])
                        if not events:
                            return "No upcoming events."
                        results = []
                        for event in events:
                            start = event.get("start", {}).get("dateTime", event.get("start", {}).get("date", ""))
                            results.append(f"- {event.get('summary', 'Untitled')} at {start}")
                        return "\n".join(results)
                    return f"Failed to fetch events: {response.status_code}"

                elif action == "create":
                    body = {
                        "summary": summary,
                        "start": {"dateTime": start_time},
                        "end": {"dateTime": end_time},
                    }
                    response = await client.post(
                        "https://www.googleapis.com/calendar/v3/calendars/primary/events",
                        headers=headers,
                        json=body,
                        timeout=10.0,
                    )
                    if response.status_code in (200, 201):
                        return f"Event '{summary}' created successfully."
                    return f"Failed to create event: {response.status_code}"

                return f"Unknown action: {action}"
        except Exception as e:
            return f"Calendar error: {str(e)}"
