from datetime import datetime

from pydantic import BaseModel, Field


class SendMessageRequest(BaseModel):
    content: str = Field(..., min_length=1, max_length=5000)


class MessageResponse(BaseModel):
    id: str
    character_id: str
    user_id: str
    role: str
    content_type: str
    content: str | None
    media_url: str | None
    emotion: str | None
    valence: float | None
    arousal: float | None
    intensity: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class MessageListResponse(BaseModel):
    messages: list[MessageResponse]
    has_more: bool
