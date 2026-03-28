"""Russell's Circumplex Emotion Model.

Maps emotions to a 2D valence-arousal space with emotional inertia
and MBTI personality modifiers.
"""

from __future__ import annotations

import math
from dataclasses import dataclass


@dataclass
class EmotionState:
    """A point in Russell's circumplex model."""

    valence: float  # -1.0 (negative) to +1.0 (positive)
    arousal: float  # 0.0 (calm) to 1.0 (intense)
    label: str  # e.g. "happy", "angry"
    intensity: str  # "low", "mid", "high"


# Canonical circumplex coordinates for each emotion label.
EMOTION_MAP: dict[str, tuple[float, float]] = {
    "excited": (0.8, 0.9),
    "happy": (0.7, 0.5),
    "loving": (0.8, 0.4),
    "neutral": (0.0, 0.2),
    "thinking": (0.1, 0.4),
    "surprised": (0.3, 0.85),
    "jealous": (-0.5, 0.75),
    "shy": (0.3, 0.35),
    "anxious": (-0.4, 0.8),
    "sad": (-0.7, 0.2),
    "angry": (-0.8, 0.9),
    "disappointed": (-0.6, 0.35),
    "frustrated": (-0.5, 0.65),
    "proud": (0.7, 0.65),
    "grateful": (0.65, 0.25),
    "bored": (-0.3, 0.1),
    "curious": (0.3, 0.55),
    "embarrassed": (-0.3, 0.55),
    "playful": (0.55, 0.75),
    "lonely": (-0.55, 0.15),
    "confused": (-0.15, 0.45),
}

# Default inertia blending weights (overridden by familiarity scaling)
_INERTIA_PREV = 0.5
_INERTIA_NEW = 0.5


def _clamp(value: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, value))


def _intensity_from_arousal(arousal: float) -> str:
    if arousal < 0.35:
        return "low"
    if arousal <= 0.65:
        return "mid"
    return "high"


def _nearest_label(valence: float, arousal: float) -> str:
    """Find the emotion label closest to (valence, arousal) in Euclidean space."""
    best_label = "neutral"
    best_dist = float("inf")
    for label, (v, a) in EMOTION_MAP.items():
        dist = math.hypot(valence - v, arousal - a)
        if dist < best_dist:
            best_dist = dist
            best_label = label
    return best_label


def _apply_mbti_modifiers(
    valence: float, arousal: float, mbti: str | None
) -> tuple[float, float]:
    """Apply MBTI-based personality modifiers to raw valence/arousal."""
    if not mbti or len(mbti) < 4:
        return valence, arousal

    mbti_upper = mbti.upper()

    # E/I affects arousal (extroverts are more expressive)
    if mbti_upper[0] == "E":
        arousal *= 1.15
    elif mbti_upper[0] == "I":
        arousal *= 0.85

    # T/F affects valence volatility (feelers have stronger valence swings)
    if mbti_upper[2] == "F":
        valence *= 1.20
    elif mbti_upper[2] == "T":
        valence *= 0.80

    valence = _clamp(valence, -1.0, 1.0)
    arousal = _clamp(arousal, 0.0, 1.0)

    return valence, arousal


def label_to_circumplex(
    label: str,
    mbti: str | None = None,
) -> EmotionState:
    """Convert a keyword-classified emotion label into a circumplex EmotionState.

    This is the bridge between the fast keyword heuristic (which returns a label
    string) and the full circumplex model.
    """
    valence, arousal = EMOTION_MAP.get(label, EMOTION_MAP["neutral"])
    valence, arousal = _apply_mbti_modifiers(valence, arousal, mbti)
    final_label = _nearest_label(valence, arousal)
    intensity = _intensity_from_arousal(arousal)
    return EmotionState(
        valence=round(valence, 3),
        arousal=round(arousal, 3),
        label=final_label,
        intensity=intensity,
    )


def _inertia_weights(prev: EmotionState, familiarity_level: int) -> tuple[float, float]:
    """Compute inertia blending weights based on context.

    - Escaping neutral is easier (30/70 prev/new)
    - Higher familiarity = more responsive emotions
    """
    # Fast escape from neutral
    if prev.label == "neutral":
        return 0.3, 0.7

    # Familiarity-scaled inertia
    if familiarity_level >= 8:
        return 0.35, 0.65  # very responsive
    elif familiarity_level >= 5:
        return 0.50, 0.50  # balanced
    else:
        return 0.65, 0.35  # slow to change


def apply_inertia(
    prev: EmotionState,
    new: EmotionState,
    familiarity_level: int = 5,
) -> EmotionState:
    """Blend *new* toward *prev* for smooth emotional transitions.

    Familiarity scales responsiveness: close relationships change faster.
    """
    w_prev, w_new = _inertia_weights(prev, familiarity_level)
    valence = _clamp(prev.valence * w_prev + new.valence * w_new, -1.0, 1.0)
    arousal = _clamp(prev.arousal * w_prev + new.arousal * w_new, 0.0, 1.0)
    label = _nearest_label(valence, arousal)
    intensity = _intensity_from_arousal(arousal)
    return EmotionState(
        valence=round(valence, 3),
        arousal=round(arousal, 3),
        label=label,
        intensity=intensity,
    )


def emotion_to_image_key(state: EmotionState) -> str:
    """Convert an EmotionState to the filename key used for pre-cached images.

    Format: ``"{label}_{intensity}"``  e.g. ``"happy_mid"``, ``"angry_high"``.
    """
    return f"{state.label}_{state.intensity}"


# All possible image keys (21 emotions x 3 intensities = 63)
EMOTION_LABELS = list(EMOTION_MAP.keys())
INTENSITY_LEVELS = ("low", "mid", "high")
ALL_IMAGE_KEYS = [f"{label}_{intensity}" for label in EMOTION_LABELS for intensity in INTENSITY_LEVELS]
