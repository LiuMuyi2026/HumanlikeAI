import asyncio
import logging

from google import genai
from google.genai import types

logger = logging.getLogger(__name__)


class EmbeddingService:
    """Wraps Google's text-embedding model for generating vector embeddings."""

    def __init__(
        self,
        api_key: str,
        model: str = "models/gemini-embedding-001",
        output_dimensionality: int = 768,
    ):
        self._client = genai.Client(api_key=api_key)
        self._model = model
        self._config = types.EmbedContentConfig(
            output_dimensionality=output_dimensionality,
        )

    async def embed_text(self, text: str) -> list[float]:
        """Generate an embedding vector for a single text string."""
        result = await asyncio.to_thread(
            self._client.models.embed_content,
            model=self._model,
            contents=text,
            config=self._config,
        )
        return result.embeddings[0].values

    async def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Generate embeddings for multiple texts in a single call."""
        result = await asyncio.to_thread(
            self._client.models.embed_content,
            model=self._model,
            contents=texts,
            config=self._config,
        )
        return [e.values for e in result.embeddings]
