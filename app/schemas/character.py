from datetime import datetime
from enum import Enum

from pydantic import BaseModel, Field


class MBTIType(str, Enum):
    INTJ = "INTJ"
    INTP = "INTP"
    ENTJ = "ENTJ"
    ENTP = "ENTP"
    INFJ = "INFJ"
    INFP = "INFP"
    ENFJ = "ENFJ"
    ENFP = "ENFP"
    ISTJ = "ISTJ"
    ISFJ = "ISFJ"
    ESTJ = "ESTJ"
    ESFJ = "ESFJ"
    ISTP = "ISTP"
    ISFP = "ISFP"
    ESTP = "ESTP"
    ESFP = "ESFP"


class CreateCharacterRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=100)
    gender: str | None = Field(None, max_length=20)
    region: str | None = Field(None, max_length=200)
    occupation: str | None = Field(None, max_length=100)
    personality_traits: list[str] | None = None
    mbti: MBTIType | None = None
    political_leaning: str | None = Field(None, max_length=50)
    relationship_type: str | None = Field(None, max_length=50)
    familiarity_level: int = Field(5, ge=1, le=10)
    skills: list[str] | None = None


class UpdateCharacterRequest(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=100)
    gender: str | None = Field(None, max_length=20)
    region: str | None = Field(None, max_length=200)
    occupation: str | None = Field(None, max_length=100)
    personality_traits: list[str] | None = None
    mbti: MBTIType | None = None
    political_leaning: str | None = Field(None, max_length=50)
    relationship_type: str | None = Field(None, max_length=50)
    familiarity_level: int | None = Field(None, ge=1, le=10)
    skills: list[str] | None = None


class GenerateImageRequest(BaseModel):
    prompt: str | None = Field(None, max_length=1000)


class CharacterImageResponse(BaseModel):
    id: str
    character_id: str
    image_path: str
    prompt_used: str | None
    is_avatar: bool
    created_at: datetime

    model_config = {"from_attributes": True}


class CharacterResponse(BaseModel):
    id: str
    user_id: str
    name: str
    gender: str | None
    region: str | None
    occupation: str | None
    personality_traits: list[str] | None
    mbti: str | None
    political_leaning: str | None
    relationship_type: str | None
    familiarity_level: int
    skills: list[str] | None
    avatar_prompt: str | None
    avatar_path: str | None
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


class CharacterListResponse(BaseModel):
    characters: list[CharacterResponse]


class CharacterEmotionImageResponse(BaseModel):
    id: str
    character_id: str
    emotion_key: str
    image_path: str
    prompt_used: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


class EmotionPackStatusResponse(BaseModel):
    character_id: str
    total_expected: int
    generated: int
    emotion_keys: list[str]
    images: list[CharacterEmotionImageResponse]
