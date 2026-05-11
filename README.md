# O2 Platform — Maternal Healthcare Monitoring

**Offline-first maternal healthcare monitoring for ASHA workers in rural India.**

## Overview

O2 Platform empowers Community Health Workers (ASHAs) with an offline-first Flutter app that works without reliable internet, integrates with India's ABDM/ABHA health infrastructure, and provides clinical decision support (risk triage + SBAR summaries).

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│  Flutter CHW App (offline-first, SQLCipher encrypted)   │
│  Brick ORM + WorkManager + FHIR R4 models               │
└────────────────┬────────────────────────────────────────┘
                 │ sync (WiFi + Charging only)
                 ▼
┌─────────────────────────────────────────────────────────┐
│  Supabase PostgreSQL (PHC-based RLS isolation)           │
└────────┬──────────────────────┬──────────────────────────┘
         │                     │
         ▼                     ▼
┌─────────────────┐   ┌──────────────────────────────┐
│ FastAPI Backend │   │ IVR Backend (Twilio webhooks) │
│ /risk → triage  │   │ Missed call → WhatsApp voice  │
│ /sbar → LLM sum │   │ Emergency keyword detection   │
└─────────────────┘   └──────────────────────────────┘
```

## Phase 1 Components

### Flutter App (`apps/o2_app/`)
- **Offline-first**: Brick ORM + SQLCipher, WorkManager background sync
- **Encryption**: AES-256 via SQLCipher, key stored in Android Keystore
- **FHIR R4**: Patient, Observation (Vitals), DocumentReference models
- **Risk Triage**: Traffic-light (Low / Medium / High / Emergency) based on WHO maternal thresholds
- **ABDM Mock**: ABHA ID validation with Mod 97 checksum, HPR/HFR linking stubs
- **Voice Widget**: Bhashini STT/TTS stubs in `constants.dart`

### Supabase (`supabase/`)
- **Schema**: phc_hierarchy, chw_assignments, patients, vitals_logs, clinical_contact_logs, sbar_documents
- **RLS**: PHC-based isolation via `get_user_phc_ids()` helper function

### FastAPI Backend (`apps/o2_backend/`)
- **POST /risk**: Vitals → traffic-light risk assessment
- **POST /sbar**: Patient + Vitals + Notes → LLM-generated SBAR clinical summary

### IVR Backend (`ivr_backend/`)
- **Missed call** → Twilio webhook → Patient lookup → Free callback → Voice recording → WhatsApp to CHW
- **Emergency detector**: Keyword scanning in English, Kannada, Hindi

## Key Decisions (Phase 1)

| Decision | Rationale |
|----------|-----------|
| FHIR R4 as canonical format | Eliminates impedance mismatch between app and AI backend |
| SQLCipher + Android Keystore | PHI encryption at rest, hardware-backed key storage |
| WorkManager sync constraints | Rural WiFi scarcity, battery conservation |
| PHC-based RLS isolation | CHW data scoping by catchment area |
| Rule-based WHO thresholds | 24h MVP: no time for ML model training |
| Mod 97 ABHA validation | Offline-capable, official checksum algorithm |
| Single toll-free IVR number | No per-patient DID provisioning needed |

## Setup

### Flutter App
```bash
cd apps/o2_app
flutter pub get
flutter run
```

### FastAPI Backend
```bash
cd apps/o2_backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8000
```

### IVR Backend
```bash
cd ivr_backend
pip install -r requirements.txt
uvicorn main:app --reload --port 8001
```

### Supabase
```bash
supabase db push
# Then apply RLS policies:
psql $SUPABASE_DB_URL -f supabase/rls_policies.sql
```

## Documentation

- [Strategy](STRATEGY.md)
- [Implementation Plan](docs/plans/2026-05-11-001-feat-o2-platform-phase1-plan.md)
- [Ideation](docs/ideation/O2-Platform-ideation.md)
- [IVR Requirements](docs/brainstorms/O2-IVR-Communication-Layer-requirements.md)
- [Phase 1 Architecture Decisions](docs/solutions/o2-platform-phase1-mvp.md)

## What's Next (Phase 2)

- Real ABDM/NHA API integration (HPR verification, ABHA auth)
- ML-based risk scoring trained on Phase 1 historical data
- Live Bhashini STT/TTS integration
- FHIR R4 server for sync target
- Voice message transcription (ElevenLabs / Bhashini STT)
- CHW push notifications (FCM / Twilio Notify)

## License

MIT