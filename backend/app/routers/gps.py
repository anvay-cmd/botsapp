from datetime import datetime, date, timedelta
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import select, and_, desc
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models.user import User
from app.models.geofence import Geofence, LocationTracking, GeofenceSubscription
from app.models.integration import Integration
from app.utils.deps import get_current_user
import math

router = APIRouter(prefix="/gps", tags=["gps"])


# ========== Request/Response Schemas ==========

class LocationUpdateRequest(BaseModel):
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    accuracy: float | None = None
    altitude: float | None = None
    speed: float | None = None
    heading: float | None = None
    timestamp: datetime | None = None


class GeofenceCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    radius: float = Field(..., ge=10, le=10000)


class GeofenceResponse(BaseModel):
    id: str
    name: str
    latitude: float
    longitude: float
    radius: float
    is_active: bool
    created_at: datetime


# ========== Helper Functions ==========

def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate distance between two GPS coordinates in meters"""
    R = 6371000  # Earth radius in meters

    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    delta_phi = math.radians(lat2 - lat1)
    delta_lambda = math.radians(lon2 - lon1)

    a = (math.sin(delta_phi / 2) ** 2 +
         math.cos(phi1) * math.cos(phi2) * math.sin(delta_lambda / 2) ** 2)
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

    return R * c


async def check_geofence_events(
    db: AsyncSession,
    user_id: UUID,
    latitude: float,
    longitude: float
):
    """
    Check if location triggers any geofence events
    Returns list of triggered events: [(fence_name, event_type, chat_id), ...]
    """
    # Get all active geofences for user
    result = await db.execute(
        select(Geofence).where(
            and_(
                Geofence.user_id == user_id,
                Geofence.is_active == True
            )
        )
    )
    geofences = result.scalars().all()

    triggered_events = []

    for fence in geofences:
        # Calculate distance from fence center
        distance = haversine_distance(
            latitude, longitude,
            fence.latitude, fence.longitude
        )

        # Check if inside fence
        is_inside = distance <= fence.radius

        # Get subscriptions for this fence
        result = await db.execute(
            select(GeofenceSubscription).where(
                GeofenceSubscription.fence_id == fence.id
            )
        )
        subscriptions = result.scalars().all()

        for sub in subscriptions:
            if is_inside and sub.event_type in ("enter", "dwell"):
                triggered_events.append({
                    "fence_id": str(fence.id),
                    "fence_name": fence.name,
                    "event_type": sub.event_type,
                    "chat_id": str(sub.chat_id),
                    "distance": distance,
                })
            elif not is_inside and sub.event_type == "exit":
                triggered_events.append({
                    "fence_id": str(fence.id),
                    "fence_name": fence.name,
                    "event_type": sub.event_type,
                    "chat_id": str(sub.chat_id),
                    "distance": distance,
                })

    return triggered_events


# ========== Endpoints ==========

@router.post("/location")
async def update_location(
    location: LocationUpdateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Update user's current location. Called by the mobile app.
    Only saves location if GPS integration is enabled.
    Also checks for geofence events.
    """
    # Check if GPS integration is enabled
    result = await db.execute(
        select(Integration).where(
            and_(
                Integration.user_id == user.id,
                Integration.provider == "gps",
                Integration.is_active == True
            )
        )
    )
    integration = result.scalar_one_or_none()

    if not integration:
        raise HTTPException(
            status_code=403,
            detail="GPS integration is not enabled. Enable it in settings first."
        )

    # Save location to database
    # Remove timezone info from timestamp if present (database uses timezone-naive)
    timestamp = location.timestamp or datetime.utcnow()
    if timestamp.tzinfo is not None:
        timestamp = timestamp.replace(tzinfo=None)

    location_record = LocationTracking(
        user_id=user.id,
        latitude=location.latitude,
        longitude=location.longitude,
        accuracy=location.accuracy,
        altitude=location.altitude,
        speed=location.speed,
        heading=location.heading,
        timestamp=timestamp
    )
    db.add(location_record)
    await db.commit()

    # Check for geofence events
    events = await check_geofence_events(
        db, user.id, location.latitude, location.longitude
    )

    # TODO: Send websocket notifications for triggered events
    # For now, just return the events
    return {
        "status": "success",
        "location_saved": True,
        "triggered_events": events
    }


@router.get("/location")
async def get_current_location(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get user's most recent location"""
    result = await db.execute(
        select(LocationTracking)
        .where(LocationTracking.user_id == user.id)
        .order_by(desc(LocationTracking.timestamp))
        .limit(1)
    )
    location = result.scalar_one_or_none()

    if not location:
        raise HTTPException(status_code=404, detail="No location data available")

    return {
        "latitude": location.latitude,
        "longitude": location.longitude,
        "accuracy": location.accuracy,
        "altitude": location.altitude,
        "speed": location.speed,
        "heading": location.heading,
        "timestamp": location.timestamp,
    }


@router.get("/location/history")
async def get_location_history(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
    start_date: date | None = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: date | None = Query(None, description="End date (YYYY-MM-DD)"),
    limit: int = Query(1000, ge=1, le=5000, description="Maximum number of records"),
):
    """
    Get user's location history.
    If no dates provided, returns last 7 days.
    """
    # Default to last 7 days if no dates provided
    if not start_date and not end_date:
        end_date = date.today()
        start_date = end_date - timedelta(days=7)
    elif not start_date:
        start_date = end_date - timedelta(days=7)
    elif not end_date:
        end_date = date.today()

    # Convert dates to datetime for comparison
    start_datetime = datetime.combine(start_date, datetime.min.time())
    end_datetime = datetime.combine(end_date, datetime.max.time())

    # Query location history
    result = await db.execute(
        select(LocationTracking)
        .where(
            and_(
                LocationTracking.user_id == user.id,
                LocationTracking.timestamp >= start_datetime,
                LocationTracking.timestamp <= end_datetime
            )
        )
        .order_by(LocationTracking.timestamp)
        .limit(limit)
    )
    locations = result.scalars().all()

    return {
        "start_date": start_date.isoformat(),
        "end_date": end_date.isoformat(),
        "count": len(locations),
        "locations": [
            {
                "latitude": loc.latitude,
                "longitude": loc.longitude,
                "accuracy": loc.accuracy,
                "altitude": loc.altitude,
                "speed": loc.speed,
                "heading": loc.heading,
                "timestamp": loc.timestamp.isoformat(),
            }
            for loc in locations
        ]
    }


@router.post("/fences")
async def create_geofence(
    fence: GeofenceCreateRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new geofence"""
    # Check if fence with same name exists
    result = await db.execute(
        select(Geofence).where(
            and_(
                Geofence.user_id == user.id,
                Geofence.name == fence.name,
                Geofence.is_active == True
            )
        )
    )
    existing = result.scalar_one_or_none()

    if existing:
        raise HTTPException(
            status_code=400,
            detail=f"A geofence named '{fence.name}' already exists"
        )

    # Create geofence
    new_fence = Geofence(
        user_id=user.id,
        name=fence.name,
        latitude=fence.latitude,
        longitude=fence.longitude,
        radius=fence.radius
    )
    db.add(new_fence)
    await db.commit()
    await db.refresh(new_fence)

    return GeofenceResponse(
        id=str(new_fence.id),
        name=new_fence.name,
        latitude=new_fence.latitude,
        longitude=new_fence.longitude,
        radius=new_fence.radius,
        is_active=new_fence.is_active,
        created_at=new_fence.created_at
    )


@router.get("/fences")
async def list_geofences(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all user's geofences"""
    result = await db.execute(
        select(Geofence).where(
            and_(
                Geofence.user_id == user.id,
                Geofence.is_active == True
            )
        )
    )
    fences = result.scalars().all()

    return [
        GeofenceResponse(
            id=str(fence.id),
            name=fence.name,
            latitude=fence.latitude,
            longitude=fence.longitude,
            radius=fence.radius,
            is_active=fence.is_active,
            created_at=fence.created_at
        )
        for fence in fences
    ]


@router.delete("/fences/{fence_id}")
async def delete_geofence(
    fence_id: str,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Delete a geofence"""
    result = await db.execute(
        select(Geofence).where(
            and_(
                Geofence.id == UUID(fence_id),
                Geofence.user_id == user.id
            )
        )
    )
    fence = result.scalar_one_or_none()

    if not fence:
        raise HTTPException(status_code=404, detail="Geofence not found")

    fence.is_active = False
    db.add(fence)
    await db.commit()

    return {"status": "deleted"}
