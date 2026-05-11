"""
IndicTrans2 STT/TTS Service — O2 Platform Phase 2
Self-hosted IndicTrans2 (IIT-M AI4Bharat) Docker container.
Replaces Bhashini API which is not accessible for hackathon demo.

Docker setup:
  docker pull aiforskill/indictrans2:latest
  docker run -d -p 8000:8000 --name indictrans aiforskill/indictrans2:latest

API: POST http://localhost:8000/asr (STT), POST http://localhost:8000/tts (TTS)
"""

import os
import httpx
from typing import Optional

INDICTRANS_URL = os.getenv("INDICTRANS_URL", "http://localhost:8000")
USE_LOCAL_INDICTRANS = os.getenv("USE_LOCAL_INDICTRANS", "true").lower() == "true"

# Language code mapping
LANG_MAP = {
    "kn": "kan",  # Kannada
    "hi": "hin",  # Hindi
    "en": "eng",  # English
    "ta": "tam",  # Tamil
    "te": "tel",  # Telugu
}


async def transcribe_audio(audio_path: str, lang: str = "kn") -> str:
    """
    Transcribe audio file to text using IndicTrans2 STT.
    
    Args:
        audio_path: Path to audio file (wav/mp3)
        lang: Language code (kn= Kannada, hi= Hindi, en= English)
    
    Returns:
        str: Transcribed text
    """
    if not USE_LOCAL_INDICTRANS:
        return "[STT disabled - set USE_LOCAL_INDICTRANS=true]"

    lang_code = LANG_MAP.get(lang, "kan")
    
    try:
        with open(audio_path, "rb") as f:
            async with httpx.AsyncClient(timeout=30.0) as client:
                resp = await client.post(
                    f"{INDICTRANS_URL}/asr",
                    files={"audio": f},
                    data={"language": lang_code},
                )
        result = resp.json()
        return result.get("text", "")
    except Exception as e:
        print(f"[IndicTrans2 STT] Error: {e}")
        return ""


async def transcribe_from_url(audio_url: str, lang: str = "kn") -> str:
    """
    Download audio from URL and transcribe.
    
    Args:
        audio_url: URL to audio file
        lang: Language code
    
    Returns:
        str: Transcribed text
    """
    if not USE_LOCAL_INDICTRANS:
        return "[STT disabled]"
    
    lang_code = LANG_MAP.get(lang, "kan")
    
    try:
        async with httpx.AsyncClient(timeout=60.0) as client:
            # Download audio
            audio_resp = await client.get(audio_url)
            audio_resp.raise_for_status()
            
            # Transcribe
            files = {"audio": ("recording.wav", audio_resp.content, "audio/wav")}
            trans_resp = await client.post(
                f"{INDICTRANS_URL}/asr",
                files=files,
                data={"language": lang_code},
            )
        result = trans_resp.json()
        return result.get("text", "")
    except Exception as e:
        print(f"[IndicTrans2 STT] URL transcription error: {e}")
        return ""


async def synthesize_speech(text: str, lang: str = "kn", output_path: str = "output.wav") -> str:
    """
    Generate audio from text using IndicTrans2 TTS.
    
    Args:
        text: Text to synthesize
        lang: Language code
        output_path: Path to save audio file
    
    Returns:
        str: Path to generated audio file
    """
    if not USE_LOCAL_INDICTRANS:
        return "[TTS disabled - set USE_LOCAL_INDICTRANS=true]"
    
    lang_code = LANG_MAP.get(lang, "kan")
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{INDICTRANS_URL}/tts",
                json={"text": text, "language": lang_code},
            )
        with open(output_path, "wb") as f:
            f.write(resp.content)
        return output_path
    except Exception as e:
        print(f"[IndicTrans2 TTS] Error: {e}")
        return ""


async def translate_text(text: str, src_lang: str = "en", tgt_lang: str = "kn") -> str:
    """
    Translate text between languages using IndicTrans2.
    
    Args:
        text: Text to translate
        src_lang: Source language code
        tgt_lang: Target language code
    
    Returns:
        str: Translated text
    """
    if not USE_LOCAL_INDICTRANS:
        return f"[Translation disabled]"
    
    src_code = LANG_MAP.get(src_lang, "eng")
    tgt_code = LANG_MAP.get(tgt_lang, "kan")
    
    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            resp = await client.post(
                f"{INDICTRANS_URL}/translate",
                json={
                    "input_text": text,
                    "source_lang": src_code,
                    "target_lang": tgt_code,
                },
            )
        result = resp.json()
        return result.get("translated_text", "")
    except Exception as e:
        print(f"[IndicTrans2 Translate] Error: {e}")
        return ""


# ─── Health check ───────────────────────────────────────────────────────────────

async def health_check() -> dict:
    """Check if IndicTrans2 service is available."""
    if not USE_LOCAL_INDICTRANS:
        return {"status": "disabled", "url": INDICTRANS_URL}
    
    try:
        async with httpx.AsyncClient(timeout=5.0) as client:
            resp = await client.get(f"{INDICTRANS_URL}/health")
            return {"status": "available", "url": INDICTRANS_URL}
    except Exception:
        return {"status": "unavailable", "url": INDICTRANS_URL}