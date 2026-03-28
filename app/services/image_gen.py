import asyncio
import logging
import os
import uuid

from google import genai
from google.genai import types

from app.config import get_settings

logger = logging.getLogger(__name__)


def _build_avatar_prompt(character_config: dict) -> str:
    """Build an image generation prompt from character settings."""
    parts = ["Portrait photo of a person"]

    if character_config.get("gender"):
        parts.append(f"who is {character_config['gender']}")

    if character_config.get("region"):
        parts.append(f"from {character_config['region']}")

    if character_config.get("occupation"):
        parts.append(f"working as {character_config['occupation']}")

    if character_config.get("personality_traits"):
        traits = character_config["personality_traits"]
        if isinstance(traits, list) and traits:
            parts.append(f"with a {', '.join(traits[:3])} personality")

    if character_config.get("mbti"):
        parts.append(f"({character_config['mbti']} personality type)")

    age_hint = ""
    familiarity = character_config.get("familiarity_level", 5)
    if familiarity >= 7:
        age_hint = "warm and approachable expression"
    elif familiarity >= 4:
        age_hint = "friendly expression"
    else:
        age_hint = "polite and composed expression"

    parts.append(f"with a {age_hint}")
    parts.append("high quality, realistic, natural lighting, soft background")

    return ", ".join(parts)


async def generate_image(
    character_id: str,
    prompt: str | None = None,
    character_config: dict | None = None,
    reference_image_path: str | None = None,
) -> tuple[str, str]:
    """
    Generate an image using Gemini's image generation model.

    Args:
        character_id: Character ID for organizing storage.
        prompt: Custom prompt. If None, auto-builds from character_config.
        character_config: Character settings dict for auto-prompt building.
        reference_image_path: Optional path to a reference image (e.g. avatar)
            to use as basis for generation.

    Returns:
        Tuple of (file_path, prompt_used).
    """
    settings = get_settings()

    if prompt is None and character_config:
        prompt = _build_avatar_prompt(character_config)
    elif prompt is None:
        prompt = "Portrait photo of a friendly person, high quality, realistic"

    # Ensure storage directory exists
    storage_dir = os.path.join(settings.image_storage_dir, character_id)
    os.makedirs(storage_dir, exist_ok=True)

    client = genai.Client(api_key=settings.gemini_api_key)

    # Build contents: reference image + prompt, or just prompt
    if reference_image_path and os.path.exists(reference_image_path):
        ref_data = await asyncio.to_thread(_read_file, reference_image_path)
        # Detect mime type from extension
        ext = reference_image_path.rsplit(".", 1)[-1].lower()
        mime_map = {"jpg": "image/jpeg", "jpeg": "image/jpeg", "png": "image/png", "webp": "image/webp"}
        mime_type = mime_map.get(ext, "image/png")
        contents = [
            types.Part(inline_data=types.Blob(mime_type=mime_type, data=ref_data)),
            prompt,
        ]
        logger.info("Generating image with reference from: %s", reference_image_path)
    else:
        contents = prompt

    response = await asyncio.to_thread(
        client.models.generate_content,
        model=settings.gemini_image_model,
        contents=contents,
        config=types.GenerateContentConfig(
            response_modalities=["IMAGE"],
        ),
    )

    # Extract image data from response
    image_data = None
    for part in response.candidates[0].content.parts:
        if getattr(part, "inline_data", None) and part.inline_data.mime_type.startswith("image/"):
            image_data = part.inline_data
            break

    if image_data is None:
        raise ValueError("No image data returned from Gemini")

    # Determine file extension from mime type
    ext = "png"
    if "jpeg" in image_data.mime_type or "jpg" in image_data.mime_type:
        ext = "jpg"
    elif "webp" in image_data.mime_type:
        ext = "webp"

    filename = f"{uuid.uuid4().hex}.{ext}"
    file_path = os.path.join(storage_dir, filename)

    await asyncio.to_thread(_write_file, file_path, image_data.data)

    logger.info(
        "Generated image for character=%s, size=%d bytes, path=%s",
        character_id,
        len(image_data.data),
        file_path,
    )

    return file_path, prompt


def _write_file(path: str, data: bytes) -> None:
    with open(path, "wb") as f:
        f.write(data)


def _read_file(path: str) -> bytes:
    with open(path, "rb") as f:
        return f.read()
