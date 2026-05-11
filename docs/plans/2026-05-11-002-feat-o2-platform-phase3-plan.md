# O2 Platform — Phase 3 Implementation Plan

**Date:** 2026-05-11  
**Phase:** 3 (End-to-End Wiring + Full Flutter UI + Deployment Demo)  
**Based on:** `docs/brainstorms/O2-Platform-Phase3-requirements.md` + `docs/ideation/O2-Platform-Phase3-ideation.md`

---

## Overview

Phase 3 wires all stubs to functional, completes the Flutter UI, merges IVR into FastAPI, and deploys online for the hackathon demo.

**Key architectural decision:** Merge `ivr_backend/` into FastAPI as `/ivr` router — single process, simpler deployment. Twilio adapter remains (`USE_TWILIO=true` env var).

---

## Implementation Units

### U1: IVR Backend — Merge into FastAPI + Telegram IVR Pipeline

**What:** Wire `ivr_backend/` endpoints into FastAPI as `/ivr` router, implement Telegram voice message handling with IndicTrans2 STT.

**Files to create/modify:**
- Create `apps/o2_backend/routers/ivr.py` — FastAPI router for IVR endpoints
- Modify `apps/o2_backend/main.py` — add `ivr` router, merge from `ivr_backend/` logic

**Endpoints:**
```python
POST /ivr/voice-message
  # Request: { patient_id, file_id, language: "kn"|"hi"|"en" }
  # 1. Download audio from Telegram file_id
  # 2. POST /asr to IndicTrans2 Docker (localhost:8000)
  # 3. Store transcript in SQLite (ivr_transcripts table)
  # 4. Build alert message with transcript
  # 5. Call send_risk_alert() from telegram_alerts.py
  # 6. Return: { transcript, alert_sent, alert_tier }

GET /ivr/transcript/{patient_id}
  # Fetch all ivr_transcripts for patient

GET /ivr/health
  # Check IndicTrans2 availability + database
```

**Code sketch — `/ivr/voice-message`:**
```python
@router.post("/voice-message")
async def handle_voice_message(req: IvrVoiceRequest):
    # 1. Download audio from Telegram
    telegram_file_url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/getFile?file_id={req.file_id}"
    # ... get file_path, download from telegram file URL
    
    # 2. Transcribe via IndicTrans2
    transcript = await transcribe_from_url(telegram_audio_url, req.language)
    
    # 3. Store transcript
    await ivr_repo.create({ "id": uuid4(), "patient_id": req.patient_id, 
                            "transcript_text": transcript, "language": req.language })
    
    # 4. Check emergency keywords → alert tier
    keywords = ["help", "emergency", "bleeding", "pain", "fever", "not feeling", "difficulty"]
    is_critical = any(k in transcript.lower() for k in keywords)
    alert_tier = "EMERGENCY" if is_critical else "MEDIUM"
    
    # 5. Send to CHW via existing telegram_alerts.py
    await send_ivr_transcript_alert(req.patient_id, patient_name, transcript, req.language)
    
    return {"transcript": transcript, "alert_tier": alert_tier, "is_critical": is_critical}
```

**Env vars needed:**
```env
TELEGRAM_BOT_TOKEN=<from @BotFather>
INDICTRANS_URL=http://localhost:8000
USE_TWILIO=false
```

---

### U2: Flutter UI Completeness — All Screens

**What:** Build real UI for all screens referenced in `core/router.dart`. No placeholder `Container()` widgets.

**Files to modify:**
- `apps/o2_app/lib/app.dart` — already has the router, needs `_O2AppState` builder implementations
- `apps/o2_app/lib/core/router.dart` — routes already defined, needs screen implementations
- Create new screen files in `apps/o2_app/lib/screens/`

**Screens to build:**

| Screen | File | Key Features |
|--------|------|--------------|
| `HomeScreen` | `screens/home_screen.dart` | Patient count card, recent HIGH alerts, sync status indicator |
| `PatientListScreen` | `screens/patient_list_screen.dart` | ListView with risk-level filter chips (ALL/HIGH/MEDIUM/LOW) |
| `PatientRegistrationScreen` | `screens/patient_registration_screen.dart` | Call `POST /abdm/generate-abha`, form for name/DOB/phone/gender/emergency_contact |
| `PatientDetailScreen` | `screens/patient_detail_screen.dart` | ABHA display, vitals history chart, SBAR button, visit log |
| `VitalsEntryScreen` | `screens/vitals_entry_screen.dart` | BP systolic/diastolic, HR, SpO2, temp, weight, height, gestation weeks. Call `POST /risk` on submit, show traffic-light result |
| `SBARScreen` | `screens/sbar_screen.dart` | Call `POST /sbar` with patient_id + vitals, display formatted SBAR markdown |
| `VoiceInputScreen` | `screens/voice_input_screen.dart` | Record button → `indictrans_service.dart` STT → display Kannada/Hindi transcript |

**Integration points:**
```dart
// core/constants.dart — update API URLs for deployed backend
static const String aiServerUrl = 'https://<deployed-host>.railway.app'; // Phase 3 deployment
static const String ivrBackendUrl = 'https://<deployed-host>.railway.app';
```

**Key services to wire:**
```dart
// services/indictrans_service.dart — new file
class IndicTransService {
  // POST http://10.0.2.2:8000/asr (Android emulator localhost → docker host)
  // POST /tts for TTS
  Future<String> transcribe(File audio, String lang); // kn, hi, en
  Future<String> synthesize(String text, String lang);
}

// services/telegram_service.dart — new file
class TelegramService {
  // Poll Telegram bot updates or use webhook
  // Send/receive messages
  // Riverpod provider: telegramServiceProvider
}

// services/location_service.dart — new file
class LocationService {
  // geolocator package — getCurrentPosition()
  // Returns {latitude, longitude}
  // Attach to visit log on submit
}
```

---

### U3: Flutter — GPS Auto-Tag on Visit Log

**What:** Wire `geolocator` to attach GPS coordinates to every visit log.

**Files to modify:**
- `apps/o2_app/lib/screens/vitals_entry_screen.dart` — get GPS on open, attach to submission
- `apps/o2_app/lib/models/clinical_contact.dart` — `visit_location` field already exists
- `apps/o2_app/lib/repositories/` — add `visit_location` to visit log model

**Code sketch — `vitals_entry_screen.dart`:**
```dart
import 'package:geolocator/geolocator.dart';

Future<void> _logVisit() async {
  // Get GPS coordinates
  Position pos = await Geolocator.getCurrentPosition(
    locationSettings: LocationSettings(accuracy: LocationAccuracy.high)
  );
  
  // Submit vitals + GPS
  final response = await http.post(
    '$aiServerUrl/visits/log',
    json: {
      "patient_id": patientId,
      "latitude": pos.latitude,
      "longitude": pos.longitude,
      "chw_id":chwId,
      "notes": notesController.text,
    }
  );
}
```

**pubspec.yaml — add geolocator:**
```yaml
dependencies:
  geolocator: ^13.0.2
  permission_handler: ^11.3.1
```

---

### U4: FastAPI Backend — Online Deployment Prep

**What:** Ensure FastAPI backend runs as single process (AI server + IVR merged), add health checks, configure CORS for deployed URL.

**Files to modify:**
- `apps/o2_backend/main.py` — add `/ivr` router, update CORS for deployed URL
- `.env.example` — document all env vars for deployment

**Code sketch — `main.py` additions:**
```python
from routers.ivr import router as ivr_router

app.include_router(ivr_router, prefix="/ivr", tags=["IVR"])

# CORS — add deployed URL
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "https://<deployed-host>.railway.app",  # Phase 3 deployment
    ],
    ...
)
```

**`.env.example`:**
```env
# Required for Phase 3
TELEGRAM_BOT_TOKEN=your_telegram_bot_token_from_BotFather
MINIMAX_API_KEY=your_minimax_api_key

# Optional (for live APIs later)
USE_LIVE_ABDM=false
USE_TWILIO=false
USE_BHASHINI=false

# Database
DB_PATH=o2_platform.db
INDICTRANS_URL=http://localhost:8000
```

---

### U5: System Wiring — End-to-End Smoke Test

**Manual test script (no automated test framework for Phase 3):**

1. **Start services:**
   ```bash
   # Terminal 1: IndicTrans2 Docker
   docker run -d -p 8000:8000 --name indictrans aiforskill/indictrans2:latest
   
   # Terminal 2: FastAPI backend (merged AI + IVR)
   cd apps/o2_backend && python main.py
   ```

2. **Flutter → FastAPI test:**
   - Open Flutter app → register patient → enter vitals → see traffic-light result
   - Verify GPS coordinates in SQLite: `SELECT latitude, longitude FROM visits`

3. **Telegram IVR test:**
   - Patient sends voice message via Telegram bot
   - CHW receives transcribed text via Telegram
   - Emergency keyword test: say "help" + "fever" → verify EMERGENCY alert fires

4. **Deploy test:**
   - Deploy to Railway: `railway up`
   - Update `core/constants.dart` with deployed URL
   - Test from physical Android device (not emulator)

---

## Requirements Checklist

| # | Requirement | Implementation |
|---|-------------|----------------|
| R1 | IVR voice message → IndicTrans2 STT → Telegram to CHW | `/ivr/voice-message` + `send_ivr_transcript_alert()` |
| R2 | Flutter patient list + vitals entry + risk display + SBAR | 7 screens in `screens/` directory |
| R3 | Flutter Telegram service + IndicTrans2 Dart client + GPS | 3 new service files + geolocator |
| R4 | FastAPI deployed online (Railway/Render/Fly.io) | Merge IVR, update CORS, `.env.example` |
| R5 | End-to-end smoke test | Manual test script above |

---

## Env Vars for Phase 3

```env
# Core (required)
TELEGRAM_BOT_TOKEN=<from @BotFather>
MINIMAX_API_KEY=<in environment>

# IVR (Phase 3)
USE_TWILIO=false  # Telegram mode
INDICTRANS_URL=http://localhost:8000

# DB
DB_PATH=o2_platform.db

# Deployment
ENV=production
```

---

## Deferred to Phase 4

- On-device quantized XGBoost (ONNX runtime + validation)
- Live Twilio integration (`USE_TWILIO=true` with credentials)
- Live NHA/ABDM (`USE_LIVE_ABDM=true` with credentials)
- WhatsApp Business API
- Automated test suite