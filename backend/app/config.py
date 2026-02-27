from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    GEMINI_API_KEY: str
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/botsapp"
    JWT_SECRET: str = "change-me-in-production-use-a-real-secret"
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_HOURS: int = 72
    GOOGLE_CLIENT_ID: str = ""
    GOOGLE_CLIENT_SECRET: str = ""
    GOOGLE_IOS_CLIENT_ID: str = ""
    GCP_PROJECT_ID: str = ""
    API_BASE_URL: str = "http://localhost:8000"
    PUBSUB_TOPIC: str = "botsapp-notifications"
    GOOGLE_APPLICATION_CREDENTIALS: str = ""
    APNS_TEAM_ID: str = ""
    APNS_KEY_ID: str = ""
    APNS_AUTH_KEY_PATH: str = ""
    APNS_BUNDLE_ID: str = ""
    APNS_USE_SANDBOX: bool = True
    UPLOAD_DIR: str = "uploads"
    CORS_ORIGINS: str = "*"
    PUBLIC_BASE_URL: str = ""

    model_config = {"env_file": ".env", "extra": "ignore"}


@lru_cache
def get_settings() -> Settings:
    return Settings()
