"""News cache model for storing fetched news articles."""

import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, DateTime, String, Text
from sqlalchemy.dialects.postgresql import JSONB

from app.models.base import Base


class NewsCache(Base):
    """Cached news articles for conversation topics."""

    __tablename__ = "news_cache"

    id = Column(String, primary_key=True, default=lambda: str(uuid.uuid4()))
    title = Column(String(500), nullable=False)
    summary = Column(Text, nullable=True)
    source = Column(String(200), nullable=True)
    url = Column(String(1000), nullable=True)
    location = Column(String(200), nullable=True)
    location_type = Column(String(50), nullable=True)  # 'user' or 'ai'
    extra_data = Column(JSONB, default=dict)
    fetched_at = Column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        nullable=False,
    )
    expires_at = Column(DateTime(timezone=True), nullable=True)

    def __repr__(self):
        return f"<NewsCache {self.title[:50]}...>"
