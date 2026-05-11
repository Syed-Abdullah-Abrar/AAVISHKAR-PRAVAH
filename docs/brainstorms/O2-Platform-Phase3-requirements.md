# O2 Platform — Phase 3 Requirements

**Date:** 2026-05-11  
**Phase:** 3 (End-to-End Wiring + Full Flutter UI + Deployment Demo)  
**Based on:** `docs/ideation/O2-Platform-Phase3-ideation.md`

---

## Context

Phase 1 built the foundation (Flutter app, Supabase schema, FastAPI AI server, IVR contracts, ABDM mock).  
Phase 2 pivoted external APIs to local alternatives (Mod97 ABHA generator, IndicTrans2 Docker, Telegram Bot, SQLite, XGBoost shadow ML) with adapter pattern (`USE_LIVE_ABDM`, `USE_TWILIO`, `USE_BHASHINI`).  

**Phase 3 goal:** Complete wiring from stubs to functional, full Flutter UI, online deployment demo.

---

## Key Decisions

### IVR Pipeline: Telegram-Based (Not Twilio)

Twilio access problems in Phase 2 → use Telegram Bot as the free patient communication layer:
- Patient sends voice message via Telegram bot (no phone number needed, no Twilio account)
- Voice forwarded to CHW + PHC supervisor via existing `telegram_alerts.py`
- STT via IndicTrans2 Docker at `localhost:8000`
- Adapter pattern: `USE_TWILIO=true` env var unlocks real Twilio when credentials arrive — no code rewrite

### Flutter App: Fully Offline-First with Local SQLite

- Supabase sync is optional for demo (SQLite-only works)
- `geolocator` + GPS auto-tag on clinical contacts (NHM compliance)
- IndicTrans2 HTTP client replaces Bhashini stubs in `core/constants.dart`
- Telegram service in Flutter for in-app alert notifications

---

## Requirements

### R1: IVR Backend — Wire Telegram IVR Pipeline

**What:** `ivr_backend/` endpoints that accept Telegram voice messages, transcribe via IndicTrans2, and route to CHW via Telegram.

**Endpoints:**

```
POST /ivr/voice-message   — Telegram bot forwards patient's voice message
  Request: { patient_id, file_id, language: "kn"|"hi"|"en" }
  → Download audio from Telegram
  → POST /asr to IndicTrans2 Docker (localhost:8000)
  → Store transcript in SQLite (ivr_transcripts table)
  → Send Telegram message to CHW with transcript text
  → If emergency keywords found → send_telegram_message to all EMERGENCY recipients
  
GET /ivr/transcript/{patient_id}  — Fetch all transcripts for a patient
GET /health  — Health check
```

**Behavior:**
- Patient sends voice via Telegram bot → bot webhook hits `/ivr/voice-message`
- Audio downloaded, sent to IndicTrans2 STT → transcript returned
- Critical keywords ("help", "emergency", "bleeding", "pain", "fever") trigger `EMERGENCY` tier alerts
- Non-critical → `MEDIUM` tier to CHW only

**Database tables (exist from Phase 2):**
```sql
-- Already in services/database.py
CREATE TABLE ivr_transcripts (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    audio_url TEXT,
    transcript_text TEXT,
    language TEXT DEFAULT 'kn',
    caller_number TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);
```

**Env vars:**
- `TELEGRAM_BOT_TOKEN` — already used by `services/telegram_alerts.py`
- `INDICTRANS_URL` — already `http://localhost:8000`
- `USE_TWILIO` — set to `false` (Telegram mode)

---

### R2: Flutter App — Completeness: Patient List + Vitals Entry + Risk Display + SBAR Review

**What:** All screens referenced in `core/router.dart` that currently have placeholder builders need real UI.

**Screens needed:**

| Screen | Route | Description |
|--------|-------|-------------|
| `HomeScreen` | `/home` | CHW home: patient count, recent alerts, sync status |
| `PatientListScreen` | `/patients` | All registered patients, filter by risk level |
| `PatientRegistrationScreen` | `/patients/register` | ABHA generation + name + DOB + phone + emergency contact |
| `PatientDetailScreen` | `/patients/:id` | Patient summary, vitals history, SBAR button, visit log |
| `VitalsEntryScreen` | `/patients/:id/vitals` | BP, heart rate, SpO2, temperature, weight, height, gestation week entry |
| `SBARScreen` | `/patients/:id/sbar` | Display SBAR document from FastAPI `/sbar` endpoint |
| `VoiceInputScreen` | `/voice-input` | Record audio, send to IndicTrans2, return transcribed text |

**Integration points:**
- `POST /risk` → get traffic-light triage for vitals
- `POST /sbar` → generate SBAR from patient data + vitals history
- `GET /abdm/patient/:id` → get patient ABHA details
- `POST /visits/log` → log GPS-tagged home visit

**Implementation approach:**
1. Wire `indictrans_service.dart` to `core/constants.dart` — replace Bhashini stubs with IndicTrans2 HTTP calls
2. Build minimal UI for each screen (no fancy animations — functional for demo)
3. Use existing Brick repositories (`patient_repository.dart`, `vitals_repository.dart`)
4. GPS auto-tag when logging visit: call `geolocator` package, attach lat/long to visit log

---

### R3: Flutter Service Integrations

**Telegram Service (`services/telegram_service.dart`):**
- Receive Telegram bot updates via webhook polling or webhook endpoint
- Parse incoming voice messages → forward to `/ivr/voice-message` endpoint
- Display time-critical EMERGENCY/HIGH alerts inside app (not just Telegram)
- Riverpod provider: `telegramServiceProvider`

**GPS Auto-Tag (`services/location_service.dart`):**
- Use `geolocator` package (already in pubspec.yaml via transitive deps)
- On `VitalsEntryScreen` open: get current GPS coordinates
- On visit log submit: attach `latitude`, `longitude` to `POST /visits/log`
- `clinical_contact.dart` has `visit_location` field — wire it to GPS coordinates

**IndicTrans2 Dart Client (`services/indictrans_service.dart`):**
```dart
// Replace bhashini stubs in core/constants.dart
class IndicTransService {
  static const String baseUrl = 'http://10.0.2.2:8000'; // Android emulator localhost
  static const String sttEndpoint = '/asr';
  static const String ttsEndpoint = '/tts';
  
  Future<String> transcribe(String audioPath, String lang);
  Future<String> synthesize(String text, String lang);
}
```

---

### R4: Backend Deployment — Online Demo

**What:** Deploy FastAPI backend + IVR backend to a public URL so Flutter app can hit them from a real device (not just localhost).

**Targets (user picks one):**
- Railway — `railway up` deploys from GitHub, gives public URL
- Render — free tier, `render.yaml` or manual
- Fly.io — `fly launch`, `fly deploy`

**Required env vars to configure:**
```
TELEGRAM_BOT_TOKEN=<token>
INDICTRANS_URL=http://localhost:8000  # for local Docker
MINIMAX_API_KEY=<key>
DB_PATH=o2_platform.db
USE_LIVE_ABDM=false
USE_TWILIO=false
USE_BHASHINI=false
```

**For Flutter to talk to deployed backend:**
- Update `core/constants.dart` → `aiServerUrl` from `http://<HOST>:8000` to deployed URL
- Update `ivrBackendUrl` similarly

---

### R5: System Wiring — End-to-End Test

**What:** Verify the complete call chain works: Flutter → FastAPI → IVR → Telegram → CHW.

**Test scenario:**
1. CHW opens Flutter app → logs GPS-tagged vitals for patient
2. FastAPI `/risk` returns traffic-light triage
3. If HIGH/EMERGENCY → `telegram_alerts.py` sends alert to CHW + supervisor
4. Patient sends voice message via Telegram bot
5. `/ivr/voice-message` receives → IndicTrans2 STT → transcript stored in SQLite
6. Transcript sent to CHW via Telegram
7. If emergency keywords → EMERGENCY tier alert fires

**Smoke test:** Manual end-to-end walkthrough with test data. No automated tests required for Phase 3 (hackathon demo scope).

---

## Outside This Phase

- **On-device quantized XGBoost** — deferred to Phase 4 (requires ONNX runtime + model validation)
- **Live ABDM/NHA integration** — `USE_LIVE_ABDM=true` when NHA credentials arrive
- **WhatsApp Business API** — Telegram used as free alternative; WhatsApp adapter for when credentials arrive
- **Flutter web build** — supervisor dashboard stays as FastAPI HTML for now

---

## Dependencies

- IndicTrans2 Docker container must be running: `docker run -d -p 8000:8000 --name indictrans aiforskill/indictrans2:latest`
- Telegram bot must be created via `@BotFather` and `TELEGRAM_BOT_TOKEN` env var set
- Patient phone numbers must be registered with the Telegram bot (patient starts chat with bot)

---

## Success Criteria

1. ✅ Flutter app can register patient, enter vitals, see risk score, view SBAR
2. ✅ GPS coordinates attached to every home visit log
3. ✅ Telegram bot receives patient voice message → transcribes → sends to CHW
4. ✅ Emergency keyword detection triggers multi-recipient Telegram alert
5. ✅ FastAPI backend accessible from deployed URL
6. ✅ End-to-end smoke test passes (Flutter → FastAPI → IVR → Telegram → CHW)