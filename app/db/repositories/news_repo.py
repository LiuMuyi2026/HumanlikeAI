"""Repository for news cache operations."""

from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.news import NewsCache


class NewsRepository:
    def __init__(self, session: AsyncSession):
        self._session = session

    async def store_news(self, news_items: list[dict]) -> list[NewsCache]:
        """Store news items in the cache."""
        cached = []
        for item in news_items:
            news = NewsCache(
                title=item.get("title", "")[:500],
                summary=item.get("summary"),
                source=item.get("source"),
                url=item.get("url"),
                location=item.get("location"),
                location_type=item.get("location_type"),
                extra_data={
                    "date": item.get("date"),
                    "fetched_at": item.get("fetched_at"),
                },
                expires_at=datetime.now(timezone.utc) + timedelta(hours=6),
            )
            self._session.add(news)
            cached.append(news)

        await self._session.commit()
        return cached

    async def get_recent_news(
        self,
        location_type: str | None = None,
        limit: int = 10,
    ) -> list[NewsCache]:
        """Get recent non-expired news, optionally filtered by location type."""
        now = datetime.now(timezone.utc)
        query = select(NewsCache).where(
            (NewsCache.expires_at > now) | (NewsCache.expires_at.is_(None))
        )

        if location_type:
            query = query.where(NewsCache.location_type == location_type)

        query = query.order_by(NewsCache.fetched_at.desc()).limit(limit)
        result = await self._session.execute(query)
        return list(result.scalars().all())

    async def get_news_for_topics(self, limit: int = 5) -> list[dict]:
        """Get news formatted for conversation topics."""
        news = await self.get_recent_news(limit=limit)
        return [
            {
                "title": n.title,
                "summary": n.summary,
                "location": n.location,
                "location_type": n.location_type,
            }
            for n in news
        ]

    async def cleanup_expired(self) -> int:
        """Delete expired news items."""
        now = datetime.now(timezone.utc)
        result = await self._session.execute(
            delete(NewsCache).where(NewsCache.expires_at < now)
        )
        await self._session.commit()
        return result.rowcount
