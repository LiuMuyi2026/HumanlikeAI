import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.db.session import engine

logger = logging.getLogger(__name__)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    logger.info("Starting HLAI backend on %s:%s", settings.host, settings.port)
    # Verify database connection
    async with engine.begin() as conn:
        logger.info("Database connection verified")
    yield
    # Shutdown
    await engine.dispose()
    logger.info("Shutdown complete")


app = FastAPI(
    title="HLAI Human Like AI",
    version="0.1.0",
    lifespan=lifespan,
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
async def health_check():
    return {"status": "ok"}


# Import and register routes after app is created
from app.api.ws_handler import router as ws_router  # noqa: E402
from app.api.user_routes import router as user_router  # noqa: E402
from app.api.character_routes import router as character_router  # noqa: E402
from app.api.message_routes import router as message_router  # noqa: E402

app.include_router(ws_router)
app.include_router(user_router, prefix="/api/users")
app.include_router(character_router, prefix="/api/characters")
app.include_router(message_router, prefix="/api/characters")
