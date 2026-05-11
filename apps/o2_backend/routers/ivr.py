"""
IVR Router — O2 Platform FastAPI Backend
Telegram-based IVR: voice message → IndicTrans2 STT → Telegram alert to CHW

Phase 3: Merged from ivr_backend/ into FastAPI as /ivr router.
Uses Telegram Bot API (no Twilio needed for demo).
When USE_TWILIO=true with real credentials → Twilio webhook adapter.

Endpoints:
- POST /ivr/voice-message — Telegram voice file_id → IndicTrans2 STT → alert
- GET /ivr/transcript/{patient_id} — Fetch all transcripts for a patient
- GET /ivr/health — Health check
"""

import os
import uuid
import httpx
from datetime import datetime, timezone
from typing import Optional, List
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel

from services.telegram_alerts import send_telegram_message, build_alert_message
from services.indictrans import transcribe_from_url, health_check as indictrans_health
from services.database import patient_repo

router = APIRouter(prefix="/ivr", tags=["IVR"])

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_API = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}"
USE_TWILIO = os.getenv("USE_TWILIO", "false").lower() == "true"


# ─── Request/Response Models ────────────────────────────────────────────────────

class IvrVoiceMessageRequest(BaseModel):
    patient_id: str
    file_id: str  # Telegram file_id for voice message
    language: str = "kn"  # kn=Kannada, hi=Hindi, en=English


class IvrVoiceMessageResponse(BaseModel):
    transcript: str
    alert_tier: str  # EMERGENCY | MEDIUM | LOW
    is_critical: bool
    patient_name: str


class IvrTranscriptResponse(BaseModel):
    patient_id: str
    transcripts: List[dict]
    count: int


# ─── Emergency Keywords ────────────────────────────────────────────────────────

EMERGENCY_KEYWORDS = [
    "help", "emergency", "bleeding", "pain", "fever",
    "not feeling", "difficulty", "can't breathe", "severe",
    "dizzy", "fainted", "swelling", "headache", "vision",
]


# ─── Telegram Helpers ─────────────────────────────────────────────────────────

async def _download_telegram_file(file_id: str) -> bytes:
    """Download voice file from Telegram by file_id."""
    if not TELEGRAM_BOT_TOKEN:
        raise HTTPException(status_code=500, detail="TELEGRAM_BOT_TOKEN not configured")
    
    async with httpx.AsyncClient(timeout=30.0) as client:
        # Get file path from Telegram
        file_resp = await client.get(
            f"{TELEGRAM_API}/getFile",
            params={"file_id": file_id}
        )
        file_data = file_resp.json()
        
        if not file_data.get("ok"):
            raise HTTPException(
                status_code=400,
                detail=f"Telegram getFile failed: {file_data}"
            )
        
        file_path = file_data["result"]["file_path"]
        
        # Download the actual file
        download_url = f"{TELEGRAM_API}/file/bot{TELEGRAM_BOT_TOKEN}/{file_path}"
        audio_resp = await client.get(download_url)
        audio_resp.raise_for_status()
        
        return audio_resp.content


async def _transcribe_audio(audio_bytes: bytes, language: str, patient_id: str) -> str:
    """
    Transcribe audio via IndicTrans2 Docker at localhost:8000.
    Writes temp .wav file, transcribes, returns transcript text.
    """
    import tempfile
    
    # Save temp audio file
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(audio_bytes)
        temp_path = f.name
    
    try:
        # Use IndicTrans2 STT
        transcript = await transcribe_from_url(f"file://{temp_path}", language)
        return transcript if transcript else ""
    except Exception as e:
        print(f"[IVR] IndicTrans2 STT error: {e}")
        return ""
    finally:
        # Cleanup temp file
        try:
            os.unlink(temp_path)
        except Exception:
            pass


# ─── Alert Helpers ─────────────────────────────────────────────────────────────

async def _send_ivr_alert_to_chw(
    patient_id: str,
    patient_name: str,
    transcript: str,
    language: str,
    is_critical: bool,
) -> dict:
    """Send IVR transcript alert to CHW via Telegram."""
    tier = "EMERGENCY" if is_critical else "MEDIUM"
    
    # Get CHW's Telegram ID from patient record
    patient = await patient_repo.get(patient_id)
    chw_telegram_id = patient.get("chw_telegram_id") if patient else None
    
    message = build_alert_message(
        patient_name=patient_name or "Unknown Patient",
        risk_level=tier,
        alert_type="IVR Voice Alert",
        details=f"*Transcript:*\n{transcript[:500]}",
    )
    
    results = {}
    
    # Send to CHW directly
    if chw_telegram_id:
        results["chw"] = await send_telegram_message(chw_telegram_id, message)
    
    return {
        "tier": tier,
        "chw_notified": results.get("chw", False),
        "transcript_length": len(transcript),
    }


# ─── Endpoints ────────────────────────────────────────────────────────────────

@router.post("/voice-message", response_model=IvrVoiceMessageResponse)
async def handle_voice_message(req: IvrVoiceMessageRequest):
    """
    Receive Telegram voice message, transcribe, store, and alert CHW.
    
    Flow:
    1. Download audio from Telegram using file_id
    2. Transcribe via IndicTrans2 STT
    3. Store transcript in SQLite
    4. Check emergency keywords → determine alert tier
    5. Send Telegram message to CHW
    """
    # Get patient info
    patient = await patient_repo.get(req.patient_id)
    if not patient:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    patient_name = patient.get("name", "Unknown")
    
    try:
        # Step 1: Download audio from Telegram
        audio_bytes = await _download_telegram_file(req.file_id)
        
        # Step 2: Transcribe via IndicTrans2
        transcript = await _transcribe_audio(audio_bytes, req.language, req.patient_id)
        
        # Step 3: Store transcript in SQLite (using aiosqlite directly)
        import aiosqlite
        from services.database import DB_PATH
        
        transcript_id = str(uuid.uuid4())
        async with aiosqlite.connect(DB_PATH) as db:
            await db.execute("""
                INSERT INTO ivr_transcripts (id, patient_id, transcript_text, language, caller_number, audio_url)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                transcript_id,
                req.patient_id,
                transcript,
                req.language,
                f"telegram_file_{req.file_id[:20]}",
                f"telegram_file_{req.file_id}",
            ))
            await db.commit()
        
        # Step 4: Check emergency keywords
        transcript_lower = transcript.lower() if transcript else ""
        is_critical = any(
            keyword in transcript_lower
            for keyword in EMERGENCY_KEYWORDS
        )
        alert_tier = "EMERGENCY" if is_critical else "MEDIUM"
        
        # Step 5: Send Telegram alert to CHW
        await _send_ivr_alert_to_chw(
            req.patient_id,
            patient_name,
            transcript,
            req.language,
            is_critical,
        )
        
        return IvrVoiceMessageResponse(
            transcript=transcript,
            alert_tier=alert_tier,
            is_critical=is_critical,
            patient_name=patient_name,
        )
        
    except HTTPException:
        raise
    except Exception as e:
        print(f"[IVR] Error handling voice message: {e}")
        raise HTTPException(status_code=500, detail=f"IVR processing failed: {e}")


@router.get("/transcript/{patient_id}", response_model=IvrTranscriptResponse)
async def get_transcripts(patient_id: str):
    """Fetch all IVR transcripts for a patient."""
    import aiosqlite
    from services.database import DB_PATH
    
    async with aiosqlite.connect(DB_PATH) as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute(
            "SELECT * FROM ivr_transcripts WHERE patient_id = ? ORDER BY created_at DESC",
            (patient_id,)
        )
        rows = await cursor.fetchall()
        transcripts = [dict(row) for row in rows]
    
    return IvrTranscriptResponse(
        patient_id=patient_id,
        transcripts=transcripts,
        count=len(transcripts),
    )


@router.get("/health")
async def ivr_health():
    """Check IVR system health: Telegram token, IndicTrans2."""
    indictrans_status = await indictrans_health()
    
    return {
        "status": "healthy",
        "ivr_service": "telegram",
        "use_twilio": USE_TWILIO,
        "telegram_configured": bool(TELEGRAM_BOT_TOKEN),
        "indictrans": indictrans_status,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }