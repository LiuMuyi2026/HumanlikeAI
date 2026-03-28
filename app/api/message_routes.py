import asyncio
import logging
import os
import random
import uuid
from datetime import datetime

from fastapi import APIRouter, HTTPException, Query, UploadFile, File
from fastapi.responses import FileResponse

from app.config import get_settings
from app.db.repositories.character_repo import CharacterRepository
from app.db.repositories.message_repo import MessageRepository
from app.db.repositories.user_repo import UserRepository
from app.db.session import async_session_factory
from app.schemas.message import MessageListResponse, MessageResponse, SendMessageRequest
from app.services.emotion_model import EmotionState
from app.services.gemini_chat import GeminiChatService
from app.services.media import save_upload
from app.services.memory import MemoryService
from app.services.embeddings import EmbeddingService
from app.services.prompt_builder import build_system_prompt
from app.workers.memory_worker import process_conversation_memory

logger = logging.getLogger(__name__)
router = APIRouter(tags=["messages"])

# Lock per (character_id, user_id) to prevent stacking proactive tasks
_proactive_locks: dict[tuple[str, str], asyncio.Lock] = {}


def _fire_memory_task(
    user_id: str,
    character_id: str,
    user_text: str,
    ai_text: str,
) -> None:
    """Fire-and-forget background task to store conversation memory."""
    settings = get_settings()
    if not settings.pinecone_api_key or not settings.pinecone_index_host:
        return

    transcript = [
        {"role": "user", "text": user_text},
        {"role": "model", "text": ai_text},
    ]
    session_id = f"text-{uuid.uuid4().hex[:12]}"

    asyncio.create_task(
        process_conversation_memory(
            user_id=user_id,
            session_id=session_id,
            transcript=transcript,
            gemini_api_key=settings.gemini_api_key,
            pinecone_api_key=settings.pinecone_api_key,
            pinecone_index_host=settings.pinecone_index_host,
            database_url=settings.database_url,
            character_id=character_id,
        )
    )


async def _load_prev_emotion(
    msg_repo: MessageRepository,
    character_id: str,
    user_id: str,
) -> EmotionState | None:
    """Load the last AI emotion state for emotion inertia."""
    last_ai = await msg_repo.get_last_ai_emotion(character_id, user_id)
    if last_ai and last_ai.emotion:
        return EmotionState(
            valence=last_ai.valence or 0.0,
            arousal=last_ai.arousal or 0.2,
            label=last_ai.emotion,
            intensity=last_ai.intensity or "low",
        )
    return None


def _fire_proactive_task(
    user_id: str,
    character_id: str,
    emotion: EmotionState,
) -> None:
    """Schedule a delayed proactive AI follow-up if emotion arousal is high."""
    if emotion.arousal <= 0.65:
        return

    key = (character_id, user_id)
    if key not in _proactive_locks:
        _proactive_locks[key] = asyncio.Lock()

    asyncio.create_task(
        _maybe_send_proactive(user_id, character_id, emotion, _proactive_locks[key])
    )


async def _maybe_send_proactive(
    user_id: str,
    character_id: str,
    emotion: EmotionState,
    lock: asyncio.Lock,
) -> None:
    """After a random delay, generate and save a proactive AI message."""
    if lock.locked():
        return  # another proactive task is already running

    async with lock:
        delay = random.uniform(8, 25)
        logger.info(
            "Proactive message scheduled for %s/%s in %.1fs (emotion=%s)",
            character_id, user_id, delay, emotion.label,
        )
        await asyncio.sleep(delay)

        try:
            settings = get_settings()
            async with async_session_factory() as session:
                char_repo = CharacterRepository(session)
                character = await char_repo.get_by_id_and_user(character_id, user_id)
                if character is None:
                    return

                user_repo = UserRepository(session)
                user = await user_repo.get_by_id(user_id)
                if user is None:
                    return

                system_prompt = await _build_chat_context(character, user, user_id)

                msg_repo = MessageRepository(session)
                history = await msg_repo.get_recent_context(character_id, user_id, limit=20)

                chat_svc = GeminiChatService(
                    api_key=settings.gemini_api_key,
                    model="models/gemini-2.5-flash",
                )
                proactive_instruction = (
                    f"你现在感到{emotion.label}，"
                    "请主动发一条消息表达你的感受。不要重复之前说过的话，自然一点。"
                )
                response_text, new_emotion = await chat_svc.send_message(
                    system_prompt=system_prompt,
                    user_text=proactive_instruction,
                    conversation_history=history,
                    character_mbti=character.mbti,
                    relationship_type=character.relationship_type,
                    familiarity_level=character.familiarity_level or 5,
                    prev_emotion=emotion,
                )

                await msg_repo.create(
                    character_id=character_id,
                    user_id=user_id,
                    role="ai",
                    content_type="text",
                    content=response_text,
                    emotion=new_emotion.label,
                    valence=new_emotion.valence,
                    arousal=new_emotion.arousal,
                    intensity=new_emotion.intensity,
                )
                logger.info("Proactive message sent for %s/%s", character_id, user_id)
        except Exception:
            logger.exception("Proactive message failed for %s/%s", character_id, user_id)


async def _build_chat_context(character, user, user_id: str):
    """Build system prompt and memory context for a chat message."""
    settings = get_settings()

    user_facts = user.extracted_facts
    user_prefs = user.preferences
    user_location = user.location

    # Memory recall
    memory_snippets: list[str] = []
    if settings.pinecone_api_key and settings.pinecone_index_host:
        try:
            embedding_svc = EmbeddingService(api_key=settings.gemini_api_key)
            memory_svc = MemoryService(
                api_key=settings.pinecone_api_key,
                index_host=settings.pinecone_index_host,
                embedding_service=embedding_svc,
            )
            memory_namespace = f"{user_id}:{character.id}"
            memory_snippets = await memory_svc.recall_memories(
                user_id=memory_namespace,
                query_text=f"Recent conversation with {user.display_name or 'user'}",
                top_k=settings.memory_top_k,
            )
        except Exception as e:
            logger.warning("Memory recall failed: %s", e)

    system_prompt = build_system_prompt(
        user_facts=user_facts,
        user_preferences=user_prefs,
        memory_snippets=memory_snippets,
        user_location=user_location,
        character=character,
    )
    # Add text chat specific instruction
    system_prompt += """

注意：这是文字聊天，不是语音通话。
- 回复要像发微信/短信一样自然简短，一般1-3句话
- 不要用书面语，用口语化的表达
- 可以用网络用语、表情符号(但不要过多)
- 像真人朋友发消息一样，有时候回复就一个字"嗯"或者"哈哈"也完全可以
- 自然地接话题、找新话题，不要每次都问"你呢？"
- 分享自己的事情来推动对话，而不是只问问题
- 回复风格要多变，不要每条消息都是相同的句式结构"""

    return system_prompt


@router.get(
    "/{character_id}/messages",
    response_model=MessageListResponse,
)
async def list_messages(
    character_id: str,
    user_id: str = Query(...),
    limit: int = Query(50, ge=1, le=100),
    before: datetime | None = Query(None),
):
    """List chat message history (paginated, newest last)."""
    async with async_session_factory() as session:
        char_repo = CharacterRepository(session)
        character = await char_repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

        msg_repo = MessageRepository(session)
        messages = await msg_repo.list_messages(
            character_id, user_id, limit=limit + 1, before=before
        )

        has_more = len(messages) > limit
        if has_more:
            messages = messages[1:]  # remove oldest extra message

        return MessageListResponse(messages=messages, has_more=has_more)


@router.post(
    "/{character_id}/messages",
    response_model=list[MessageResponse],
)
async def send_text_message(
    character_id: str,
    body: SendMessageRequest,
    user_id: str = Query(...),
):
    """Send a text message and get AI response."""
    settings = get_settings()

    async with async_session_factory() as session:
        char_repo = CharacterRepository(session)
        character = await char_repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

        user_repo = UserRepository(session)
        user = await user_repo.get_by_id(user_id)
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")

        msg_repo = MessageRepository(session)

        # Save user message
        user_msg = await msg_repo.create(
            character_id=character_id,
            user_id=user_id,
            role="user",
            content_type="text",
            content=body.content,
        )

        # Load conversation history for context
        history = await msg_repo.get_recent_context(character_id, user_id, limit=20)

        # Load previous emotion for inertia
        prev_emotion = await _load_prev_emotion(msg_repo, character_id, user_id)

        # Build context
        system_prompt = await _build_chat_context(character, user, user_id)

        # Call Gemini
        chat_svc = GeminiChatService(
            api_key=settings.gemini_api_key,
            model="models/gemini-2.5-flash",
        )
        response_text, emotion = await chat_svc.send_message(
            system_prompt=system_prompt,
            user_text=body.content,
            conversation_history=history[:-1],  # exclude the just-saved user msg
            character_mbti=character.mbti,
            relationship_type=character.relationship_type,
            familiarity_level=character.familiarity_level or 5,
            prev_emotion=prev_emotion,
        )

        # Save AI response
        ai_msg = await msg_repo.create(
            character_id=character_id,
            user_id=user_id,
            role="ai",
            content_type="text",
            content=response_text,
            emotion=emotion.label,
            valence=emotion.valence,
            arousal=emotion.arousal,
            intensity=emotion.intensity,
        )

        # Store to memory (shared with voice/video chat)
        _fire_memory_task(user_id, character_id, body.content, response_text)

        # Schedule proactive follow-up if emotion is intense
        _fire_proactive_task(user_id, character_id, emotion)

        return [user_msg, ai_msg]


@router.post(
    "/{character_id}/messages/image",
    response_model=list[MessageResponse],
)
async def send_image_message(
    character_id: str,
    user_id: str = Query(...),
    file: UploadFile = File(...),
):
    """Send an image and get AI response."""
    settings = get_settings()

    # Validate file type
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="File must be an image")

    async with async_session_factory() as session:
        char_repo = CharacterRepository(session)
        character = await char_repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

        user_repo = UserRepository(session)
        user = await user_repo.get_by_id(user_id)
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")

        # Save uploaded file
        file_path = await save_upload(file, "images", character_id)

        msg_repo = MessageRepository(session)

        # Save user message
        user_msg = await msg_repo.create(
            character_id=character_id,
            user_id=user_id,
            role="user",
            content_type="image",
            media_url=file_path,
        )

        # Load conversation history
        history = await msg_repo.get_recent_context(character_id, user_id, limit=20)

        # Load previous emotion for inertia
        prev_emotion = await _load_prev_emotion(msg_repo, character_id, user_id)

        # Build context
        system_prompt = await _build_chat_context(character, user, user_id)

        # Call Gemini with image
        chat_svc = GeminiChatService(
            api_key=settings.gemini_api_key,
            model="models/gemini-2.5-flash",
        )
        response_text, emotion = await chat_svc.send_message(
            system_prompt=system_prompt,
            user_text="用户发了一张图片给你，请自然地回应。",
            image_path=file_path,
            conversation_history=history[:-1],
            character_mbti=character.mbti,
            relationship_type=character.relationship_type,
            familiarity_level=character.familiarity_level or 5,
            prev_emotion=prev_emotion,
        )

        # Save AI response
        ai_msg = await msg_repo.create(
            character_id=character_id,
            user_id=user_id,
            role="ai",
            content_type="text",
            content=response_text,
            emotion=emotion.label,
            valence=emotion.valence,
            arousal=emotion.arousal,
            intensity=emotion.intensity,
        )

        # Store to memory (shared with voice/video chat)
        _fire_memory_task(
            user_id, character_id,
            "[用户发了一张图片]", response_text,
        )

        # Schedule proactive follow-up if emotion is intense
        _fire_proactive_task(user_id, character_id, emotion)

        return [user_msg, ai_msg]


@router.post(
    "/{character_id}/messages/voice",
    response_model=list[MessageResponse],
)
async def send_voice_message(
    character_id: str,
    user_id: str = Query(...),
    file: UploadFile = File(...),
):
    """Send a voice message and get AI text response."""
    settings = get_settings()

    # Validate file type
    if not file.content_type or not file.content_type.startswith("audio/"):
        raise HTTPException(status_code=400, detail="File must be audio")

    async with async_session_factory() as session:
        char_repo = CharacterRepository(session)
        character = await char_repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

        user_repo = UserRepository(session)
        user = await user_repo.get_by_id(user_id)
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")

        # Save uploaded file
        file_path = await save_upload(file, "voices", character_id)

        msg_repo = MessageRepository(session)

        # Save user message (content will be filled after transcription)
        user_msg = await msg_repo.create(
            character_id=character_id,
            user_id=user_id,
            role="user",
            content_type="voice",
            media_url=file_path,
        )

        # Load conversation history
        history = await msg_repo.get_recent_context(character_id, user_id, limit=20)

        # Load previous emotion for inertia
        prev_emotion = await _load_prev_emotion(msg_repo, character_id, user_id)

        # Build context
        system_prompt = await _build_chat_context(character, user, user_id)

        # Call Gemini with audio — it will understand the audio content
        chat_svc = GeminiChatService(
            api_key=settings.gemini_api_key,
            model="models/gemini-2.5-flash",
        )
        response_text, emotion = await chat_svc.send_message(
            system_prompt=system_prompt,
            user_text="",
            audio_path=file_path,
            conversation_history=history[:-1],
            character_mbti=character.mbti,
            relationship_type=character.relationship_type,
            familiarity_level=character.familiarity_level or 5,
            prev_emotion=prev_emotion,
        )

        # Save AI response
        ai_msg = await msg_repo.create(
            character_id=character_id,
            user_id=user_id,
            role="ai",
            content_type="text",
            content=response_text,
            emotion=emotion.label,
            valence=emotion.valence,
            arousal=emotion.arousal,
            intensity=emotion.intensity,
        )

        # Store to memory (shared with voice/video chat)
        _fire_memory_task(
            user_id, character_id,
            "[用户发了一条语音消息]", response_text,
        )

        # Schedule proactive follow-up if emotion is intense
        _fire_proactive_task(user_id, character_id, emotion)

        return [user_msg, ai_msg]


@router.get(
    "/{character_id}/messages/new",
    response_model=list[MessageResponse],
)
async def list_new_messages(
    character_id: str,
    user_id: str = Query(...),
    after: datetime = Query(..., description="ISO timestamp to fetch messages after"),
):
    """Poll for new messages created after a given timestamp."""
    async with async_session_factory() as session:
        char_repo = CharacterRepository(session)
        character = await char_repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise HTTPException(status_code=404, detail="Character not found")

        msg_repo = MessageRepository(session)
        messages = await msg_repo.list_messages_after(character_id, user_id, after)
        return messages


@router.get("/{character_id}/messages/{message_id}/media")
async def get_message_media(
    character_id: str,
    message_id: str,
    user_id: str = Query(...),
):
    """Serve a media file (image or voice) for a message."""
    async with async_session_factory() as session:
        msg_repo = MessageRepository(session)
        message = await msg_repo.get_message(message_id)

        if message is None or message.character_id != character_id:
            raise HTTPException(status_code=404, detail="Message not found")
        if message.user_id != user_id:
            raise HTTPException(status_code=403, detail="Access denied")
        if not message.media_url or not os.path.exists(message.media_url):
            raise HTTPException(status_code=404, detail="Media file not found")

        return FileResponse(message.media_url)
