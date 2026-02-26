from typing import Type

import httpx
from pydantic import BaseModel, Field

from app.integrations.base import BaseIntegrationTool


class SpotifyInput(BaseModel):
    action: str = Field(description="Action: 'search' to search tracks, 'playing' to get current track")
    query: str = Field(default="", description="Search query (for search)")


class SpotifyTool(BaseIntegrationTool):
    name: str = "spotify"
    description: str = "Interact with Spotify. Search for songs/artists or check what's currently playing."
    args_schema: Type[BaseModel] = SpotifyInput

    def _run(self, **kwargs) -> str:
        raise NotImplementedError("Use async version")

    async def _arun(self, action: str = "search", query: str = "") -> str:
        access_token = self.credentials.get("access_token", "")
        if not access_token:
            return "Spotify not connected. Please connect it in Integrations settings."

        headers = {"Authorization": f"Bearer {access_token}"}

        try:
            async with httpx.AsyncClient() as client:
                if action == "search" and query:
                    response = await client.get(
                        "https://api.spotify.com/v1/search",
                        headers=headers,
                        params={"q": query, "type": "track", "limit": 5},
                        timeout=10.0,
                    )
                    if response.status_code == 200:
                        tracks = response.json().get("tracks", {}).get("items", [])
                        results = []
                        for track in tracks:
                            artists = ", ".join(a["name"] for a in track["artists"])
                            results.append(f"- {track['name']} by {artists}")
                        return "\n".join(results) if results else "No tracks found."
                    return f"Search failed: {response.status_code}"

                elif action == "playing":
                    response = await client.get(
                        "https://api.spotify.com/v1/me/player/currently-playing",
                        headers=headers,
                        timeout=10.0,
                    )
                    if response.status_code == 200:
                        data = response.json()
                        if data and data.get("item"):
                            track = data["item"]
                            artists = ", ".join(a["name"] for a in track["artists"])
                            return f"Now playing: {track['name']} by {artists}"
                        return "Nothing is currently playing."
                    return "Could not get current playback."

                return f"Unknown action: {action}"
        except Exception as e:
            return f"Spotify error: {str(e)}"
