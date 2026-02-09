import asyncio
import os

from fastapi import APIRouter, HTTPException, Query
from fastapi.responses import FileResponse

from app.db.repositories.character_repo import CharacterRepository
from app.db.session import async_session_factory
from app.schemas.character import (
    CharacterEmotionImageResponse,
    CharacterImageResponse,
    CharacterListResponse,
    CharacterResponse,
    CreateCharacterRequest,
    EmotionPackStatusResponse,
    GenerateImageRequest,
    UpdateCharacterRequest,
)
from app.services.emotion_model import ALL_IMAGE_KEYS
from app.services.image_gen import generate_image

router = APIRouter(tags=["characters"])


@router.post("", response_model=CharacterResponse)
async def create_character(body: CreateCharacterRequest, user_id: str = Query(...)):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        data = body.model_dump()
        # Convert MBTI enum to string for storage
        if data.get("mbti"):
            data["mbti"] = data["mbti"].value
        character = await repo.create(user_id=user_id, **data)
        return character


@router.get("", response_model=CharacterListResponse)
async def list_characters(user_id: str = Query(...)):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        characters = await repo.list_by_user(user_id)
        return CharacterListResponse(characters=characters)


@router.get("/{character_id}", response_model=CharacterResponse)
async def get_character(character_id: str, user_id: str = Query(...)):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")
        return character


@router.put("/{character_id}", response_model=CharacterResponse)
async def update_character(
    character_id: str, body: UpdateCharacterRequest, user_id: str = Query(...)
):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")
        data = body.model_dump(exclude_none=True)
        if data.get("mbti"):
            data["mbti"] = data["mbti"].value
        updated = await repo.update(character_id, **data)
        return updated


@router.delete("/{character_id}")
async def delete_character(character_id: str, user_id: str = Query(...)):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")
        await repo.delete(character_id)
        return {"status": "deleted"}


@router.post("/{character_id}/generate-avatar", response_model=CharacterImageResponse)
async def generate_avatar(
    character_id: str,
    body: GenerateImageRequest | None = None,
    user_id: str = Query(...),
):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

        character_config = {
            "name": character.name,
            "gender": character.gender,
            "region": character.region,
            "occupation": character.occupation,
            "personality_traits": character.personality_traits,
            "mbti": character.mbti,
            "familiarity_level": character.familiarity_level,
        }

        custom_prompt = body.prompt if body else None
        file_path, prompt_used = await generate_image(
            character_id=character_id,
            prompt=custom_prompt,
            character_config=character_config,
        )

        # Unset previous avatars and save new one
        image = await repo.add_image(
            character_id=character_id,
            image_path=file_path,
            prompt_used=prompt_used,
            is_avatar=True,
        )
        await repo.set_avatar(character_id, image.id)
        # Refresh to get updated is_avatar
        await session.refresh(image)
        return image


@router.post("/{character_id}/generate-image", response_model=CharacterImageResponse)
async def generate_gallery_image(
    character_id: str,
    body: GenerateImageRequest | None = None,
    user_id: str = Query(...),
    use_avatar: bool = Query(False),
):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

        character_config = {
            "name": character.name,
            "gender": character.gender,
            "region": character.region,
            "occupation": character.occupation,
            "personality_traits": character.personality_traits,
            "mbti": character.mbti,
            "familiarity_level": character.familiarity_level,
        }

        custom_prompt = body.prompt if body else None
        # Use avatar as reference image if requested
        reference_path = None
        if use_avatar and character.avatar_path and os.path.exists(character.avatar_path):
            reference_path = character.avatar_path
            # Add context to prompt when using avatar as reference
            if custom_prompt:
                custom_prompt = f"Using this person as reference, generate: {custom_prompt}"
            else:
                custom_prompt = (
                    "Generate a new image of this same person in a different pose, "
                    "scene, or outfit. Keep the same face and appearance. "
                    "High quality, realistic, natural lighting."
                )

        file_path, prompt_used = await generate_image(
            character_id=character_id,
            prompt=custom_prompt,
            character_config=character_config,
            reference_image_path=reference_path,
        )

        image = await repo.add_image(
            character_id=character_id,
            image_path=file_path,
            prompt_used=prompt_used,
            is_avatar=False,
        )
        return image


@router.get("/{character_id}/images", response_model=list[CharacterImageResponse])
async def list_images(character_id: str, user_id: str = Query(...)):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")
        images = await repo.list_images(character_id)
        return images


@router.put("/{character_id}/images/{image_id}/set-avatar")
async def set_avatar(character_id: str, image_id: str, user_id: str = Query(...)):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")
        success = await repo.set_avatar(character_id, image_id)
        if not success:
            raise HTTPException(status_code=404, detail="Image not found")
        return {"status": "avatar_set"}


@router.delete("/{character_id}/images/{image_id}")
async def delete_image(character_id: str, image_id: str, user_id: str = Query(...)):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

        # Check if we're deleting the current avatar
        image = await repo.get_image(image_id)
        is_current_avatar = (
            image
            and image.is_avatar
            and character.avatar_path == image.image_path
        )

        success = await repo.delete_image(image_id)
        if not success:
            raise HTTPException(status_code=404, detail="Image not found")

        # Clear avatar_path if we deleted the avatar
        if is_current_avatar:
            from sqlalchemy import update
            from app.models.character import AICharacter
            await session.execute(
                update(AICharacter)
                .where(AICharacter.id == character_id)
                .values(avatar_path=None)
            )
            await session.commit()

        return {"status": "deleted"}


@router.get("/{character_id}/images/{image_id}/file")
async def get_image_file(character_id: str, image_id: str):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        image = await repo.get_image(image_id)
        if image is None or image.character_id != character_id:
            raise HTTPException(status_code=404, detail="Image not found")
        if not os.path.exists(image.image_path):
            raise HTTPException(status_code=404, detail="Image file not found")
        return FileResponse(image.image_path)


@router.get("/{character_id}/avatar")
async def get_avatar(character_id: str):
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id(character_id)
        if character is None or not character.avatar_path:
            raise HTTPException(status_code=404, detail="Avatar not found")
        if not os.path.exists(character.avatar_path):
            raise HTTPException(status_code=404, detail="Avatar file not found")
        return FileResponse(character.avatar_path)


# --- Emotion Pack endpoints ---


@router.post("/{character_id}/emotion-pack", response_model=EmotionPackStatusResponse)
async def generate_emotion_pack_endpoint(
    character_id: str,
    user_id: str = Query(...),
):
    """Kick off emotion pack generation in the background.

    Returns immediately with the current status. The client should poll
    GET /emotion-pack to track progress.
    """
    from app.services.emotion_image_gen import generate_emotion_pack

    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

    # Fire-and-forget — generation runs in background
    asyncio.create_task(generate_emotion_pack(character_id, user_id))

    # Return current status immediately
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        images = await repo.list_emotion_images(character_id)
        return EmotionPackStatusResponse(
            character_id=character_id,
            total_expected=len(ALL_IMAGE_KEYS),
            generated=len(images),
            emotion_keys=[img.emotion_key for img in images],
            images=images,
        )


@router.get("/{character_id}/emotion-pack", response_model=EmotionPackStatusResponse)
async def get_emotion_pack_status(
    character_id: str,
    user_id: str = Query(...),
):
    """List status of emotion images for a character."""
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")
        images = await repo.list_emotion_images(character_id)
        return EmotionPackStatusResponse(
            character_id=character_id,
            total_expected=len(ALL_IMAGE_KEYS),
            generated=len(images),
            emotion_keys=[img.emotion_key for img in images],
            images=images,
        )


@router.get("/{character_id}/emotion-pack/{emotion_key}/file")
async def get_emotion_image_file(character_id: str, emotion_key: str):
    """Serve an individual emotion image file."""
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        image = await repo.get_emotion_image(character_id, emotion_key)
        if image is None:
            raise HTTPException(status_code=404, detail="Emotion image not found")
        if not os.path.exists(image.image_path):
            raise HTTPException(status_code=404, detail="Image file not found")
        return FileResponse(image.image_path)


@router.delete("/{character_id}/emotion-pack")
async def delete_emotion_pack(
    character_id: str,
    user_id: str = Query(...),
):
    """Delete all emotion images for a character."""
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")
        count = await repo.delete_emotion_images(character_id)
        return {"status": "deleted", "count": count}
