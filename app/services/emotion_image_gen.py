"""Generate a full emotion image pack for a character.

Creates one image per emotion_key (e.g. "happy_mid", "angry_high") using
the character's avatar as a reference image for visual consistency.
"""

import logging

from app.db.repositories.character_repo import CharacterRepository
from app.db.session import async_session_factory
from app.services.emotion_model import ALL_IMAGE_KEYS
from app.services.image_gen import generate_image

logger = logging.getLogger(__name__)

# Human-readable prompt fragments per emotion+intensity.
EMOTION_PROMPTS: dict[str, str] = {
    # excited
    "excited_low": "Mildly excited expression, slight spark in the eyes, hint of anticipation",
    "excited_mid": "Excited expression, bright eyes, enthusiastic smile, energetic pose",
    "excited_high": "Extremely excited, beaming with energy, arms raised, radiant joy",
    # happy
    "happy_low": "Gentle smile, relaxed and content expression, soft warmth",
    "happy_mid": "Bright smile, warm and friendly expression, cheerful mood",
    "happy_high": "Beaming with joy, radiant happiness, wide genuine smile, glowing",
    # loving
    "loving_low": "Soft tender expression, gentle warmth in eyes, slight caring smile",
    "loving_mid": "Warm loving expression, affectionate gaze, sweet smile",
    "loving_high": "Deeply loving expression, adoring eyes, heart-melting warmth",
    # neutral
    "neutral_low": "Calm and serene expression, peaceful, completely relaxed",
    "neutral_mid": "Neutral composed expression, balanced mood, attentive",
    "neutral_high": "Alert neutral expression, focused attention, engaged",
    # thinking
    "thinking_low": "Slightly contemplative expression, mild curiosity, relaxed thought",
    "thinking_mid": "Thoughtful expression, hand near chin, pondering, curious",
    "thinking_high": "Deeply focused thinking expression, intense concentration, furrowed brow",
    # surprised
    "surprised_low": "Mildly surprised, slightly raised eyebrows, hint of wonder",
    "surprised_mid": "Surprised expression, raised eyebrows, open mouth, wide eyes",
    "surprised_high": "Extremely surprised, jaw dropped, eyes wide, astonished",
    # anxious
    "anxious_low": "Slightly uneasy expression, subtle tension, mild concern",
    "anxious_mid": "Worried expression, tense, furrowed brow, concerned eyes",
    "anxious_high": "Very anxious expression, visible stress, tense posture, fearful eyes",
    # sad
    "sad_low": "Slightly melancholic expression, subdued mood, gentle sadness",
    "sad_mid": "Sad expression, downcast eyes, frowning slightly, sorrowful",
    "sad_high": "Deeply sad expression, tears forming, heartbroken, grief-stricken",
    # angry
    "angry_low": "Slight frown, mild annoyance, hint of displeasure",
    "angry_mid": "Angry expression, furrowed brow, tight jaw, frustration",
    "angry_high": "Intense anger, fierce expression, glaring eyes, clenched jaw",
    # jealous
    "jealous_low": "Slightly jealous expression, subtle pout, guarded eyes, hint of possessiveness",
    "jealous_mid": "Jealous expression, narrow eyes, pouty lips, arms crossed, displeased",
    "jealous_high": "Intensely jealous, fierce possessive stare, tight lips, hurt and angry",
    # shy
    "shy_low": "Slightly shy expression, gentle blush, looking away subtly, soft smile",
    "shy_mid": "Shy expression, blushing cheeks, looking down, bashful smile, hands near face",
    "shy_high": "Very shy, deep blush, hiding face partially, flustered, adorably embarrassed",
    # disappointed
    "disappointed_low": "Slightly let down expression, mild frown, subdued eyes, hint of sadness",
    "disappointed_mid": "Disappointed expression, downturned mouth, deflated posture, sad eyes",
    "disappointed_high": "Deeply disappointed, crestfallen expression, heavy sigh, eyes cast downward",
    # frustrated
    "frustrated_low": "Mildly frustrated expression, slight tension in jaw, hint of irritation",
    "frustrated_mid": "Frustrated expression, furrowed brow, tight lips, exasperated look",
    "frustrated_high": "Very frustrated, hands on temples, eyes squeezed shut, visible exasperation",
    # proud
    "proud_low": "Subtly proud expression, confident slight smile, chin up slightly",
    "proud_mid": "Proud expression, beaming confident smile, chest out, self-assured posture",
    "proud_high": "Extremely proud, radiant confidence, triumphant smile, glowing with accomplishment",
    # grateful
    "grateful_low": "Gently grateful expression, soft warm smile, appreciative eyes",
    "grateful_mid": "Grateful expression, heartfelt smile, hands together, warm thankful gaze",
    "grateful_high": "Deeply grateful, moved to tears, hands over heart, overwhelming appreciation",
    # bored
    "bored_low": "Slightly bored expression, glazed eyes, minimal engagement, flat affect",
    "bored_mid": "Bored expression, resting chin on hand, half-lidded eyes, disinterested",
    "bored_high": "Extremely bored, head tilted back, eyes rolling, exaggerated disinterest",
    # curious
    "curious_low": "Slightly curious expression, one eyebrow raised, hint of interest",
    "curious_mid": "Curious expression, leaning forward, wide attentive eyes, intrigued smile",
    "curious_high": "Intensely curious, eyes wide with fascination, leaning in eagerly, captivated",
    # embarrassed
    "embarrassed_low": "Slightly embarrassed expression, light blush, avoiding eye contact",
    "embarrassed_mid": "Embarrassed expression, red cheeks, covering mouth, sheepish smile",
    "embarrassed_high": "Deeply embarrassed, face buried in hands, bright red cheeks, cringing",
    # playful
    "playful_low": "Slightly playful expression, mischievous hint in eyes, teasing smile",
    "playful_mid": "Playful expression, winking, tongue out slightly, cheeky grin",
    "playful_high": "Very playful, big mischievous grin, animated pose, infectious energy",
    # lonely
    "lonely_low": "Slightly lonely expression, distant gaze, subtle melancholy, quiet mood",
    "lonely_mid": "Lonely expression, hugging self, sad distant eyes, longing look",
    "lonely_high": "Deeply lonely, curled up posture, hollow eyes, aching solitude, tearful",
    # confused
    "confused_low": "Slightly confused expression, one eyebrow raised, tilted head, uncertain",
    "confused_mid": "Confused expression, furrowed brow, squinting eyes, scratching head",
    "confused_high": "Very confused, bewildered expression, hands up in puzzlement, lost look",
}


async def generate_emotion_pack(
    character_id: str,
    user_id: str,
) -> list[str]:
    """Generate all emotion images for a character.

    Uses the character's avatar as a reference image. If no avatar exists,
    generates from the character config alone.

    Returns a list of emotion_keys that were successfully generated.
    """
    async with async_session_factory() as session:
        repo = CharacterRepository(session)
        character = await repo.get_by_id_and_user(character_id, user_id)
        if character is None:
            raise ValueError("Character not found")

        character_config = {
            "name": character.name,
            "gender": character.gender,
            "region": character.region,
            "occupation": character.occupation,
            "personality_traits": character.personality_traits,
            "mbti": character.mbti,
            "familiarity_level": character.familiarity_level,
        }

        import os
        reference_path = None
        if character.avatar_path and os.path.exists(character.avatar_path):
            reference_path = character.avatar_path

    generated_keys: list[str] = []

    # Video-call style constraints for all emotion images
    _VIDEO_CALL_STYLE = (
        "Front-facing webcam angle, looking directly at camera, "
        "head and shoulders framing like a video call, "
        "same plain soft-lit background, consistent lighting, "
        "high quality, realistic"
    )

    for emotion_key in ALL_IMAGE_KEYS:
        emotion_desc = EMOTION_PROMPTS.get(emotion_key, "neutral expression")
        prompt = (
            f"Same person as reference image. "
            f"Expression: {emotion_desc}. "
            f"Same face and appearance, {_VIDEO_CALL_STYLE}."
        )
        if not reference_path:
            # No reference — build from scratch using character config
            prompt = (
                f"Portrait of a person, {emotion_desc}. "
                f"{_VIDEO_CALL_STYLE}."
            )

        try:
            file_path, prompt_used = await generate_image(
                character_id=character_id,
                prompt=prompt,
                character_config=character_config,
                reference_image_path=reference_path,
            )

            async with async_session_factory() as session:
                repo = CharacterRepository(session)
                # Delete existing image for this key if any
                existing = await repo.get_emotion_image(character_id, emotion_key)
                if existing:
                    await session.delete(existing)
                    await session.commit()
                await repo.add_emotion_image(
                    character_id=character_id,
                    emotion_key=emotion_key,
                    image_path=file_path,
                    prompt_used=prompt_used,
                )

            generated_keys.append(emotion_key)
            logger.info(
                "Generated emotion image: character=%s key=%s",
                character_id,
                emotion_key,
            )
        except Exception as e:
            logger.error(
                "Failed to generate emotion image: character=%s key=%s error=%s",
                character_id,
                emotion_key,
                e,
            )

    return generated_keys
