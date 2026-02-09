import asyncio
import logging

from google import genai
from google.genai import types

logger = logging.getLogger(__name__)


class GeminiLiveSession:
    """Manages a single Gemini Live API session for one user."""

    def __init__(
        self,
        api_key: str,
        model: str,
        system_prompt: str,
        tools: list | None = None,
    ):
        self._client = genai.Client(api_key=api_key)
        self._model = model
        self._system_prompt = system_prompt
        self._tools = tools
        self._session = None
        self._context_manager = None
        self._running = False
        self._session_handle: str | None = None

    @property
    def is_running(self) -> bool:
        return self._running

    async def connect(self) -> None:
        """Open the Gemini Live WebSocket session."""
        config = types.LiveConnectConfig(
            response_modalities=["AUDIO"],
            system_instruction=types.Content(
                parts=[types.Part(text=self._system_prompt)]
            ),
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name="Kore",
                    )
                )
            ),
            input_audio_transcription=types.AudioTranscriptionConfig(),
            output_audio_transcription=types.AudioTranscriptionConfig(),
            realtime_input_config=types.RealtimeInputConfig(
                activity_handling=types.ActivityHandling.START_OF_ACTIVITY_INTERRUPTS,
                automatic_activity_detection=types.AutomaticActivityDetection(
                    disabled=False,
                    start_of_speech_sensitivity=types.StartSensitivity.START_SENSITIVITY_HIGH,
                    end_of_speech_sensitivity=types.EndSensitivity.END_SENSITIVITY_LOW,
                    prefix_padding_ms=200,
                    silence_duration_ms=800,
                ),
            ),
            # Sliding window compression enables unlimited session duration
            context_window_compression=types.ContextWindowCompressionConfig(
                sliding_window=types.SlidingWindow(),
            ),
            # Session resumption preserves context across reconnects
            session_resumption=types.SessionResumptionConfig(
                handle=self._session_handle,
            ),
            # Function calling tools (memory recall, web search)
            tools=self._tools,
        )

        self._context_manager = self._client.aio.live.connect(
            model=self._model,
            config=config,
        )
        self._session = await self._context_manager.__aenter__()
        self._running = True
        logger.info(
            "Gemini Live session connected (resumption=%s)",
            self._session_handle is not None,
        )

    async def send_audio(self, audio_bytes: bytes) -> None:
        """Forward raw PCM audio from client to Gemini."""
        if self._session and self._running:
            await self._session.send_realtime_input(
                audio=types.Blob(data=audio_bytes, mime_type="audio/pcm;rate=16000")
            )

    async def send_video_frame(self, frame_bytes: bytes, mime_type: str = "image/jpeg") -> None:
        """Send a single video frame (JPEG) to Gemini."""
        if self._session and self._running:
            await self._session.send_realtime_input(
                video=types.Blob(data=frame_bytes, mime_type=mime_type)
            )

    async def send_text(self, text: str) -> None:
        """Send a text message to Gemini as user input."""
        if self._session and self._running:
            await self._session.send_client_content(
                turns=[
                    types.Content(
                        role="user", parts=[types.Part(text=text)]
                    )
                ],
                turn_complete=True,
            )

    async def inject_context(self, system_text: str) -> None:
        """Inject a hidden system-level context update mid-session."""
        if self._session and self._running:
            await self._session.send_client_content(
                turns=[
                    types.Content(
                        role="user",
                        parts=[types.Part(text=f"[SYSTEM UPDATE]: {system_text}")],
                    )
                ],
                turn_complete=False,
            )

    async def send_tool_response(self, function_responses: list) -> None:
        """Send tool/function call results back to Gemini."""
        if self._session and self._running:
            await self._session.send_tool_response(
                function_responses=function_responses
            )

    async def receive_responses(self):
        """Async generator yielding responses from Gemini Live.

        Internally captures session resumption handles so reconnects
        can restore full conversation context.
        """
        if not self._session:
            return
        async for response in self._session.receive():
            # Store session resumption handles for resilient reconnects
            resumption = getattr(response, "session_resumption_update", None)
            if resumption:
                new_handle = getattr(resumption, "new_handle", None)
                if new_handle:
                    self._session_handle = new_handle
                    logger.debug("Updated session resumption handle")

            yield response

    async def close(self) -> None:
        """Tear down the Gemini session."""
        self._running = False
        if self._context_manager:
            try:
                await self._context_manager.__aexit__(None, None, None)
            except Exception as e:
                logger.warning("Error closing Gemini session: %s", e)
            self._context_manager = None
            self._session = None
        logger.info("Gemini Live session closed")

    async def reconnect(self, max_retries: int = 3) -> bool:
        """Reconnect as fast as possible to minimize audio gap."""
        for attempt in range(1, max_retries + 1):
            try:
                await self.close()
                if attempt > 1:
                    await asyncio.sleep(0.5 * attempt)
                await self.connect()
                logger.info("Reconnected on attempt %d", attempt)
                return True
            except Exception as e:
                logger.warning("Reconnect attempt %d failed: %s", attempt, e)
        return False
