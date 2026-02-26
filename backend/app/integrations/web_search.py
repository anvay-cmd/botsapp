from typing import Type

import httpx
from pydantic import BaseModel, Field

from app.integrations.base import BaseIntegrationTool


class WebSearchInput(BaseModel):
    query: str = Field(description="The search query")


class WebSearchTool(BaseIntegrationTool):
    name: str = "web_search"
    description: str = "Search the web for real-time information. Use this when you need current data, news, or facts."
    args_schema: Type[BaseModel] = WebSearchInput

    def _run(self, query: str) -> str:
        raise NotImplementedError("Use async version")

    async def _arun(self, query: str) -> str:
        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(
                    "https://www.googleapis.com/customsearch/v1",
                    params={
                        "key": self.credentials.get("api_key", ""),
                        "cx": self.credentials.get("search_engine_id", ""),
                        "q": query,
                        "num": 5,
                    },
                    timeout=10.0,
                )
                if response.status_code == 200:
                    data = response.json()
                    results = []
                    for item in data.get("items", [])[:5]:
                        results.append(f"**{item['title']}**\n{item['snippet']}\n{item['link']}")
                    return "\n\n".join(results) if results else "No results found."
                return f"Search failed with status {response.status_code}"
        except Exception as e:
            return f"Search error: {str(e)}"
