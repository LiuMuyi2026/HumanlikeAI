from datetime import datetime
from typing import Literal

from pydantic import BaseModel


# --- Client -> Server ---

class AuthPayload(BaseModel):
    device_id: str
    display_name: str | None = None


class AudioPayload(BaseModel):
    data: str  # base64-encoded PCM
    mime_type: str = "audio/pcm;rate=16000"


class TextPayload(BaseModel):
    text: str


class ControlPayload(BaseModel):
    action: Literal["end_session"]


class ClientMessage(BaseModel):
    type: Literal["auth", "audio", "text", "control"]
    payload: dict
    timestamp: datetime | None = None


# --- Server -> Client ---

class ServerAudioPayload(BaseModel):
    data: str  # base64-encoded PCM
    mime_type: str = "audio/pcm;rate=24000"
    emotion: str = "neutral"
    valence: float = 0.0
    arousal: float = 0.2
    intensity: str = "low"


class ServerTextPayload(BaseModel):
    text: str
    emotion: str = "neutral"
    valence: float = 0.0
    arousal: float = 0.2
    intensity: str = "low"


def server_message(
    msg_type: str, payload: dict | None = None
) -> dict:
    """Build a server -> client message dict."""
    return {
        "type": msg_type,
        "payload": payload or {},
    }
