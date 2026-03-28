from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.character import AICharacter, CharacterEmotionImage, CharacterImage


class CharacterRepository:
    def __init__(self, session: AsyncSession):
        self._session = session

    async def create(self, user_id: str, **kwargs) -> AICharacter:
        character = AICharacter(user_id=user_id, **kwargs)
        self._session.add(character)
        await self._session.commit()
        await self._session.refresh(character)
        return character

    async def get_by_id(self, character_id: str) -> AICharacter | None:
        result = await self._session.execute(
            select(AICharacter).where(AICharacter.id == character_id)
        )
        return result.scalar_one_or_none()

    async def get_by_id_and_user(
        self, character_id: str, user_id: str
    ) -> AICharacter | None:
        result = await self._session.execute(
            select(AICharacter).where(
                AICharacter.id == character_id,
                AICharacter.user_id == user_id,
            )
        )
        return result.scalar_one_or_none()

    async def list_by_user(self, user_id: str) -> list[AICharacter]:
        result = await self._session.execute(
            select(AICharacter)
            .where(AICharacter.user_id == user_id)
            .order_by(AICharacter.updated_at.desc())
        )
        return list(result.scalars().all())

    async def update(self, character_id: str, **kwargs) -> AICharacter | None:
        filtered = {k: v for k, v in kwargs.items() if v is not None}
        if not filtered:
            return await self.get_by_id(character_id)
        await self._session.execute(
            update(AICharacter)
            .where(AICharacter.id == character_id)
            .values(**filtered)
        )
        await self._session.commit()
        return await self.get_by_id(character_id)

    async def delete(self, character_id: str) -> bool:
        character = await self.get_by_id(character_id)
        if character is None:
            return False
        await self._session.delete(character)
        await self._session.commit()
        return True

    # --- Image operations ---

    async def get_image(self, image_id: str) -> CharacterImage | None:
        result = await self._session.execute(
            select(CharacterImage).where(CharacterImage.id == image_id)
        )
        return result.scalar_one_or_none()

    async def add_image(
        self,
        character_id: str,
        image_path: str,
        prompt_used: str | None = None,
        is_avatar: bool = False,
    ) -> CharacterImage:
        image = CharacterImage(
            character_id=character_id,
            image_path=image_path,
            prompt_used=prompt_used,
            is_avatar=is_avatar,
        )
        self._session.add(image)
        await self._session.commit()
        await self._session.refresh(image)
        return image

    async def list_images(self, character_id: str) -> list[CharacterImage]:
        result = await self._session.execute(
            select(CharacterImage)
            .where(CharacterImage.character_id == character_id)
            .order_by(CharacterImage.created_at.desc())
        )
        return list(result.scalars().all())

    async def set_avatar(self, character_id: str, image_id: str) -> bool:
        """Set an image as the avatar, unsetting any previous avatar."""
        # Unset all current avatars for this character
        await self._session.execute(
            update(CharacterImage)
            .where(
                CharacterImage.character_id == character_id,
                CharacterImage.is_avatar == True,
            )
            .values(is_avatar=False)
        )
        # Set the new avatar
        result = await self._session.execute(
            update(CharacterImage)
            .where(
                CharacterImage.id == image_id,
                CharacterImage.character_id == character_id,
            )
            .values(is_avatar=True)
        )
        if result.rowcount == 0:
            return False
        # Also update the character's avatar_path
        img = await self._session.execute(
            select(CharacterImage).where(CharacterImage.id == image_id)
        )
        image = img.scalar_one_or_none()
        if image:
            await self._session.execute(
                update(AICharacter)
                .where(AICharacter.id == character_id)
                .values(avatar_path=image.image_path)
            )
        await self._session.commit()
        return True

    async def delete_image(self, image_id: str) -> bool:
        result = await self._session.execute(
            select(CharacterImage).where(CharacterImage.id == image_id)
        )
        image = result.scalar_one_or_none()
        if image is None:
            return False
        await self._session.delete(image)
        await self._session.commit()
        return True

    # --- Emotion image operations ---

    async def add_emotion_image(
        self,
        character_id: str,
        emotion_key: str,
        image_path: str,
        prompt_used: str | None = None,
    ) -> CharacterEmotionImage:
        image = CharacterEmotionImage(
            character_id=character_id,
            emotion_key=emotion_key,
            image_path=image_path,
            prompt_used=prompt_used,
        )
        self._session.add(image)
        await self._session.commit()
        await self._session.refresh(image)
        return image

    async def get_emotion_image(
        self, character_id: str, emotion_key: str
    ) -> CharacterEmotionImage | None:
        result = await self._session.execute(
            select(CharacterEmotionImage).where(
                CharacterEmotionImage.character_id == character_id,
                CharacterEmotionImage.emotion_key == emotion_key,
            )
        )
        return result.scalar_one_or_none()

    async def list_emotion_images(
        self, character_id: str
    ) -> list[CharacterEmotionImage]:
        result = await self._session.execute(
            select(CharacterEmotionImage)
            .where(CharacterEmotionImage.character_id == character_id)
            .order_by(CharacterEmotionImage.emotion_key)
        )
        return list(result.scalars().all())

    async def delete_emotion_images(self, character_id: str) -> int:
        """Delete all emotion images for a character. Returns count deleted."""
        result = await self._session.execute(
            select(CharacterEmotionImage).where(
                CharacterEmotionImage.character_id == character_id
            )
        )
        images = list(result.scalars().all())
        for img in images:
            await self._session.delete(img)
        await self._session.commit()
        return len(images)
