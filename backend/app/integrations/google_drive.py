from typing import Type

import httpx
from pydantic import BaseModel, Field

from app.integrations.base import BaseIntegrationTool


class DriveInput(BaseModel):
    action: str = Field(description="Action: 'search' to search files, 'list' to list recent files")
    query: str = Field(default="", description="Search query (for search)")
    max_results: int = Field(default=10, description="Max files to return")


class GoogleDriveTool(BaseIntegrationTool):
    name: str = "google_drive"
    description: str = "Interact with Google Drive. Search or list files."
    args_schema: Type[BaseModel] = DriveInput

    def _run(self, **kwargs) -> str:
        raise NotImplementedError("Use async version")

    async def _arun(self, action: str = "list", query: str = "", max_results: int = 10) -> str:
        access_token = self.credentials.get("access_token", "")
        if not access_token:
            return "Google Drive not connected. Please connect it in Integrations settings."

        headers = {"Authorization": f"Bearer {access_token}"}

        try:
            async with httpx.AsyncClient() as client:
                params = {"pageSize": max_results, "fields": "files(id,name,mimeType,modifiedTime)"}

                if action == "search" and query:
                    params["q"] = f"name contains '{query}'"
                elif action == "list":
                    params["orderBy"] = "modifiedTime desc"

                response = await client.get(
                    "https://www.googleapis.com/drive/v3/files",
                    headers=headers,
                    params=params,
                    timeout=10.0,
                )
                if response.status_code == 200:
                    files = response.json().get("files", [])
                    if not files:
                        return "No files found."
                    results = [f"- {f['name']} ({f['mimeType']})" for f in files]
                    return "\n".join(results)
                return f"Drive error: {response.status_code}"
        except Exception as e:
            return f"Drive error: {str(e)}"
