from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # Server
    host: str = "0.0.0.0"
    port: int = 8000

    # Google / Gemini
    gemini_api_key: str = ""
    gemini_live_model: str = "models/gemini-2.5-flash-native-audio-preview-12-2025"
    gemini_embedding_model: str = "models/text-embedding-004"

    # PostgreSQL
    database_url: str = "postgresql+asyncpg://user:password@localhost:5432/hlai"

    # Pinecone
    pinecone_api_key: str = ""
    pinecone_index_host: str = ""

    # Image generation
    gemini_image_model: str = "models/gemini-2.5-flash-image"
    image_storage_dir: str = "storage/character_images"

    # App
    embedding_dimension: int = 768
    memory_top_k: int = 5

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


@lru_cache
def get_settings() -> Settings:
    return Settings()
