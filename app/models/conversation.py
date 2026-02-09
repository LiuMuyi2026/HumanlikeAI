import uuid
from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class ConversationLog(Base):
    __tablename__ = "conversation_logs"

    id: Mapped[str] = mapped_column(
        String(36), primary_key=True, default=lambda: str(uuid.uuid4())
    )
    user_id: Mapped[str] = mapped_column(String(36), index=True)
    transcript_text: Mapped[str] = mapped_column(Text)
    role: Mapped[str] = mapped_column(String(10))  # "user" or "model"
    emotion: Mapped[str | None] = mapped_column(String(20))
    session_id: Mapped[str] = mapped_column(String(36), index=True)
    character_id: Mapped[str | None] = mapped_column(String(36), index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
