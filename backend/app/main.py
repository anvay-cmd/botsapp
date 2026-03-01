import logging
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from sqlalchemy import text

logging.basicConfig(level=logging.INFO)
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import get_settings
from app.database import async_session
from app.routers import auth, chats, bots, integrations, ws, voice, uploads, calls, schedules, lifecycle
from app.services.reminder_service import start_scheduler, stop_scheduler, load_pending_reminders
from app.services.proactive_service import load_proactive_jobs

settings = get_settings()


@asynccontextmanager
async def lifespan(app: FastAPI):
    os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
    # Lightweight schema safety for local/dev where migrations may lag.
    async with async_session() as db:
        await db.execute(text("ALTER TABLE chats ADD COLUMN IF NOT EXISTS unread_count INTEGER DEFAULT 0"))
        await db.commit()
    start_scheduler()
    await load_pending_reminders()
    await load_proactive_jobs()
    yield
    stop_scheduler()


app = FastAPI(
    title="BotsApp API",
    description="WhatsApp-clone for AI chatbots",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS.split(","),
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api")
app.include_router(chats.router, prefix="/api")
app.include_router(bots.router, prefix="/api")
app.include_router(integrations.router, prefix="/api")
app.include_router(uploads.router, prefix="/api")
app.include_router(calls.router, prefix="/api")
app.include_router(schedules.router, prefix="/api")
app.include_router(lifecycle.router, prefix="/api")
app.include_router(ws.router)
app.include_router(voice.router)

os.makedirs(settings.UPLOAD_DIR, exist_ok=True)
app.mount("/uploads", StaticFiles(directory=settings.UPLOAD_DIR), name="uploads")


@app.get("/health")
async def health():
    return {"status": "ok"}
