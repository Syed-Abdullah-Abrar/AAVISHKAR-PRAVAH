# O2 Platform — Investor Pitch

> Live document — update before each pitch session.

---

## The Problem

**Maternal mortality in rural India is preventable — yet 50 women die every day.**

The majority of these deaths occur in low-resource, remote areas where:

- ASHAs (Accredited Social Health Activists) lack real-time clinical decision support tools
- Patients cannot reach hospitals without early warning of complications
- Internet connectivity is unreliable or absent
- India's own health infrastructure (ABDM/ABHA) is inaccessible offline

**Current state**: CHWs do paper-based tracking, WhatsApp text messages, or apps that fail when offline — leaving the most vulnerable women completely unmonitored.

---

## Our Solution

**O2 Platform** — an offline-first mobile app for ASHA workers that works without internet, integrates with India's national health stack (ABDM), and provides AI-driven clinical decision support.

### The Flow

```
CHW opens app (works offline — no internet needed)
    ↓
Enter patient vitals → Risk Assessment (WHO thresholds, no internet)
    ↓
If HIGH/EMERGENCY → Alert CHW + PHC supervisor
    ↓
Generate SBAR summary (when back online) → LLM clinical handover document
    ↓
Sync to Supabase when WiFi available

Feature-phone patient:
    ↓
Gives missed call to toll-free number
    ↓
Twilio webhook → Patient lookup → Free callback
    ↓
Patient records voice message → WhatsApp sent to CHW
```

---

## Market & Problem Detail

### The Gap
- **15.6 million** pregnancies in India per year (NFHS 5)
- **~18,000** maternal deaths annually — many preventable
- **~1 million** ASHAs deployed nationwide, but limited clinical decision support
- Rural doctor-to-patient ratio: **1:10,000+**

### Why Current Solutions Fail
| Approach | Problem |
|----------|---------|
| Paper-based tracking | No alerts, no trend analysis, easy to lose |
| WhatsApp groups | No structure, no clinical logic, no offline support |
| Generic health apps | Require internet, don't understand CHW workflow |
| Hospital-centric apps | Designed for facilities, not homes |

---

## Key Features

| Feature | How It Works |
|---------|-------------|
| **Offline-First** | SQLCipher-encrypted local DB; WorkManager syncs only on WiFi + Charging |
| **Clinical Decision Support** | Traffic-light triage (LOW / MEDIUM / HIGH / EMERGENCY) from vitals using WHO thresholds |
| **AI Summaries** | SBAR (Situation-Background-Assessment-Recommendation) reports via LLM |
| **ABDM Integration** | ABHA ID validation (Mod 97 checksum), HPR/HFR linking — mock in Phase 1 |
| **Voice Interface** | Bhashini STT/TTS for low-literacy users (stub in Phase 1) |
| **IVR for Feature Phones** | Missed call → free callback → voice recording → WhatsApp to CHW |
| **PHC-Based Access Control** | Supabase Row Level Security enforces data isolation by catchment area |

---

## Tech Stack

### Why Each Technology Was Chosen

#### Flutter (Mobile Framework)
**Why**: Cross-platform, works on low-end Android devices (₹5,000–₹8,000 phones), single codebase for app + future web dashboard.

**Alternatives considered**: React Native (less offline support), native Android (iOS excluded), PWA (poor offline capability).

**Key packages**: `flutter_riverpod` (state management), `go_router` (navigation), `workmanager` (background sync).

---

#### Brick ORM + SQLCipher (Offline Data)
**Why**: Brick provides offline-first repository pattern — data lives locally, syncs when connected. SQLCipher adds AES-256 encryption at rest.

**Problem solved**: Patient data is PHI. Without encryption, a lost/stolen phone exposes sensitive health data. SQLCipher + Android Keystore means even root access can't read the database without the hardware-backed key.

**Key packages**: `brick_offline_first_with_supabase`, `sqflite_sqlcipher`.

---

#### WorkManager (Background Sync)
**Why**: Rural CHWs have expensive, unreliable data. Sync only on WiFi when device is charging prevents bill shock and battery drain.

```
WorkManager constraints:
  - NetworkType.unmetered (WiFi only)
  - requiresCharging: true
  - flexIntervalMinutes: 15
```

---

#### FHIR R4 (Data Format)
**Why**: India NHS (National Health Stack) uses FHIR R4. By making FHIR the canonical format everywhere — app models, API payloads, database — we eliminate translation layers and can plug into government systems directly.

**Format mapping**:
- Patient → `FHIR Patient` resource
- Vitals → `FHIR Observation` resource  
- SBAR → `FHIR DocumentReference` resource

**Key package**: `fhir` (Dart) — native FHIR R4 deserialization.

---

#### FastAPI (AI Backend)
**Why**: Python's scientific computing ecosystem + async HTTP. FastAPI handles the `/risk` (triage) and `/sbar` (LLM summary) endpoints.

**Phase 1**: Rule-based WHO thresholds (deterministic, explainable).  
**Phase 2+**: ML model (Gradient Boosting) trained on Phase 1 historical data.

**Key packages**: `fastapi`, `pydantic`, `openai`/`anthropic` (LLM), `scikit-learn` (Phase 2 ML).

---

#### Supabase (Backend Database)
**Why**: PostgreSQL with Row Level Security (RLS) — database enforces data isolation at the query level. CHW can only see patients in their assigned PHC(s). No app-layer security依赖于.

```
RLS Policy pattern:
  patients: phc_id = ANY(get_user_phc_ids(auth.uid()))
  vitals_logs: patient_id IN (SELECT id FROM patients WHERE phc_id = ANY(get_user_phc_ids()))
```

---

#### Twilio + WhatsApp (IVR)
**Why**: Feature-phone patients can't use smartphone apps. Missed-call IVR is zero-cost to patient, works on any phone. Voice message forwarded to CHW via WhatsApp — CHW already uses WhatsApp daily.

**Flow**:
1. Patient gives missed call to toll-free number
2. Twilio webhook hits `/twilio/missed-call` with caller ID
3. `patient_lookup.py` maps caller ID → patient → CHW WhatsApp number
4. System calls patient back (free for patient)
5. Patient records voice message
6. Twilio forwards recording URL to `whatsapp_sender.py`
7. CHW receives WhatsApp voice note

---

#### ABDM / ABHA (India Health ID)
**Why**: India's Ayushman Bharat Digital Mission requires ABHA (Ayushman Bharat Health Account) numbers. Mod 97 checksum validates ABHA format offline. Phase 2 will connect to live NHA APIs.

```
ABHA Format: XXXX-XXXX-XXXX-XX
Checksum validation: number % 97 == 1 (ISO 7064 Mod 97)
```

---

## The Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Flutter CHW App (offline-first, SQLCipher encrypted)         │
│                                                             │
│  Brick ORM (local SQLite) ←→ FHIR R4 models                 │
│  WorkManager (WiFi + Charging sync)                         │
│  Android Keystore (hardware-backed encryption key)           │
└───────────────────────┬─────────────────────────────────────┘
                        │ sync (WiFi + Charging)
                        ▼
┌─────────────────────────────────────────────────────────────┐
│  Supabase PostgreSQL                                         │
│  PHC-based Row Level Security                               │
│  Tables: phc_hierarchy, chw_assignments, patients,          │
│         vitals_logs, clinical_contact_logs, sbar_documents  │
└────────┬──────────────────────┬────────────────────────────┘
         │                      │
         ▼                      ▼
┌──────────────────┐    ┌────────────────────────────────────┐
│ FastAPI Backend  │    │ IVR Backend (Twilio webhooks)      │
│                  │    │                                    │
│ POST /risk       │    │ /twilio/missed-call                │
│ → Traffic-light  │    │ /twilio/voice-recording            │
│   triage         │    │                                    │
│                  │    │ PatientLookup → WhatsAppSender     │
│ POST /sbar       │    │ EmergencyKeywordDetector (EN/KN/HI)│
│ → LLM SBAR       │    │                                    │
│   generation     │    └────────────────────────────────────┘
└──────────────────┘
```

---

## Traction & Progress

| Milestone | Status |
|-----------|--------|
| Phase 1 MVP (hackathon) | ✅ Implemented — 6 units, 259 files, 48k lines |
| FHIR R4 native models | ✅ Patient, Observation, DocumentReference |
| Offline-first architecture | ✅ Brick + SQLCipher + WorkManager |
| Traffic-light triage | ✅ WHO maternal health thresholds |
| IVR missed-call flow | ✅ Twilio → patient lookup → WhatsApp |
| ABDM mock | ✅ Mod 97 ABHA checksum validation |
| SBAR LLM generation | ✅ JSON schema enforcement |
| Circular import fix | ✅ Central `models/__init__.py` |
| PHC-based RLS | ✅ `get_user_phc_ids()` helper |

---

## Phase 3 Roadmap (Completed)

| Item | Description | Status |
|------|-------------|--------|
| **Telegram Bot IVR** | Patient voice → IndicTrans2 STT → Telegram alert to CHW (replaced Twilio) | ✅ |
| **Full Flutter UI** | Complete StatefulWidget screens: Home, Patient List/Reg/Detail, Vitals, SBAR, Voice, Sync, Settings, Emergency | ✅ |
| **IndicTrans2 Docker** | Self-hosted STT/TTS at localhost:8000 — both backend and Flutter | ✅ |
| **MiniMax AI Brain** | FastAPI `/risk` and `/sbar` routes wired to MiniMax API | ✅ |
| **GPS Auto-Tag** | `geolocator` package in Flutter → lat/long on every vitals record | ✅ |
| **Telegram Service** | Flutter `TelegramService` for in-app voice forwarding | ✅ |
| **CORS/Android Emulator** | FastAPI CORS for `http://10.0.2.2:3000` (Android emulator host) | ✅ |
| **On-device ML deferred** | Phase 4: quantized XGBoost for offline inference | 🔜 |

---

## Phase 2 Roadmap (Legacy)

| Item | Description |
|------|-------------|
| **Real ABDM integration** | Live NHA API calls for HPR verification, ABHA auth |
| **ML risk scoring** | Train Gradient Boosting model on Phase 1 historical outcomes |
| **Live Bhashini STT/TTS** | Replace stubs with Bhashini API v3 |
| **Voice message transcription** | ElevenLabs or Bhashini STT for IVR recordings |
| **CHW push notifications** | FCM or Twilio Notify for HIGH/EMERGENCY alerts |
| **FHIR Server sync** | Replace Supabase with real FHIR R4 server as sync target |

---

## Unit Economics (India Context)

| Metric | Value |
|--------|-------|
| ASHAs in India | ~1 million |
| Pregnant women per ASHA per year | ~20–30 |
| Total addressable pregnancies | ~20–30 million/year |
| Government CHW app budget (per state) | ₹50–200 lakh/year |
| Current market gap | No offline-first, AI-enabled solution |

**Path to revenue**: State government contracts (NHM/MNH programs), PPP with healthcare NGOs, ABDM integration partnerships.

---

## The Ask

| What We Need | What We Offer |
|--------------|---------------|
| **Pilot partners** — PHCs in Karnataka or Andhra Pradesh | Open-source stack, FHIR-native, built for low-resource deployment |
| **Bhashini API access** — for STT/TTS integration | Co-development credit, preferred pricing post-pilot |
| **ABDM sandbox credentials** — NHA API access | India national health stack integration expertise |
| **Funding (₹50L–₹1Cr)** — 6-month runway for Phase 2 | 10x reduction in maternal mortality tracking gaps |

---

## Team

**Product & Engineering**: [Your name + background]  
**Clinical Protocols**: Maternal health expert (OBGYN or public health)  
**UX Research**: ASHA-facing research in rural Karnataka

---

## Contact

**Name**: [Your name]  
**Email**: [your@email.com]  
**GitHub**: github.com/syed/AAVISHKAR-PRAVAH  
**LinkedIn**: linkedin.com/in/[your-handle]

---

> **Last updated**: 2026-05-11 — Phase 1 complete, preparing for Round 1 pitch