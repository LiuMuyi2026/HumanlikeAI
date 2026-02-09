import asyncio
import logging
from typing import Literal

from google import genai

from app.services.emotion_model import EmotionState, apply_inertia, label_to_circumplex

logger = logging.getLogger(__name__)

EmotionLabel = Literal[
    "happy", "sad", "angry", "neutral", "thinking",
    "excited", "surprised", "loving", "anxious",
    "jealous", "shy",
    "disappointed", "frustrated", "proud", "grateful",
    "bored", "curious", "embarrassed", "playful",
    "lonely", "confused",
]
VALID_EMOTIONS: set[str] = {
    "happy", "sad", "angry", "neutral", "thinking",
    "excited", "surprised", "loving", "anxious",
    "jealous", "shy",
    "disappointed", "frustrated", "proud", "grateful",
    "bored", "curious", "embarrassed", "playful",
    "lonely", "confused",
}

# Tier 1: Fast keyword-based heuristic (zero latency, no API call)
EMOTION_KEYWORDS: dict[str, list[str]] = {
    "happy": [
        "haha", "wonderful", "great", "glad", "awesome",
        "amazing", "yay", "fantastic", "brilliant", "delighted", "fun",
        "joy", "happy", "laugh", "smile", "cool", "sweet", "nice",
        "开心", "高兴", "哈哈", "不错", "棒", "太好了", "好开心",
    ],
    "excited": [
        "excited", "wow", "incredible", "omg", "can't wait", "thrilled",
        "pumped", "stoked", "unbelievable", "insane", "let's go",
        "太棒了", "激动", "兴奋", "天啊", "厉害", "震惊",
    ],
    "sad": [
        "sorry", "unfortunately", "sad", "miss", "lost", "difficult",
        "tough", "heartbreaking", "regret", "painful",
        "grief", "cry", "tears",
        "难过", "伤心", "可惜", "遗憾", "想念", "心疼", "委屈",
    ],
    "angry": [
        "unfair", "annoyed", "upset", "furious", "angry",
        "outrageous", "ridiculous", "unacceptable", "terrible", "hate",
        "生气", "烦", "讨厌", "气死", "受不了", "过分",
    ],
    "anxious": [
        "worried", "nervous", "anxious", "scared", "afraid", "stress",
        "uneasy", "concerned", "panic", "overwhelmed", "tense",
        "担心", "紧张", "焦虑", "害怕", "不安", "压力",
    ],
    "loving": [
        "love", "adore", "cherish", "care about", "precious",
        "sweetheart", "darling", "dear", "miss you", "warm",
        "affection", "tender", "hug",
        "喜欢你", "爱你", "想你", "在乎你", "心疼你", "亲爱的", "宝贝",
    ],
    "surprised": [
        "really", "no way", "what", "seriously", "unexpected",
        "didn't expect", "oh my", "shocking", "whoa",
        "真的吗", "不会吧", "没想到", "居然", "竟然", "吓到",
    ],
    "thinking": [
        "hmm", "let me think", "consider", "interesting",
        "perhaps", "maybe", "could be", "wonder",
        "actually", "on the other hand",
        "嗯", "这个嘛", "让我想想", "有意思", "也许", "好像",
    ],
    "jealous": [
        "jealous", "girlfriend", "boyfriend", "dating someone",
        "seeing someone", "other girl", "other guy", "who is she",
        "who is he", "don't like her", "don't like him", "mine",
        "belong to me", "flirting", "cheating", "why her", "why him",
        "吃醋", "女朋友", "男朋友", "其他女生", "其他男生",
        "她是谁", "他是谁", "你是我的", "不许", "别跟她",
        "别跟他", "醋意", "嫉妒",
    ],
    "shy": [
        "blush", "shy", "awkward", "flattered",
        "stop it", "don't say that", "you're making me",
        "too much", "oh stop", "you're sweet",
        "害羞", "不好意思", "脸红", "别说了", "讨厌啦",
        "人家", "哎呀", "羞死了", "你真会说",
    ],
    "disappointed": [
        "disappointed", "let down", "expected more", "not what i hoped",
        "underwhelming", "letdown", "hoped for",
        "失望", "不满意", "不如预期",
    ],
    "frustrated": [
        "frustrating", "frustrated", "ugh", "so annoying", "stuck",
        "can't figure out", "nothing works", "give up",
        "烦死了", "搞不定", "好烦",
    ],
    "proud": [
        "proud", "nailed it", "crushed it", "achievement", "accomplished",
        "did it", "i'm so good", "look what i did",
        "骄傲", "自豪", "厉害了",
    ],
    "grateful": [
        "grateful", "thankful", "appreciate", "thanks so much",
        "means a lot", "blessed", "so kind",
        "感恩", "感谢", "谢谢你", "太感谢",
    ],
    "bored": [
        "bored", "boring", "dull", "nothing to do", "meh",
        "whatever", "yawn", "so tired of",
        "无聊", "没意思", "好闷",
    ],
    "curious": [
        "curious", "tell me more", "how does", "why does",
        "i wonder", "what if", "fascinating",
        "好奇", "想知道", "怎么回事",
    ],
    "embarrassed": [
        "embarrassed", "embarrassing", "cringe", "so awkward",
        "want to disappear", "mortified", "humiliating",
        "尴尬", "丢人", "好丢脸",
    ],
    "playful": [
        "hehe", "tease", "playful", "just kidding", "gotcha",
        "bet you can't", "catch me", "wanna play",
        "嘻嘻", "逗你的", "来玩",
    ],
    "lonely": [
        "lonely", "alone", "no one", "nobody", "by myself",
        "miss someone", "isolated", "all alone",
        "孤独", "寂寞", "一个人",
    ],
    "confused": [
        "confused", "don't understand", "makes no sense", "huh",
        "lost me", "wait what", "i'm so confused",
        "困惑", "搞不懂", "什么意思",
    ],
}

# Relationship-based emotion biases: when no strong keyword match,
# the relationship type makes certain emotions more likely than plain "neutral"
RELATIONSHIP_EMOTION_BIAS: dict[str, str] = {
    "Romantic Partner": "loving",
    "Ex-Partner": "sad",
    "Best Friend": "happy",
    "Friend": "happy",
    "Mentor": "thinking",
    "Companion": "happy",
    "Confidant": "thinking",
    "Rival": "excited",
    "Frenemy": "surprised",
    "Nemesis": "angry",
    "Critic": "thinking",
    "Stranger": "neutral",
    "Acquaintance": "neutral",
    "Colleague": "neutral",
    "Study Buddy": "thinking",
    "Advisor": "thinking",
}


def classify_emotion_heuristic(
    text: str,
    relationship_type: str | None = None,
    familiarity_level: int = 5,
) -> str:
    """
    Fast keyword-based emotion classification with relationship context.

    Returns one of: happy, sad, angry, neutral, thinking, excited, surprised, loving, anxious.
    """
    text_lower = text.lower()
    scores: dict[str, float] = {emotion: 0.0 for emotion in EMOTION_KEYWORDS}

    for emotion, keywords in EMOTION_KEYWORDS.items():
        for kw in keywords:
            if kw in text_lower:
                scores[emotion] += 1

    best = max(scores, key=scores.get)

    if scores[best] > 0:
        return best

    # No strong keyword match — use relationship bias instead of always "neutral"
    if relationship_type and relationship_type in RELATIONSHIP_EMOTION_BIAS:
        bias = RELATIONSHIP_EMOTION_BIAS[relationship_type]
        # Higher familiarity = stronger bias away from neutral
        if familiarity_level >= 7:
            return bias
        elif familiarity_level >= 4:
            # 50/50 bias vs neutral — use text length as tiebreaker
            # Longer responses tend to be more engaged
            return bias if len(text) > 20 else "neutral"

    return "neutral"


# Tier 2: Gemini-based classification (higher accuracy, costs an API call)
async def classify_emotion_gemini(
    text: str,
    client: genai.Client,
    model: str = "models/gemini-2.0-flash-lite",
    relationship_type: str | None = None,
    familiarity_level: int = 5,
) -> str:
    """
    Use Gemini to classify emotion from AI response text.

    Only use this for important transitions or when heuristic confidence is low.
    """
    relationship_context = ""
    if relationship_type:
        relationship_context = (
            f"\nContext: The AI's relationship with the user is '{relationship_type}' "
            f"with familiarity level {familiarity_level}/10."
        )

    try:
        response = await asyncio.to_thread(
            client.models.generate_content,
            model=model,
            contents=(
                "Classify the emotion of this AI response into exactly one of: "
                "happy, sad, angry, neutral, thinking, excited, surprised, loving, anxious, jealous, shy, "
                "disappointed, frustrated, proud, grateful, bored, curious, embarrassed, playful, lonely, confused.\n"
                f"{relationship_context}\n"
                f'Response text: "{text}"\n'
                "Reply with only the single emotion word, nothing else."
            ),
        )
        emotion = response.text.strip().lower()
        return emotion if emotion in VALID_EMOTIONS else "neutral"
    except Exception as e:
        logger.warning("Gemini emotion classification failed: %s", e)
        return classify_emotion_heuristic(text, relationship_type, familiarity_level)


def classify_to_circumplex(
    text: str,
    relationship_type: str | None = None,
    familiarity_level: int = 5,
    mbti: str | None = None,
    prev_state: EmotionState | None = None,
) -> EmotionState:
    """Classify text into a circumplex EmotionState with inertia.

    Uses the fast keyword heuristic, maps the label to valence/arousal,
    applies MBTI modifiers, then blends with the previous state for smooth
    emotional transitions.
    """
    label = classify_emotion_heuristic(text, relationship_type, familiarity_level)
    new_state = label_to_circumplex(label, mbti=mbti)
    if prev_state is not None:
        return apply_inertia(prev_state, new_state)
    return new_state
