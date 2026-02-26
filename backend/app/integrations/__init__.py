from app.integrations.web_search import WebSearchTool
from app.integrations.google_calendar import GoogleCalendarTool
from app.integrations.gmail import GmailTool
from app.integrations.spotify import SpotifyTool
from app.integrations.github import GitHubTool
from app.integrations.google_drive import GoogleDriveTool
from app.integrations.news import NewsTool
from app.integrations.reminders import ReminderTool

ALL_TOOLS = {
    "web_search": WebSearchTool,
    "google_calendar": GoogleCalendarTool,
    "gmail": GmailTool,
    "spotify": SpotifyTool,
    "github": GitHubTool,
    "google_drive": GoogleDriveTool,
    "news": NewsTool,
    "reminders": ReminderTool,
}
