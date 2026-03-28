import asyncio
import json
import logging

from google import genai
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.db.repositories.character_repo import CharacterRepository
from app.db.repositories.user_repo import UserRepository
from app.services.embeddings import EmbeddingService
from app.services.memory import MemoryService

logger = logging.getLogger(__name__)

# Feature 4: Valid relationship types (must match RELATIONSHIP_EMOTION_BIAS keys)
VALID_RELATIONSHIP_TYPES = [
    "Romantic Partner", "Ex-Partner", "Best Friend", "Friend", "Mentor",
    "Companion", "Confidant", "Rival", "Frenemy", "Nemesis", "Critic",
    "Stranger", "Acquaintance", "Colleague", "Study Buddy", "Advisor",
]


def _chunk_transcript(transcript: list[dict], chunk_size: int = 4) -> list[list[dict]]:
    """Split transcript into chunks of N exchanges for embedding."""
    chunks = []
    for i in range(0, len(transcript), chunk_size):
        chunk = transcript[i : i + chunk_size]
        if chunk:
            chunks.append(chunk)
    return chunks


def _transcript_to_text(transcript: list[dict]) -> str:
    """Convert transcript entries to readable text."""
    return "\n".join(
        f"{'User' if t['role'] == 'user' else 'AI'}: {t['text']}" for t in transcript
    )


async def process_conversation_memory(
    user_id: str,
    session_id: str,
    transcript: list[dict],
    gemini_api_key: str,
    pinecone_api_key: str,
    pinecone_index_host: str,
    database_url: str,
    character_id: str | None = None,
    embedding_model: str = "models/text-embedding-004",
    embedding_dimension: int = 768,
) -> None:
    """
    Background task: process a conversation for memory extraction.

    1. Extract user facts/intents using Gemini
    2. Update user profile in PostgreSQL
    3. Generate embeddings and store in Pinecone
    """
    try:
        logger.info(
            "Processing memory for user=%s session=%s (%d entries)",
            user_id,
            session_id,
            len(transcript),
        )

        client = genai.Client(api_key=gemini_api_key)
        full_text = _transcript_to_text(transcript)

        # Step 1: Extract facts using Gemini
        extraction_prompt = (
            "Analyze this conversation and extract:\n"
            "1. New facts about the user (name, job, hobbies, relationships, etc.)\n"
            "2. Key topics discussed\n"
            "3. Any changes in the user's life situation\n\n"
            "Return ONLY valid JSON (no markdown, no code blocks):\n"
            '{"user_facts": {"key": "value"}, "topics": ["topic1"]}\n\n'
            "If no new facts are found, return: {\"user_facts\": {}, \"topics\": []}\n\n"
            f"Conversation:\n{full_text}"
        )

        extraction_response = await asyncio.to_thread(
            client.models.generate_content,
            model="models/gemini-2.0-flash-lite",
            contents=extraction_prompt,
        )

        extracted = _parse_json_response(extraction_response.text)

        # Step 2: Update user profile in PostgreSQL
        if extracted.get("user_facts"):
            engine = create_async_engine(database_url)
            session_factory = async_sessionmaker(
                engine, class_=AsyncSession, expire_on_commit=False
            )
            async with session_factory() as session:
                repo = UserRepository(session)
                await repo.merge_extracted_facts(user_id, extracted["user_facts"])
            await engine.dispose()
            logger.info("Updated user facts: %s", list(extracted["user_facts"].keys()))

        # Step 3: Chunk transcript and store embeddings in Pinecone
        embedding_svc = EmbeddingService(
            api_key=gemini_api_key,
            model=embedding_model,
            output_dimensionality=embedding_dimension,
        )
        memory_svc = MemoryService(
            api_key=pinecone_api_key,
            index_host=pinecone_index_host,
            embedding_service=embedding_svc,
        )

        chunks = _chunk_transcript(transcript, chunk_size=4)
        chunk_texts = [_transcript_to_text(chunk) for chunk in chunks]

        metadata = {
            "session_id": session_id,
            "topics": json.dumps(extracted.get("topics", [])),
        }
        # Use character-scoped namespace if character_id is provided
        namespace = f"{user_id}:{character_id}" if character_id else user_id
        await memory_svc.store_batch(namespace, chunk_texts, metadata)

        logger.info(
            "Stored %d memory chunks for user=%s", len(chunk_texts), user_id
        )

        # Feature 4: Adjust relationship based on conversation
        if character_id:
            await adjust_relationship(
                user_id, character_id, transcript,
                gemini_api_key, database_url,
            )

    except Exception as e:
        logger.exception("Memory processing failed for user=%s: %s", user_id, e)


def _parse_json_response(text: str) -> dict:
    """Parse JSON from Gemini response, handling markdown code blocks."""
    text = text.strip()

    # Strip markdown code block wrappers if present
    if text.startswith("```"):
        lines = text.split("\n")
        # Remove first line (```json or ```) and last line (```)
        lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        text = "\n".join(lines)

    try:
        return json.loads(text)
    except json.JSONDecodeError:
        logger.warning("Failed to parse JSON from Gemini: %s", text[:200])
        return {"user_facts": {}, "topics": []}


async def store_news_as_memory(
    user_id: str,
    news_items: list[dict],
    gemini_api_key: str,
    pinecone_api_key: str,
    pinecone_index_host: str,
    embedding_model: str = "models/text-embedding-004",
    embedding_dimension: int = 768,
    character_id: str | None = None,
) -> None:
    """
    Store news items as conversation memory for the user.

    This allows the AI to recall news it discussed with the user.
    """
    try:
        if not news_items:
            return

        embedding_svc = EmbeddingService(
            api_key=gemini_api_key,
            model=embedding_model,
            output_dimensionality=embedding_dimension,
        )
        memory_svc = MemoryService(
            api_key=pinecone_api_key,
            index_host=pinecone_index_host,
            embedding_service=embedding_svc,
        )

        # Create text summaries for each news item
        news_texts = []
        for item in news_items:
            location = item.get("location", "")
            title = item.get("title", "")
            summary = item.get("summary", "")
            text = f"[News from {location}] {title}: {summary}"
            news_texts.append(text)

        metadata = {
            "type": "news",
            "locations": json.dumps([n.get("location", "") for n in news_items]),
        }
        namespace = f"{user_id}:{character_id}" if character_id else user_id
        await memory_svc.store_batch(namespace, news_texts, metadata)

        logger.info("Stored %d news items as memory for user=%s", len(news_texts), user_id)

    except Exception as e:
        logger.exception("Failed to store news as memory for user=%s: %s", user_id, e)


async def adjust_relationship(
    user_id: str,
    character_id: str,
    transcript: list[dict],
    gemini_api_key: str,
    database_url: str,
) -> None:
    """
    Feature 4: Analyze conversation and adjust relationship_type / familiarity_level.

    If the provided transcript is short (text chat sends 2 entries at a time),
    loads the full recent chat history from the database instead.
    Familiarity changes by at most +-1 per session.
    """
    try:
        # Load current character and possibly full history from DB
        engine = create_async_engine(database_url)
        session_factory = async_sessionmaker(
            engine, class_=AsyncSession, expire_on_commit=False
        )
        async with session_factory() as session:
            repo = CharacterRepository(session)
            character = await repo.get_by_id(character_id)
            if not character:
                logger.warning("Character %s not found for relationship adjustment", character_id)
                await engine.dispose()
                return

            current_type = character.relationship_type or "Friend"
            current_familiarity = character.familiarity_level or 5

            # If transcript is too short, load recent messages from DB
            analysis_transcript = transcript
            if len(transcript) < 5:
                from app.db.repositories.message_repo import MessageRepository
                msg_repo = MessageRepository(session)
                db_messages = await msg_repo.list_messages(
                    character_id, user_id, limit=30,
                )
                if db_messages:
                    analysis_transcript = [
                        {
                            "role": "user" if m.role == "user" else "model",
                            "text": m.content or "",
                        }
                        for m in db_messages
                        if m.content
                    ]
                    logger.info(
                        "Loaded %d messages from DB for relationship analysis",
                        len(analysis_transcript),
                    )

            if len(analysis_transcript) < 3:
                logger.info("Skipping relationship adjustment: not enough messages (%d)", len(analysis_transcript))
                await engine.dispose()
                return

            # Use last 30 messages for analysis
            recent = analysis_transcript[-30:]
            convo_text = "\n".join(
                f"{'User' if t['role'] == 'user' else 'AI'}: {t.get('text', '')}"
                for t in recent
            )

            valid_types_desc = (
                "Romantic Partner (恋人/情侣), "
                "Ex-Partner (前任/分手后), "
                "Best Friend (闺蜜/铁哥们), "
                "Friend (普通朋友), "
                "Mentor (导师), "
                "Companion (伙伴), "
                "Confidant (知己), "
                "Rival (对手), "
                "Frenemy (亦敌亦友), "
                "Nemesis (死对头), "
                "Critic (批评者), "
                "Stranger (陌生人), "
                "Acquaintance (熟人), "
                "Colleague (同事), "
                "Study Buddy (学习伙伴), "
                "Advisor (顾问)"
            )
            analysis_prompt = (
                "Analyze this conversation between a user and their AI character, "
                "and determine if the relationship has changed.\n\n"
                f"Current relationship type: {current_type}\n"
                f"Current familiarity level: {current_familiarity}/10\n\n"
                f"Valid relationship types with descriptions:\n{valid_types_desc}\n\n"
                "Guidelines:\n"
                "- familiarity_level can change by at most +1 or -1\n"
                "- Change the relationship type when the conversation shows a clear shift. Examples:\n"
                "  - User says breakup/分手/不爱了 → change Romantic Partner to Ex-Partner\n"
                "  - User confesses love/表白 → may upgrade to Romantic Partner\n"
                "  - Conversation turns hostile → may change to Rival or Nemesis\n"
                "  - Conversation shows growing closeness → may upgrade from Friend to Best Friend\n"
                "- Look for explicit relationship-changing statements from the user\n"
                "- If no clear signal of change, keep the current values and set changed to false\n\n"
                "Return ONLY valid JSON (no markdown, no code blocks):\n"
                '{"relationship_type": "...", "familiarity_level": N, "changed": true/false, "reason": "brief explanation"}\n\n'
                f"Conversation:\n{convo_text}"
            )

            client = genai.Client(api_key=gemini_api_key)
            response = await asyncio.to_thread(
                client.models.generate_content,
                model="models/gemini-2.0-flash-lite",
                contents=analysis_prompt,
            )

            result = _parse_json_response(response.text)
            logger.info("Relationship analysis result for character=%s: %s", character_id, result)

            if not result.get("changed", False):
                logger.info("No relationship change for character=%s", character_id)
                await engine.dispose()
                return

            # Validate and clamp
            new_type = result.get("relationship_type", current_type)
            if new_type not in VALID_RELATIONSHIP_TYPES:
                new_type = current_type

            new_familiarity = result.get("familiarity_level", current_familiarity)
            if not isinstance(new_familiarity, (int, float)):
                new_familiarity = current_familiarity
            new_familiarity = int(new_familiarity)

            # Clamp delta to +-1
            delta = new_familiarity - current_familiarity
            if delta > 1:
                new_familiarity = current_familiarity + 1
            elif delta < -1:
                new_familiarity = current_familiarity - 1
            new_familiarity = max(1, min(10, new_familiarity))

            # Update DB
            update_fields = {}
            if new_type != current_type:
                update_fields["relationship_type"] = new_type
            if new_familiarity != current_familiarity:
                update_fields["familiarity_level"] = new_familiarity

            if update_fields:
                await repo.update(character_id, **update_fields)
                reason = result.get("reason", "")
                logger.info(
                    "Relationship adjusted for character=%s: %s -> %s, familiarity %d -> %d (reason: %s)",
                    character_id, current_type, new_type,
                    current_familiarity, new_familiarity, reason,
                )

        await engine.dispose()

    except Exception as e:
        logger.exception(
            "Relationship adjustment failed for character=%s: %s", character_id, e
        )
