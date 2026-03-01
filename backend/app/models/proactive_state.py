import uuid
from datetime import datetime

from sqlalchemy import Integer, DateTime, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class ProactiveState(Base):
    """Tracks proactive messaging state per chat"""
    __tablename__ = "proactive_states"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    chat_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("chats.id"), unique=True)
    message_count: Mapped[int] = mapped_column(Integer, default=0)  # Count of proactive messages sent
    session_counter: Mapped[int] = mapped_column(Integer, default=0)  # Incremental counter for lifecycle sessions
    last_reset_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)

    chat = relationship("Chat", foreign_keys=[chat_id])
