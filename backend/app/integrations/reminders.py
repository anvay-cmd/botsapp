from datetime import datetime, timezone
from typing import Type
from uuid import UUID

from pydantic import BaseModel, Field

from app.integrations.base import BaseIntegrationTool


class ReminderInput(BaseModel):
    message: str = Field(description="The reminder message")
    trigger_at: str = Field(description="When to trigger the reminder, in ISO 8601 format (e.g. 2025-12-31T10:00:00)")
    reminder_type: str = Field(default="message", description="Type: 'message' for text notification, 'call' for voice call")


class ReminderTool(BaseIntegrationTool):
    name: str = "reminders"
    description: str = (
        "Set a reminder for the user. The reminder will notify them via message or initiate a voice call "
        "at the specified time. Always confirm the time with the user before setting."
    )
    args_schema: Type[BaseModel] = ReminderInput
    chat_id: str = ""

    def _run(self, **kwargs) -> str:
        raise NotImplementedError("Use async version")

    async def _arun(
        self,
        message: str,
        trigger_at: str,
        reminder_type: str = "message",
    ) -> str:
        try:
            trigger_time = datetime.fromisoformat(trigger_at)
        except ValueError:
            return f"Invalid time format: {trigger_at}. Use ISO 8601 format."

        # Require explicit timezone to avoid accidental local-time ambiguity.
        if trigger_time.tzinfo is None:
            return (
                "Please include timezone in trigger_at (for example: "
                "2026-03-01T10:30:00+05:30 or 2026-03-01T05:00:00Z)."
            )
        trigger_time = trigger_time.astimezone(timezone.utc).replace(tzinfo=None)

        if trigger_time <= datetime.utcnow():
            return "The reminder time must be in the future."

        try:
            from app.database import async_session
            from app.models.reminder import Reminder
            from app.services.reminder_service import schedule_reminder

            async with async_session() as db:
                if reminder_type not in {"message", "call"}:
                    return "Invalid reminder_type. Use 'message' or 'call'."
                reminder = Reminder(
                    chat_id=UUID(self.chat_id),
                    user_id=UUID(self.user_id),
                    message=message,
                    reminder_type=reminder_type,
                    trigger_at=trigger_time,
                )
                db.add(reminder)
                await db.commit()
                await db.refresh(reminder)
                await schedule_reminder(reminder)

            return f"Reminder set for {trigger_time.strftime('%B %d, %Y at %I:%M %p')}: {message}"
        except Exception as e:
            return f"Failed to set reminder: {str(e)}"
