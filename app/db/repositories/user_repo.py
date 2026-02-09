from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User


class UserRepository:
    def __init__(self, session: AsyncSession):
        self._session = session

    async def get_by_device_id(self, device_id: str) -> User | None:
        result = await self._session.execute(
            select(User).where(User.device_id == device_id)
        )
        return result.scalar_one_or_none()

    async def get_by_id(self, user_id: str) -> User | None:
        result = await self._session.execute(
            select(User).where(User.id == user_id)
        )
        return result.scalar_one_or_none()

    async def create(self, device_id: str, display_name: str | None = None) -> User:
        user = User(device_id=device_id, display_name=display_name)
        self._session.add(user)
        await self._session.commit()
        await self._session.refresh(user)
        return user

    async def get_or_create(
        self, device_id: str, display_name: str | None = None
    ) -> User:
        user = await self.get_by_device_id(device_id)
        if user is None:
            user = await self.create(device_id, display_name)
        elif display_name and user.display_name != display_name:
            user.display_name = display_name
            await self._session.commit()
            await self._session.refresh(user)
        return user

    async def update_profile(self, user_id: str, **kwargs) -> User | None:
        allowed = {
            "display_name",
            "preferences",
            "relationship_status",
            "personality_notes",
            "extracted_facts",
        }
        filtered = {k: v for k, v in kwargs.items() if k in allowed}
        if not filtered:
            return await self.get_by_id(user_id)

        await self._session.execute(
            update(User).where(User.id == user_id).values(**filtered)
        )
        await self._session.commit()
        return await self.get_by_id(user_id)

    async def merge_extracted_facts(
        self, user_id: str, new_facts: dict
    ) -> User | None:
        user = await self.get_by_id(user_id)
        if user is None:
            return None
        existing = user.extracted_facts or {}
        existing.update(new_facts)
        user.extracted_facts = existing
        await self._session.commit()
        await self._session.refresh(user)
        return user
