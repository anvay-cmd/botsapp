from langchain_core.tools import BaseTool


class BaseIntegrationTool(BaseTool):
    """Base class for all BotsApp integration tools."""

    user_id: str = ""
    credentials: dict = {}

    class Config:
        arbitrary_types_allowed = True
