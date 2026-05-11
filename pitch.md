# O2 Platform — Pitch Deck

> Live document — update before each pitch session.

---

## The Problem

**Maternal mortality in rural India is preventable.**

Every day, ~50 women die from pregnancy-related causes in India. The majority of these deaths occur in low-resource, remote areas where:

- ASHAs (Community Health Workers) lack real-time clinical decision support
- Patients cannot reach hospitals without early warning of complications
- Internet connectivity is unreliable or absent
- India's own health infrastructure (ABDM/ABHA) is inaccessible offline

**Current state**: CHWs do paper-based tracking, Excel sheets, or apps that fail when offline — leaving the most vulnerable women unmonitored.

---

## Our Solution

**O2 Platform** — an offline-first mobile app for ASHA workers that works without internet, integrates with India's national health stack, and provides AI-driven clinical decision support.

### What It Does

```
Patient + Vitals → Risk Assessment (WHO thresholds)
                → SBAR Clinical Summary (LLM)
                → Emergency Alert
                → ABHA/ABDM Health Record

Feature-phone patient → Missed call IVR → CHW WhatsApp voice note
```

### Who It's For

- **Primary**: ASHA workers in rural Karnataka / Andhra Pradesh
- **End beneficiaries**: Pregnant women in PHC catchment areas
- **Secondary**: PHC supervisors, district health officers

---

## Key Features

| Feature | How It Works |
|---------|-------------|
| **Offline-First** | SQLCipher-encrypted local DB; WorkManager sync on WiFi + Charging |
| **Clinical Decision Support** | Traffic-light triage (Low / Medium / High / Emergency) from vitals |
| **AI Summaries** | SBAR reports generated via LLM from patient history |
| **ABDM Integration** | ABHA ID validation (Mod 97 checksum), HPR/HFR linking mock |
| **Voice Interface** | Bhashini STT/TTS for low-literacy users (stub in Phase 1) |
| **IVR for Feature Phones** | Missed call → free callback → voice recording → WhatsApp to CHW |
| **PHC-Based Access Control** | Supabase RLS enforces data isolation by catchment area |

---

## The Technology

- **Flutter** — cross-platform, works on low-end Android devices
- **Brick ORM + SQLCipher** — offline-first with AES-256 encryption at rest
- **WorkManager** — background sync with network/battery constraints
- **FHIR R4** — canonical format from app to AI backend
- **FastAPI** — risk assessment + SBAR generation endpoints
- **Twilio + WhatsApp** — IVR voice message forwarding
- **Supabase** — PostgreSQL with PHC-based Row Level Security

---

## Traction & Progress

| Milestone | Status |
|-----------|--------|
| Phase 1 MVP (hackathon) | ✅ Implemented — 6 units complete |
| FHIR R4 native models | ✅ |
| Offline-first architecture | ✅ |
| Traffic-light triage | ✅ |
| IVR missed-call flow | ✅ |
| ABDM mock (Mod 97) | ✅ |
| SBAR LLM generation | ✅ |

---

## Phase 2 Roadmap

1. **Real ABDM integration** — live NHA API for HPR/ABHA verification
2. **ML-based risk scoring** — trained on Phase 1 historical data
3. **Live Bhashini STT/TTS** — replace stubs
4. **Voice message transcription** — ElevenLabs/Bhashini STT for IVR
5. **CHW push notifications** — FCM or Twilio Notify

---

## The Ask

- **What we need**: Pilot partners (PHCs in Karnataka), Bhashini API access, ABDM sandbox credentials
- **What we offer**: Open-source stack, FHIR-native architecture, built for low-resource deployment

---

## Team

- ASHA-facing UX research
- Clinical protocol design by maternal health experts
- Engineering: Flutter + FastAPI + Supabase

---

## Contact

[Your name]  
[Your email]  
[GitHub repo link]

---

> **Note**: Update this before each pitch with latest pilot interest, any metrics from user testing, and Phase 2 progress.