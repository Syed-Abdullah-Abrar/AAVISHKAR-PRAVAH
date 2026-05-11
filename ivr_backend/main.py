"""
O2 Platform — IVR Backend (Twilio Webhook Handler)
Missed Call → Callback → Voice Recording → WhatsApp to CHW

Phase 1: Fully stubbed with documented API contracts.
Phase 2: Real Twilio + WhatsApp Business API integration.
"""

from fastapi import FastAPI, Header, HTTPException
from fastapi.responses import XMLResponse
from pydantic import BaseModel
from typing import Optional
import os

from patient_lookup import PatientLookupService
from whatsapp_sender import WhatsAppSenderService
from emergency_detector import EmergencyDetector

app = FastAPI(title="O2 IVR Backend", version="1.0.0")

patient_lookup = PatientLookupService()
whatsapp_sender = WhatsAppSenderService()
emergency_detector = EmergencyDetector()


# ─── Twilio Webhook Endpoints ────────────────────────────────────────────────

@app.post("/twilio/missed-call")
async def handle_missed_call(
    From: str,  # Caller phone number
    CallSid: str,
    CallStatus: str,
):
    """
    Twilio StatusCallback for missed call.
    
    1. Extract caller ID
    2. Lookup patient via caller ID
    3. If registered: initiate callback
    4. If not registered: play not-registered message
    """
    if CallStatus != "completed":
        return {"status": "ignored"}
    
    # Lookup patient
    patient = await patient_lookup.find_by_caller_id(From)
    
    if patient is None:
        # Not registered - play message (TwiML)
        return XMLResponse(content=f"""<?xml version="1.0" encoding="UTF-8"?>
<Response>
    <Say voice="alice" language="kn-IN">
        ನಮಸ್ಕಾರ, ನೀವು ನೋಂದಣೆಯಾಗಿಲ್ಲ. ದಯವಿಟ್ಟು ನಿಮ್ಮ ಆರೋಗ್ಯ ಕಾರ್ಯನಿರ್ವಾಹಕರನ್ನು ಸಂಪರ್ಕಿಸಿ.
    </Say>
</Response>""")
    
    # Initiate callback
    await _initiate_callback(patient, From)
    
    return {"status": "callback_initiated", "patient_id": patient["id"]}


@app.post("/twilio/voice-recording")
async def handle_voice_recording(
    RecordingUrl: str,
    CallSid: str,
    From: str,
    RecordingDuration: Optional[int] = 60,
):
    """
    Twilio RecordingCallback.
    
    1. Receive recording URL
    2. Detect emergency keywords
    3. Forward to CHW via WhatsApp
    4. If emergency: trigger escalation
    """
    # Get patient
    patient = await patient_lookup.find_by_caller_id(From)
    if patient is None:
        raise HTTPException(status_code=404, detail="Patient not found")
    
    # Emergency detection
    is_emergency = await emergency_detector.check_recording(RecordingUrl)
    
    if is_emergency:
        # Emergency escalation
        await _handle_emergency(patient, RecordingUrl)
    else:
        # Normal: forward to CHW WhatsApp
        await whatsapp_sender.send_voice_to_chw(
            chw_whatsapp=patient["chw_whatsapp"],
            recording_url=RecordingUrl,
            patient_name=patient["name"],
        )
    
    return {"status": "processed"}


# ─── Helper Functions ───────────────────────────────────────────────────────

async def _initiate_callback(patient: dict, caller_id: str):
    """Initiate callback to patient."""
    # TODO: Integrate with Twilio API
    print(f"[IVR] Initiating callback to {caller_id} for patient {patient['id']}")


async def _handle_emergency(patient: dict, recording_url: str):
    """Handle emergency: immediate CHW call + push notification."""
    # Call CHW immediately
    await whatsapp_sender.send_emergency_alert(
        chw_whatsapp=patient["chw_whatsapp"],
        patient_name=patient["name"],
        recording_url=recording_url,
    )
    print(f"[IVR] EMERGENCY alert sent for patient {patient['id']}")


# ─── Health ────────────────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "healthy", "service": "o2-ivr-backend"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8001)