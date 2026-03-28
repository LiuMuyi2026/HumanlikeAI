"""Gemini text chat service using the standard (non-Live) Gemini API."""

import logging
import mimetypes

from google import genai
from google.genai import types

from app.models.message import ChatMessage
from app.services.emotion import classify_to_circumplex
from app.services.emotion_model import EmotionState

logger = logging.getLogger(__name__)


class GeminiChatService:
    """Handles text-based chat using the standard Gemini API."""

    def __init__(self, api_key: str, model: str = "models/gemini-2.5-flash"):
        self._client = genai.Client(api_key=api_key)
        self._model = model

    async def send_message(
        self,
        system_prompt: str,
        user_text: str,
        conversation_history: list[ChatMessage] | None = None,
        image_path: str | None = None,
        audio_path: str | None = None,
        character_mbti: str | None = None,
        relationship_type: str | None = None,
        familiarity_level: int = 5,
        prev_emotion: EmotionState | None = None,
    ) -> tuple[str, EmotionState]:
        """Send a message and get a text response from Gemini.

        Returns:
            Tuple of (response_text, emotion_state).
        """
        # Build conversation contents
        contents: list[types.Content] = []

        # Add conversation history
        if conversation_history:
            for msg in conversation_history:
                role = "user" if msg.role == "user" else "model"
                parts: list[types.Part] = []
                if msg.content:
                    parts.append(types.Part(text=msg.content))
                if parts:
                    contents.append(types.Content(role=role, parts=parts))

        # Build current user message parts
        user_parts: list[types.Part] = []

        # Add image if provided
        if image_path:
            mime_type = mimetypes.guess_type(image_path)[0] or "image/jpeg"
            with open(image_path, "rb") as f:
                image_data = f.read()
            user_parts.append(
                types.Part(inline_data=types.Blob(data=image_data, mime_type=mime_type))
            )

        # Add audio if provided
        if audio_path:
            mime_type = mimetypes.guess_type(audio_path)[0] or "audio/webm"
            with open(audio_path, "rb") as f:
                audio_data = f.read()
            user_parts.append(
                types.Part(inline_data=types.Blob(data=audio_data, mime_type=mime_type))
            )
            # Add instruction to transcribe and respond
            if not user_text:
                user_text = "请听这段语音消息并回复。"

        user_parts.append(types.Part(text=user_text))
        contents.append(types.Content(role="user", parts=user_parts))

        # Call Gemini
        response = await self._client.aio.models.generate_content(
            model=self._model,
            contents=contents,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=0.9,
                max_output_tokens=500,
            ),
        )

        response_text = response.text or ""
        logger.info("Gemini text response: %s", response_text[:100])

        # Classify emotion
        emotion = classify_to_circumplex(
            response_text,
            relationship_type=relationship_type,
            familiarity_level=familiarity_level,
            mbti=character_mbti,
            prev_state=prev_emotion,
        )

        return response_text, emotion
