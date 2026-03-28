from datetime import datetime

from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.message import ChatMessage


class MessageRepository:
    def __init__(self, session: AsyncSession):
        self._session = session

    async def create(
        self,
        character_id: str,
        user_id: str,
        role: str,
        content_type: str,
        content: str | None = None,
        media_url: str | None = None,
        emotion: str | None = None,
        valence: float | None = None,
        arousal: float | None = None,
        intensity: str | None = None,
    ) -> ChatMessage:
        msg = ChatMessage(
            character_id=character_id,
            user_id=user_id,
            role=role,
            content_type=content_type,
            content=content,
            media_url=media_url,
            emotion=emotion,
            valence=valence,
            arousal=arousal,
            intensity=intensity,
        )
        self._session.add(msg)
        await self._session.commit()
        await self._session.refresh(msg)
        return msg

    async def list_messages(
        self,
        character_id: str,
        user_id: str,
        limit: int = 50,
        before: datetime | None = None,
    ) -> list[ChatMessage]:
        stmt = (
            select(ChatMessage)
            .where(
                ChatMessage.character_id == character_id,
                ChatMessage.user_id == user_id,
            )
            .order_by(ChatMessage.created_at.desc())
            .limit(limit)
        )
        if before:
            stmt = stmt.where(ChatMessage.created_at < before)
        result = await self._session.execute(stmt)
        messages = list(result.scalars().all())
        messages.reverse()  # return in chronological order
        return messages

    async def get_recent_context(
        self,
        character_id: str,
        user_id: str,
        limit: int = 20,
    ) -> list[ChatMessage]:
        """Get recent messages for building Gemini conversation context."""
        return await self.list_messages(character_id, user_id, limit=limit)

    async def count_messages(
        self,
        character_id: str,
        user_id: str,
    ) -> int:
        result = await self._session.execute(
            select(func.count(ChatMessage.id)).where(
                ChatMessage.character_id == character_id,
                ChatMessage.user_id == user_id,
            )
        )
        return result.scalar_one()

    async def get_last_ai_emotion(
        self,
        character_id: str,
        user_id: str,
    ) -> ChatMessage | None:
        """Get the most recent AI message that has emotion data."""
        result = await self._session.execute(
            select(ChatMessage)
            .where(
                ChatMessage.character_id == character_id,
                ChatMessage.user_id == user_id,
                ChatMessage.role == "ai",
                ChatMessage.emotion.is_not(None),
            )
            .order_by(ChatMessage.created_at.desc())
            .limit(1)
        )
        return result.scalar_one_or_none()

    async def list_messages_after(
        self,
        character_id: str,
        user_id: str,
        after: datetime,
    ) -> list[ChatMessage]:
        """Get messages created after a given timestamp (chronological order)."""
        result = await self._session.execute(
            select(ChatMessage)
            .where(
                ChatMessage.character_id == character_id,
                ChatMessage.user_id == user_id,
                ChatMessage.created_at > after,
            )
            .order_by(ChatMessage.created_at.asc())
        )
        return list(result.scalars().all())

    async def get_message(self, message_id: str) -> ChatMessage | None:
        result = await self._session.execute(
            select(ChatMessage).where(ChatMessage.id == message_id)
        )
        return result.scalar_one_or_none()
