import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class AICharacter(Base):
    __tablename__ = "ai_characters"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    user_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    name: Mapped[str] = mapped_column(String(100))
    gender: Mapped[str | None] = mapped_column(String(20))
    region: Mapped[str | None] = mapped_column(String(200))
    occupation: Mapped[str | None] = mapped_column(String(100))
    personality_traits: Mapped[list | None] = mapped_column(JSONB, default=list)
    mbti: Mapped[str | None] = mapped_column(String(4))
    political_leaning: Mapped[str | None] = mapped_column(String(50))
    relationship_type: Mapped[str | None] = mapped_column(String(50))
    familiarity_level: Mapped[int] = mapped_column(Integer, default=5)
    skills: Mapped[list | None] = mapped_column(JSONB, default=list)
    avatar_prompt: Mapped[str | None] = mapped_column(Text)
    avatar_path: Mapped[str | None] = mapped_column(String(500))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )

    images: Mapped[list["CharacterImage"]] = relationship(
        back_populates="character", cascade="all, delete-orphan"
    )
    emotion_images: Mapped[list["CharacterEmotionImage"]] = relationship(
        back_populates="character", cascade="all, delete-orphan"
    )


class CharacterImage(Base):
    __tablename__ = "character_images"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    character_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ai_characters.id", ondelete="CASCADE"), index=True
    )
    image_path: Mapped[str] = mapped_column(String(500))
    prompt_used: Mapped[str | None] = mapped_column(Text)
    is_avatar: Mapped[bool] = mapped_column(default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    character: Mapped["AICharacter"] = relationship(back_populates="images")


class CharacterEmotionImage(Base):
    __tablename__ = "character_emotion_images"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    character_id: Mapped[str] = mapped_column(
        String(36), ForeignKey("ai_characters.id", ondelete="CASCADE"), index=True
    )
    emotion_key: Mapped[str] = mapped_column(String(30))
    image_path: Mapped[str] = mapped_column(String(500))
    prompt_used: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    character: Mapped["AICharacter"] = relationship(back_populates="emotion_images")
