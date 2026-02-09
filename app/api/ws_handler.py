import asyncio
import base64
import json
import logging
import time
import uuid

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from app.config import get_settings
from app.db.repositories.character_repo import CharacterRepository
from app.db.repositories.message_repo import MessageRepository
from app.db.repositories.user_repo import UserRepository
from app.db.repositories.news_repo import NewsRepository
from app.db.session import async_session_factory
from app.schemas.ws_messages import server_message
from app.services.emotion import classify_to_circumplex
from app.services.emotion_model import EmotionState, emotion_to_image_key
from app.services.gemini_live import GeminiLiveSession
from app.services.memory import MemoryService
from app.services.embeddings import EmbeddingService
from app.services.prompt_builder import build_system_prompt
from app.services.news_search import NewsSearchService

logger = logging.getLogger(__name__)
router = APIRouter()


class SessionState:
    """Mutable state for a single user WebSocket session."""

    def __init__(self):
        self.user_id: str | None = None
        self.session_id: str = str(uuid.uuid4())
        self.current_emotion: EmotionState = EmotionState(
            valence=0.0, arousal=0.2, label="neutral", intensity="low"
        )
        self.transcript_buffer: list[dict] = []
        self.gemini_session: GeminiLiveSession | None = None
        self.running: bool = True
        self.last_activity_time: float = 0.0
        self.user_location: str | None = None
        self.news_context: list[dict] = []
        self.character_id: str | None = None
        self.ai_location: str | None = None
        self.relationship_type: str | None = None
        self.familiarity_level: int = 5
        self.mbti: str | None = None
        self.memory_svc: MemoryService | None = None
        self.memory_namespace: str | None = None
        self.news_svc: NewsSearchService | None = None
        # Feature 3: Only reclassify emotion after user interaction
        self.user_interacted_since_last_emotion: bool = True  # True so first greeting classifies
        # Feature 1: Emotional burst state
        self.burst_count: int = 0
        self.burst_cooldown_until: float = 0.0


# Feature 1: Emotional burst constants
BURST_AROUSAL_THRESHOLD = 0.7
BURST_MAX_FOLLOW_UPS = 3
BURST_COOLDOWN_SECONDS = 30.0
BURST_FOLLOW_UP_PROMPTS = [
    "你还有更多想说的，继续表达你的感受，自然地补充一两句。",
    "你觉得意犹未尽，再说一点你的想法。",
    "你还想再说点什么，简短地补充。",
]

# Default starting emotions per relationship type (valence, arousal, label, intensity)
RELATIONSHIP_DEFAULT_EMOTIONS: dict[str, tuple[float, float, str, str]] = {
    "Romantic Partner": (0.6, 0.5, "loving", "medium"),
    "Best Friend": (0.5, 0.4, "happy", "medium"),
    "Friend": (0.3, 0.3, "happy", "low"),
    "Companion": (0.3, 0.3, "happy", "low"),
    "Mentor": (0.2, 0.3, "thinking", "low"),
    "Confidant": (0.2, 0.3, "thinking", "low"),
    "Rival": (0.1, 0.5, "excited", "medium"),
    "Frenemy": (0.0, 0.4, "surprised", "low"),
    "Nemesis": (-0.2, 0.5, "angry", "low"),
    "Critic": (0.0, 0.3, "thinking", "low"),
    "Ex-Partner": (-0.3, 0.4, "sad", "low"),
    "Stranger": (0.0, 0.2, "neutral", "low"),
    "Acquaintance": (0.1, 0.2, "neutral", "low"),
    "Colleague": (0.1, 0.2, "neutral", "low"),
    "Study Buddy": (0.2, 0.3, "thinking", "low"),
    "Advisor": (0.2, 0.3, "thinking", "low"),
}

# Keywords that trigger proactive memory recall
RECALL_TRIGGERS = {
    "记得", "上次", "之前", "以前", "还记得", "说过", "聊过", "提过", "讲过",
    "remember", "last time", "before", "mentioned", "told you",
}

# Keywords that trigger proactive web search
SEARCH_TRIGGERS = {
    "新闻", "搜索", "查一下", "搜一下", "最新", "最近发生", "现在",
    "news", "search", "look up", "what's happening", "latest",
    "天气", "weather", "比分", "score", "股票", "stock",
    "帮我查", "帮我搜", "你知道", "告诉我",
}


async def _execute_tool(name: str, args: dict, state: SessionState) -> str:
    """Execute a single tool call and return the result as text."""
    if name == "recall_memory":
        if not state.memory_svc or not state.memory_namespace:
            return "Memory service not available."
        query = args.get("query", "")
        memories = await state.memory_svc.recall_memories(
            user_id=state.memory_namespace,
            query_text=query,
            top_k=8,
        )
        if memories:
            return "\n".join(f"- {m}" for m in memories)
        return "No relevant memories found for this query."

    elif name == "search_web":
        if not state.news_svc:
            return "Search service not available."
        query = args.get("query", "")
        results = await state.news_svc.search_news(
            query=query,
            location=state.user_location,
            max_results=5,
        )
        if results:
            formatted = []
            for r in results:
                title = r.get("title", "")
                summary = r.get("summary", "")
                source = r.get("source", "")
                formatted.append(f"- {title} ({source}): {summary}")
            return "\n".join(formatted)
        return "No search results found."

    return f"Unknown tool: {name}"


async def _proactive_search(text: str, ws: WebSocket, state: SessionState):
    """Detect user intent and proactively inject search/recall results."""
    text_lower = text.lower()

    # Check for memory recall triggers
    for trigger in RECALL_TRIGGERS:
        if trigger in text_lower:
            try:
                await ws.send_json(
                    server_message("status", {"action": "searching", "tool": "recall_memory"})
                )
                result = await _execute_tool("recall_memory", {"query": text}, state)
                if result and "No relevant" not in result:
                    await state.gemini_session.inject_context(
                        f"[你回忆起了以下相关内容，请自然地融入回答中]:\n{result}"
                    )
                    logger.info("Injected recalled memories for: %s", text[:60])
                await ws.send_json(
                    server_message("status", {"action": "done", "tool": "recall_memory"})
                )
            except Exception as e:
                logger.warning("Proactive recall failed: %s", e)
            return

    # Check for web search triggers
    for trigger in SEARCH_TRIGGERS:
        if trigger in text_lower:
            try:
                await ws.send_json(
                    server_message("status", {"action": "searching", "tool": "search_web"})
                )
                result = await _execute_tool("search_web", {"query": text}, state)
                if result and "No search" not in result:
                    await state.gemini_session.inject_context(
                        f"[以下是你搜索到的最新信息，请自然地分享给用户]:\n{result}"
                    )
                    logger.info("Injected search results for: %s", text[:60])
                await ws.send_json(
                    server_message("status", {"action": "done", "tool": "search_web"})
                )
            except Exception as e:
                logger.warning("Proactive search failed: %s", e)
            return


@router.websocket("/ws")
async def websocket_endpoint(ws: WebSocket):
    await ws.accept()
    state = SessionState()
    settings = get_settings()
    client_task = None
    gemini_task = None
    idle_task = None

    try:
        # === Phase 1: Authentication ===
        raw = await asyncio.wait_for(ws.receive_text(), timeout=10.0)
        msg = json.loads(raw)

        if msg.get("type") != "auth":
            await ws.send_json(
                server_message(
                    "error",
                    {"code": "AUTH_REQUIRED", "message": "First message must be auth"},
                )
            )
            await ws.close()
            return

        device_id = msg["payload"]["device_id"]
        display_name = msg["payload"].get("display_name")
        user_location_from_client = msg["payload"].get("location")
        character_id_from_client = msg["payload"].get("character_id")

        # Upsert user in PostgreSQL
        character = None
        async with async_session_factory() as db_session:
            repo = UserRepository(db_session)
            user = await repo.get_or_create(
                device_id=device_id, display_name=display_name
            )
            state.user_id = user.id
            user_facts = user.extracted_facts
            user_prefs = user.preferences
            user_location = user.location or user_location_from_client

            # Update user location if provided from client
            if user_location_from_client and user_location_from_client != user.location:
                user.location = user_location_from_client
                await db_session.commit()
                user_location = user_location_from_client

            # Load character if specified
            if character_id_from_client:
                char_repo = CharacterRepository(db_session)
                character = await char_repo.get_by_id_and_user(
                    character_id_from_client, user.id
                )
                if character is None:
                    await ws.send_json(
                        server_message(
                            "error",
                            {"code": "CHARACTER_NOT_FOUND", "message": "Character not found or not owned by user"},
                        )
                    )
                    await ws.close()
                    return
                state.character_id = character.id
                state.ai_location = character.region or "Tokyo, Japan"
                state.relationship_type = character.relationship_type
                state.familiarity_level = character.familiarity_level or 5
                state.mbti = character.mbti

                # Load initial emotion from last conversation or relationship default
                msg_repo = MessageRepository(db_session)
                last_ai = await msg_repo.get_last_ai_emotion(character.id, user.id)
                if last_ai and last_ai.emotion:
                    state.current_emotion = EmotionState(
                        valence=last_ai.valence or 0.0,
                        arousal=last_ai.arousal or 0.2,
                        label=last_ai.emotion,
                        intensity=last_ai.intensity or "low",
                    )
                    logger.info("Initial emotion from history: %s", last_ai.emotion)
                elif character.relationship_type and character.relationship_type in RELATIONSHIP_DEFAULT_EMOTIONS:
                    v, a, label, intensity = RELATIONSHIP_DEFAULT_EMOTIONS[character.relationship_type]
                    state.current_emotion = EmotionState(
                        valence=v, arousal=a, label=label, intensity=intensity,
                    )
                    logger.info("Initial emotion from relationship (%s): %s", character.relationship_type, label)

        # === Phase 2: Load context & build prompt ===
        # Initialize services for use during session (tool calls)
        memory_snippets: list[str] = []
        if settings.pinecone_api_key and settings.pinecone_index_host:
            try:
                embedding_svc = EmbeddingService(api_key=settings.gemini_api_key)
                memory_svc = MemoryService(
                    api_key=settings.pinecone_api_key,
                    index_host=settings.pinecone_index_host,
                    embedding_service=embedding_svc,
                )
                # Use character-scoped namespace if character is selected
                memory_namespace = f"{user.id}:{state.character_id}" if state.character_id else user.id

                # Store on session state so tools can access them mid-conversation
                state.memory_svc = memory_svc
                state.memory_namespace = memory_namespace

                memory_snippets = await memory_svc.recall_memories(
                    user_id=memory_namespace,
                    query_text=f"Recent conversation with {display_name or 'user'}",
                    top_k=settings.memory_top_k,
                )
                logger.info("Recalled %d memories for user=%s", len(memory_snippets), user.id)
            except Exception as e:
                logger.warning("Memory recall failed, continuing without: %s", e)

        # === Phase 2b: Fetch news for conversation topics ===
        news_context: list[dict] = []
        state.user_location = user_location
        try:
            news_svc = NewsSearchService(gemini_api_key=settings.gemini_api_key)
            state.news_svc = news_svc  # Store for mid-conversation tool calls
            async with async_session_factory() as db_session:
                news_repo = NewsRepository(db_session)
                # Cleanup expired news
                cleaned = await news_repo.cleanup_expired()
                if cleaned > 0:
                    logger.info("Cleaned up %d expired news items", cleaned)

                # Check for cached recent news first
                cached_news = await news_repo.get_news_for_topics(limit=6)
                if cached_news:
                    news_context = cached_news
                    logger.info("Using %d cached news items", len(news_context))
                else:
                    # Fetch fresh news
                    ai_loc = state.ai_location or "Tokyo, Japan"
                    news_items = await news_svc.search_local_news(
                        user_location=user_location,
                        ai_location=ai_loc,
                    )
                    if news_items:
                        await news_repo.store_news(news_items)
                        news_context = [
                            {
                                "title": n.get("title"),
                                "summary": n.get("summary"),
                                "location": n.get("location"),
                            }
                            for n in news_items
                        ]
                        logger.info("Fetched and stored %d news items", len(news_items))

                        # Store news as memory in Pinecone (background task)
                        if settings.pinecone_api_key and settings.pinecone_index_host:
                            from app.workers.memory_worker import store_news_as_memory
                            asyncio.create_task(
                                store_news_as_memory(
                                    user_id=state.user_id,
                                    news_items=news_items,
                                    gemini_api_key=settings.gemini_api_key,
                                    pinecone_api_key=settings.pinecone_api_key,
                                    pinecone_index_host=settings.pinecone_index_host,
                                )
                            )
        except Exception as e:
            logger.warning("News fetch failed, continuing without: %s", e)

        state.news_context = news_context

        system_prompt = build_system_prompt(
            user_facts=user_facts,
            user_preferences=user_prefs,
            memory_snippets=memory_snippets,
            news_context=news_context,
            user_location=user_location,
            character=character,
        )

        # === Phase 3: Open Gemini Live session ===
        state.gemini_session = GeminiLiveSession(
            api_key=settings.gemini_api_key,
            model=settings.gemini_live_model,
            system_prompt=system_prompt,
        )
        await state.gemini_session.connect()

        await ws.send_json(
            server_message(
                "auth_ok",
                {"user_id": user.id, "session_id": state.session_id},
            )
        )
        logger.info("Session started: user=%s session=%s", user.id, state.session_id)

        # Send initial greeting prompt to ensure Gemini starts talking
        if character:
            greeting_prompt = f"你是{character.name}。用中文自然地打个招呼，简短亲切，符合你的性格设定。"
        else:
            greeting_prompt = "用中文自然地打个招呼，就像老朋友一样，简短亲切。"
        await state.gemini_session.send_text(greeting_prompt)

        # === Phase 4: Bidirectional streaming ===
        state.last_activity_time = time.time()
        client_task = asyncio.create_task(_forward_client_to_gemini(ws, state))
        gemini_task = asyncio.create_task(_forward_gemini_to_client(ws, state))
        idle_task = asyncio.create_task(_idle_topic_prompter(state, settings))

        # Client task controls session lifetime — wait for it
        await client_task

        # Client is done, cancel other tasks
        for task in [gemini_task, idle_task]:
            task.cancel()
            try:
                await task
            except (asyncio.CancelledError, Exception):
                pass

    except WebSocketDisconnect:
        logger.info("Client disconnected: user=%s", state.user_id)
    except asyncio.TimeoutError:
        try:
            await ws.send_json(
                server_message(
                    "error", {"code": "TIMEOUT", "message": "Auth timeout"}
                )
            )
        except Exception:
            pass
    except Exception as e:
        logger.exception("Session error: %s", e)
        try:
            await ws.send_json(
                server_message(
                    "error", {"code": "INTERNAL", "message": str(e)}
                )
            )
        except Exception:
            pass
    finally:
        state.running = False

        # Cancel any remaining tasks
        for task in [client_task, gemini_task, idle_task]:
            if task and not task.done():
                task.cancel()

        # Cleanup Gemini session
        if state.gemini_session:
            await state.gemini_session.close()

        # Dispatch background memory processing
        if state.transcript_buffer and state.user_id:
            settings = get_settings()
            if settings.pinecone_api_key and settings.pinecone_index_host:
                from app.workers.memory_worker import process_conversation_memory

                asyncio.create_task(
                    process_conversation_memory(
                        user_id=state.user_id,
                        session_id=state.session_id,
                        transcript=state.transcript_buffer,
                        gemini_api_key=settings.gemini_api_key,
                        pinecone_api_key=settings.pinecone_api_key,
                        pinecone_index_host=settings.pinecone_index_host,
                        database_url=settings.database_url,
                        character_id=state.character_id,
                    )
                )

        try:
            await ws.close()
        except Exception:
            pass

        logger.info("Session ended: user=%s", state.user_id)


async def _forward_client_to_gemini(ws: WebSocket, state: SessionState):
    """Read messages from Flutter client, forward to Gemini Live."""
    max_retries = 3

    try:
        while state.running:
            raw = await ws.receive_text()
            msg = json.loads(raw)

            if msg["type"] == "audio":
                audio_bytes = base64.b64decode(msg["payload"]["data"])
                # Try sending with reconnect on Gemini errors
                for attempt in range(max_retries):
                    try:
                        await state.gemini_session.send_audio(audio_bytes)
                        break
                    except Exception as e:
                        logger.warning(
                            "Gemini send_audio failed (attempt %d/%d): %s",
                            attempt + 1, max_retries, e,
                        )
                        if attempt < max_retries - 1:
                            if not await state.gemini_session.reconnect():
                                logger.error("Cannot reconnect to Gemini after send_audio failure")
                                await ws.send_json(
                                    server_message("error", {"code": "GEMINI_DISCONNECTED", "message": "Lost connection to AI"})
                                )
                                return
                            await asyncio.sleep(0.5)
                        else:
                            logger.error("Exhausted retries for send_audio")
                state.last_activity_time = time.time()
                state.user_interacted_since_last_emotion = True
                state.burst_count = 0
                logger.debug("Forwarded %d bytes audio to Gemini", len(audio_bytes))

            elif msg["type"] == "text":
                text = msg["payload"]["text"]
                state.transcript_buffer.append({"role": "user", "text": text})
                # Try sending with reconnect on Gemini errors
                for attempt in range(max_retries):
                    try:
                        await state.gemini_session.send_text(text)
                        break
                    except Exception as e:
                        logger.warning(
                            "Gemini send_text failed (attempt %d/%d): %s",
                            attempt + 1, max_retries, e,
                        )
                        if attempt < max_retries - 1:
                            if not await state.gemini_session.reconnect():
                                logger.error("Cannot reconnect to Gemini after send_text failure")
                                await ws.send_json(
                                    server_message("error", {"code": "GEMINI_DISCONNECTED", "message": "Lost connection to AI"})
                                )
                                return
                            await asyncio.sleep(0.5)
                        else:
                            logger.error("Exhausted retries for send_text")
                state.last_activity_time = time.time()
                state.user_interacted_since_last_emotion = True
                state.burst_count = 0
                logger.info("User text: %s", text[:100])

                # Proactive search/recall in background (doesn't block)
                asyncio.create_task(_proactive_search(text, ws, state))

            elif msg["type"] == "control":
                if msg["payload"].get("action") == "end_session":
                    return
    except WebSocketDisconnect:
        logger.info("Client WebSocket disconnected")
    except asyncio.CancelledError:
        pass
    except Exception as e:
        logger.exception("Error in client->gemini: %s", e)


async def _forward_gemini_to_client(ws: WebSocket, state: SessionState):
    """Read responses from Gemini Live, parse emotion, forward to client.

    The Gemini Live API generator exits after every turn_complete.
    We handle this by fast-reconnecting and injecting conversation context
    so the model maintains continuity across turns.
    """
    try:
        while state.running:
            try:
                async for response in state.gemini_session.receive_responses():
                    if not state.running:
                        return

                    # Handle go_away — server wants to end session soon
                    go_away = getattr(response, "go_away", None)
                    if go_away:
                        logger.info("Received go_away from Gemini")
                        break

                    server_content = getattr(response, "server_content", None)
                    if server_content is None:
                        continue

                    # Handle interruption
                    if getattr(server_content, "interrupted", False):
                        await ws.send_json(server_message("interrupted"))
                        continue

                    # Handle turn completion
                    if getattr(server_content, "turn_complete", False):
                        await ws.send_json(server_message("turn_complete"))
                        state.last_activity_time = time.time()
                        logger.debug(
                            "AI turn complete, emotion=%s", state.current_emotion.label
                        )
                        continue

                    # Process model output parts
                    model_turn = getattr(server_content, "model_turn", None)
                    if model_turn and model_turn.parts:
                        for part in model_turn.parts:
                            inline_data = getattr(part, "inline_data", None)
                            if (
                                inline_data
                                and getattr(inline_data, "mime_type", None)
                                and "audio" in inline_data.mime_type
                            ):
                                audio_b64 = base64.b64encode(
                                    inline_data.data
                                ).decode("utf-8")
                                emo = state.current_emotion
                                await ws.send_json(
                                    server_message(
                                        "audio",
                                        {
                                            "data": audio_b64,
                                            "mime_type": "audio/pcm;rate=24000",
                                            "emotion": emo.label,
                                            "valence": emo.valence,
                                            "arousal": emo.arousal,
                                            "intensity": emo.intensity,
                                        },
                                    )
                                )

                    # Handle output transcription (spoken content transcript)
                    output_transcription = getattr(
                        server_content, "output_transcription", None
                    )
                    if output_transcription and getattr(
                        output_transcription, "text", None
                    ):
                        text = output_transcription.text
                        # Feature 3: Only reclassify emotion after user interaction
                        if state.user_interacted_since_last_emotion:
                            emo = classify_to_circumplex(
                                text,
                                relationship_type=state.relationship_type,
                                familiarity_level=state.familiarity_level,
                                mbti=state.mbti,
                                prev_state=state.current_emotion,
                            )
                            state.current_emotion = emo
                            state.user_interacted_since_last_emotion = False
                        else:
                            emo = state.current_emotion
                        if text.strip():
                            state.transcript_buffer.append(
                                {"role": "model", "text": text, "emotion": emo.label}
                            )
                            await ws.send_json(
                                server_message(
                                    "text",
                                    {
                                        "text": text,
                                        "emotion": emo.label,
                                        "valence": emo.valence,
                                        "arousal": emo.arousal,
                                        "intensity": emo.intensity,
                                    },
                                )
                            )

                    # Handle input transcription (user speech-to-text)
                    input_transcription = getattr(
                        server_content, "input_transcription", None
                    )
                    if input_transcription and getattr(
                        input_transcription, "text", None
                    ):
                        user_text = input_transcription.text
                        state.transcript_buffer.append(
                            {"role": "user", "text": user_text}
                        )
                        state.user_interacted_since_last_emotion = True
                        # Proactive search/recall based on speech
                        asyncio.create_task(
                            _proactive_search(user_text, ws, state)
                        )

                # Generator ended (exits after each turn_complete) — reconnect fast
                if not state.running:
                    return
                if not await state.gemini_session.reconnect():
                    logger.error("Failed to reconnect to Gemini")
                    await ws.send_json(
                        server_message(
                            "error",
                            {"code": "GEMINI_DISCONNECTED", "message": "Lost connection to AI"},
                        )
                    )
                    return

                # Inject conversation context so the model keeps continuity
                if state.transcript_buffer:
                    recent = state.transcript_buffer[-20:]
                    context_lines = []
                    for entry in recent:
                        role = "用户" if entry["role"] == "user" else "你"
                        text = entry.get("text", "")[:150]
                        context_lines.append(f"{role}: {text}")
                    context = "\n".join(context_lines)
                    await state.gemini_session.inject_context(
                        f"之前的对话记录:\n{context}\n\n继续自然地聊天，等用户说话。"
                    )

                # Feature 1: Emotional burst — send follow-up when arousal is high
                emo = state.current_emotion
                now = time.time()
                if (
                    emo.arousal >= BURST_AROUSAL_THRESHOLD
                    and state.burst_count < BURST_MAX_FOLLOW_UPS
                    and now >= state.burst_cooldown_until
                ):
                    prompt = BURST_FOLLOW_UP_PROMPTS[
                        state.burst_count % len(BURST_FOLLOW_UP_PROMPTS)
                    ]
                    state.burst_count += 1
                    logger.info(
                        "Burst follow-up #%d (arousal=%.2f, emotion=%s)",
                        state.burst_count, emo.arousal, emo.label,
                    )
                    await asyncio.sleep(0.8)
                    if state.running:
                        await state.gemini_session.send_text(prompt)
                else:
                    if state.burst_count > 0:
                        state.burst_cooldown_until = now + BURST_COOLDOWN_SECONDS
                        state.burst_count = 0

            except asyncio.CancelledError:
                return
            except Exception as e:
                logger.exception("Error in gemini->client loop: %s", e)
                if not state.running:
                    return
                await asyncio.sleep(1)
                if not await state.gemini_session.reconnect():
                    return
    except asyncio.CancelledError:
        pass


async def _idle_topic_prompter(state: SessionState, settings):
    """
    Monitor for conversation lulls and prompt AI to bring up topics.

    Triggers after 30 seconds of inactivity to keep conversation flowing.
    """
    IDLE_THRESHOLD_SECONDS = 30.0
    CHECK_INTERVAL_SECONDS = 10.0

    try:
        while state.running:
            await asyncio.sleep(CHECK_INTERVAL_SECONDS)

            if not state.running or not state.gemini_session:
                return

            idle_duration = time.time() - state.last_activity_time

            if idle_duration >= IDLE_THRESHOLD_SECONDS:
                # Generate a proactive topic prompt
                ai_loc = state.ai_location or "东京"
                topic_prompts = [
                    "聊天有点安静了，自然地聊起一个有趣的话题，比如最近的新闻或者问问用户今天怎么样。",
                    "分享一些你觉得有趣的事情，或者问用户一个轻松的问题。",
                    f"聊聊{ai_loc}最近发生的有趣事情，或者问问用户那边怎么样。",
                ]

                # Pick based on what context we have
                if state.news_context:
                    prompt = topic_prompts[0]
                else:
                    prompt = topic_prompts[1]

                try:
                    await state.gemini_session.send_text(prompt)
                    state.last_activity_time = time.time()
                    logger.info("Sent idle topic prompt after %.1fs", idle_duration)
                except Exception as e:
                    logger.warning("Failed to send idle prompt: %s", e)

    except asyncio.CancelledError:
        pass
    except Exception as e:
        logger.exception("Idle prompter error: %s", e)
