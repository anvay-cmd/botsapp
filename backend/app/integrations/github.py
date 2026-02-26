from typing import Type

import httpx
from pydantic import BaseModel, Field

from app.integrations.base import BaseIntegrationTool


class GitHubInput(BaseModel):
    action: str = Field(description="Action: 'repos' to list repos, 'issues' to list issues, 'create_issue' to create issue")
    repo: str = Field(default="", description="Repository in owner/name format")
    title: str = Field(default="", description="Issue title (for create_issue)")
    body: str = Field(default="", description="Issue body (for create_issue)")


class GitHubTool(BaseIntegrationTool):
    name: str = "github"
    description: str = "Interact with GitHub. List repositories, view issues, or create new issues."
    args_schema: Type[BaseModel] = GitHubInput

    def _run(self, **kwargs) -> str:
        raise NotImplementedError("Use async version")

    async def _arun(
        self,
        action: str = "repos",
        repo: str = "",
        title: str = "",
        body: str = "",
    ) -> str:
        access_token = self.credentials.get("access_token", "")
        if not access_token:
            return "GitHub not connected. Please connect it in Integrations settings."

        headers = {
            "Authorization": f"token {access_token}",
            "Accept": "application/vnd.github.v3+json",
        }

        try:
            async with httpx.AsyncClient() as client:
                if action == "repos":
                    response = await client.get(
                        "https://api.github.com/user/repos",
                        headers=headers,
                        params={"sort": "updated", "per_page": 10},
                        timeout=10.0,
                    )
                    if response.status_code == 200:
                        repos = response.json()
                        results = [f"- {r['full_name']} ({'private' if r['private'] else 'public'})" for r in repos]
                        return "\n".join(results) if results else "No repositories found."
                    return f"Failed to list repos: {response.status_code}"

                elif action == "issues" and repo:
                    response = await client.get(
                        f"https://api.github.com/repos/{repo}/issues",
                        headers=headers,
                        params={"state": "open", "per_page": 10},
                        timeout=10.0,
                    )
                    if response.status_code == 200:
                        issues = response.json()
                        results = [f"- #{i['number']}: {i['title']}" for i in issues]
                        return "\n".join(results) if results else "No open issues."
                    return f"Failed to list issues: {response.status_code}"

                elif action == "create_issue" and repo and title:
                    response = await client.post(
                        f"https://api.github.com/repos/{repo}/issues",
                        headers=headers,
                        json={"title": title, "body": body},
                        timeout=10.0,
                    )
                    if response.status_code == 201:
                        issue = response.json()
                        return f"Issue created: #{issue['number']} - {issue['title']}"
                    return f"Failed to create issue: {response.status_code}"

                return f"Unknown action: {action}"
        except Exception as e:
            return f"GitHub error: {str(e)}"
