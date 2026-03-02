import uuid
from datetime import datetime

from sqlalchemy import String, Float, Integer, DateTime, ForeignKey, Boolean
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base


class Geofence(Base):
    __tablename__ = "geofences"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    name: Mapped[str] = mapped_column(String(255))
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    radius: Mapped[float] = mapped_column(Float)  # meters
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    user = relationship("User", back_populates="geofences")
    subscriptions = relationship("GeofenceSubscription", back_populates="geofence", cascade="all, delete-orphan")


class GeofenceSubscription(Base):
    __tablename__ = "geofence_subscriptions"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    fence_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("geofences.id"))
    chat_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("chats.id"))
    event_type: Mapped[str] = mapped_column(String(50))  # 'enter', 'exit', 'dwell'
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)

    geofence = relationship("Geofence", back_populates="subscriptions")
    chat = relationship("Chat")


class LocationTracking(Base):
    __tablename__ = "location_tracking"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id"))
    latitude: Mapped[float] = mapped_column(Float)
    longitude: Mapped[float] = mapped_column(Float)
    accuracy: Mapped[float | None] = mapped_column(Float, nullable=True)  # meters
    altitude: Mapped[float | None] = mapped_column(Float, nullable=True)  # meters
    speed: Mapped[float | None] = mapped_column(Float, nullable=True)  # m/s
    heading: Mapped[float | None] = mapped_column(Float, nullable=True)  # degrees
    timestamp: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow, index=True)

    user = relationship("User", back_populates="location_tracks")
