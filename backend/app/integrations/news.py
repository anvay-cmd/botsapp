from typing import Type

import httpx
from pydantic import BaseModel, Field

from app.integrations.base import BaseIntegrationTool


class NewsInput(BaseModel):
    query: str = Field(default="", description="Topic to search for. Leave empty for top headlines.")
    country: str = Field(default="us", description="Country code for headlines")


class NewsTool(BaseIntegrationTool):
    name: str = "news"
    description: str = "Get latest news headlines or search for news on a specific topic."
    args_schema: Type[BaseModel] = NewsInput

    def _run(self, **kwargs) -> str:
        raise NotImplementedError("Use async version")

    async def _arun(self, query: str = "", country: str = "us") -> str:
        api_key = self.credentials.get("api_key", "")
        if not api_key:
            return "News API not configured. Set NEWS_API_KEY in your environment."

        try:
            async with httpx.AsyncClient() as client:
                if query:
                    url = "https://newsapi.org/v2/everything"
                    params = {"q": query, "pageSize": 5, "apiKey": api_key, "sortBy": "publishedAt"}
                else:
                    url = "https://newsapi.org/v2/top-headlines"
                    params = {"country": country, "pageSize": 5, "apiKey": api_key}

                response = await client.get(url, params=params, timeout=10.0)
                if response.status_code == 200:
                    articles = response.json().get("articles", [])
                    if not articles:
                        return "No news articles found."
                    results = []
                    for article in articles:
                        results.append(
                            f"**{article['title']}**\n"
                            f"{article.get('description', 'No description')}\n"
                            f"Source: {article.get('source', {}).get('name', 'Unknown')}"
                        )
                    return "\n\n".join(results)
                return f"News API error: {response.status_code}"
        except Exception as e:
            return f"News error: {str(e)}"
