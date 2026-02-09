import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    device_id: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    display_name: Mapped[str | None] = mapped_column(String(100))
    preferences: Mapped[dict | None] = mapped_column(JSONB, default=dict)
    relationship_status: Mapped[str | None] = mapped_column(String(50))
    personality_notes: Mapped[str | None] = mapped_column(Text)
    extracted_facts: Mapped[dict | None] = mapped_column(JSONB, default=dict)
    location: Mapped[str | None] = mapped_column(String(200))  # User's location
    timezone: Mapped[str | None] = mapped_column(String(50))  # User's timezone
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
