import asyncio
import logging
from typing import AsyncGenerator

from google import genai
from google.genai import types

from app.config import get_settings

logger = logging.getLogger(__name__)
settings = get_settings()
client = genai.Client(api_key=settings.GEMINI_API_KEY)


class GeminiVoiceBridge:
    """Bridges raw PCM audio over WebSocket to Gemini's Live API."""

    def __init__(
        self,
        system_prompt: str = "You are a helpful assistant.",
        voice_name: str = "Kore",
        conversation_history: list[dict[str, str]] | None = None,
        call_intent_message: str | None = None,
    ):
        self.system_prompt = system_prompt
        self.conversation_history = conversation_history or []
        self.call_intent_message = call_intent_message
        # Normalize user-selected voice to stable presets for this model.
        # Puck can be inconsistent in some sessions; Fenrir is more reliable.
        normalized = (voice_name or "Kore").strip()
        if normalized.lower() in {"male", "puck"}:
            normalized = "Fenrir"
        self.voice_name = normalized
        self.session = None
        self._session_context = None
        self._running = False
        self._last_user_transcript_text = ""
        self._last_bot_transcript_text = ""

    async def start_session(self):
        self._running = True
        logger.info("Using voice: %s", self.voice_name)

        voice_style = (
            "Speak in a warm, natural, conversational tone. "
            "Use casual pacing with natural pauses. "
            "Vary your intonation like a real person would. "
            "Keep responses concise and spoken-word friendly — no bullet points or lists."
        )
        full_prompt = f"{voice_style}\n\n{self.system_prompt}"

        # Include call intent message if provided
        if self.call_intent_message:
            full_prompt += f"\n\nCall Context: {self.call_intent_message}"

        # Include conversation history context if available
        if self.conversation_history:
            history_summary = "\n\nPrevious Conversation:\n"
            for msg in self.conversation_history[-10:]:  # Last 10 messages for context
                role = "User" if msg["role"] == "user" else "You"
                history_summary += f"{role}: {msg['content']}\n"
            full_prompt += history_summary

        config = types.LiveConnectConfig(
            response_modalities=["AUDIO"],
            input_audio_transcription=types.AudioTranscriptionConfig(),
            output_audio_transcription=types.AudioTranscriptionConfig(),
            speech_config=types.SpeechConfig(
                voice_config=types.VoiceConfig(
                    prebuilt_voice_config=types.PrebuiltVoiceConfig(
                        voice_name=self.voice_name,
                    ),
                ),
            ),
            system_instruction=types.Content(
                parts=[types.Part(text=full_prompt)]
            ),
        )
        self._session_context = client.aio.live.connect(
            model="gemini-2.5-flash-native-audio-latest",
            config=config,
        )
        self.session = await self._session_context.__aenter__()
        logger.info("Gemini Live session opened with %d history messages", len(self.conversation_history))

    async def send_audio(self, audio_data: bytes):
        """Send a chunk of raw PCM audio directly to Gemini."""
        if self.session and self._running:
            await self.session.send_realtime_input(
                audio=types.Blob(
                    mime_type="audio/pcm;rate=16000",
                    data=audio_data,
                )
            )

    async def end_user_turn(self):
        """Explicitly signal end of current user utterance."""
        if self.session and self._running:
            await self.session.send_realtime_input(audio_stream_end=True)

    async def receive_audio(self):
        """Continuously receive audio responses from Gemini.

        Yields (kind, data) tuples:
          ("audio", bytes)  – raw PCM audio chunk
          ("turn_complete", b"")  – model finished speaking
          ("transcript_user", str) – finalized user transcription chunk
          ("transcript_bot", str) – finalized assistant transcription chunk
        """
        while self._running and self.session:
            try:
                async for response in self.session.receive():
                    if not self._running:
                        return

                    if response.data:
                        logger.info("Got response.data: %d bytes", len(response.data))
                        yield ("audio", response.data)
                    elif response.server_content:
                        sc = response.server_content
                        if sc.input_transcription and sc.input_transcription.text:
                            text = sc.input_transcription.text.strip()
                            if text and text != self._last_user_transcript_text:
                                logger.info(
                                    "User transcript%s: %s",
                                    " (final)" if sc.input_transcription.finished else "",
                                    text,
                                )
                                self._last_user_transcript_text = text
                                yield ("transcript_user", text)

                        if sc.output_transcription and sc.output_transcription.text:
                            text = sc.output_transcription.text.strip()
                            if text and text != self._last_bot_transcript_text:
                                logger.info(
                                    "Bot transcript%s: %s",
                                    " (final)" if sc.output_transcription.finished else "",
                                    text,
                                )
                                self._last_bot_transcript_text = text
                                yield ("transcript_bot", text)

                        if sc.model_turn and sc.model_turn.parts:
                            for part in sc.model_turn.parts:
                                if part.inline_data and part.inline_data.data:
                                    logger.info("Got inline_data: %d bytes", len(part.inline_data.data))
                                    yield ("audio", part.inline_data.data)
                        if sc.turn_complete:
                            logger.info("Gemini turn complete")
                            yield ("turn_complete", b"")
            except StopAsyncIteration:
                break
            except Exception as e:
                if not self._running:
                    break
                logger.warning("receive_audio error: %s", e)
                await asyncio.sleep(0.1)
                continue

    async def close(self):
        self._running = False
        if self._session_context:
            try:
                await self._session_context.__aexit__(None, None, None)
            except Exception:
                pass
        self.session = None
        self._session_context = None
        logger.info("Gemini Live session closed")
