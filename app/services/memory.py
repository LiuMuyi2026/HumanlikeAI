import logging
import uuid
from datetime import datetime, timezone

from pinecone import PineconeAsyncio

from app.services.embeddings import EmbeddingService

logger = logging.getLogger(__name__)


class MemoryService:
    """Handles Pinecone vector operations for RAG-based memory recall."""

    def __init__(
        self,
        api_key: str,
        index_host: str,
        embedding_service: EmbeddingService,
    ):
        self._api_key = api_key
        self._index_host = index_host
        self._embedding_service = embedding_service

    async def store_memory(
        self, user_id: str, text: str, metadata: dict | None = None
    ) -> None:
        """Embed text and store in Pinecone under user's namespace."""
        vector = await self._embedding_service.embed_text(text)
        memory_id = str(uuid.uuid4())

        record_metadata = {
            "text": text,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        if metadata:
            record_metadata.update(metadata)

        async with PineconeAsyncio(api_key=self._api_key) as pc:
            idx = pc.IndexAsyncio(host=self._index_host)
            await idx.upsert(
                namespace=user_id,
                vectors=[
                    {
                        "id": memory_id,
                        "values": vector,
                        "metadata": record_metadata,
                    }
                ],
            )

    async def recall_memories(
        self, user_id: str, query_text: str, top_k: int = 5
    ) -> list[str]:
        """Retrieve most relevant past conversation snippets for context."""
        query_vector = await self._embedding_service.embed_text(query_text)

        async with PineconeAsyncio(api_key=self._api_key) as pc:
            idx = pc.IndexAsyncio(host=self._index_host)
            results = await idx.query(
                namespace=user_id,
                vector=query_vector,
                top_k=top_k,
                include_metadata=True,
            )

        return [
            match.metadata["text"]
            for match in results.matches
            if match.metadata and "text" in match.metadata
        ]

    async def store_batch(
        self, user_id: str, texts: list[str], metadata: dict | None = None
    ) -> None:
        """Embed and store multiple text chunks."""
        if not texts:
            return
        vectors = await self._embedding_service.embed_batch(texts)

        records = []
        for text, vec in zip(texts, vectors):
            record_metadata = {
                "text": text,
                "timestamp": datetime.now(timezone.utc).isoformat(),
            }
            if metadata:
                record_metadata.update(metadata)
            records.append(
                {
                    "id": str(uuid.uuid4()),
                    "values": vec,
                    "metadata": record_metadata,
                }
            )

        async with PineconeAsyncio(api_key=self._api_key) as pc:
            idx = pc.IndexAsyncio(host=self._index_host)
            await idx.upsert(namespace=user_id, vectors=records)
