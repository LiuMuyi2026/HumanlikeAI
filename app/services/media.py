"""Media file storage helper for chat messages."""

import os
import uuid

from fastapi import UploadFile


MEDIA_BASE_DIR = "storage/media"


async def save_upload(
    file: UploadFile,
    category: str,
    character_id: str,
) -> str:
    """Save an uploaded file and return its path.

    Args:
        file: The uploaded file.
        category: 'images' or 'voices'.
        character_id: Character ID for directory organization.

    Returns:
        The saved file path.
    """
    ext = _get_extension(file.filename, file.content_type)
    filename = f"{uuid.uuid4().hex}{ext}"
    directory = os.path.join(MEDIA_BASE_DIR, category, character_id)
    os.makedirs(directory, exist_ok=True)

    file_path = os.path.join(directory, filename)
    content = await file.read()
    with open(file_path, "wb") as f:
        f.write(content)

    return file_path


def _get_extension(filename: str | None, content_type: str | None) -> str:
    """Determine file extension from filename or content type."""
    if filename and "." in filename:
        return os.path.splitext(filename)[1]

    mime_to_ext = {
        "image/jpeg": ".jpg",
        "image/png": ".png",
        "image/gif": ".gif",
        "image/webp": ".webp",
        "audio/webm": ".webm",
        "audio/ogg": ".ogg",
        "audio/mpeg": ".mp3",
        "audio/wav": ".wav",
        "audio/mp4": ".m4a",
    }
    return mime_to_ext.get(content_type or "", ".bin")
