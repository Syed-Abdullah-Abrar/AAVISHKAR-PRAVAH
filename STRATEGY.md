# O2 Platform — Product Strategy

**Date:** 2026-05-11  
**Phase:** 1 (Foundation) + Phase 2 (Pilot-Ready Integration)  
**Version:** 2.0

---

## 1. Target Problem

Rural maternal healthcare in India collapses at the **last-mile connection** between pregnant women and the health system. Community Health Workers (CHWs / ASHAs) are the primary link — but:

- Women in low-connectivity regions cannot reach their CHW between visits
- CHWs lose visibility into patient risk between scheduled appointments
- Clinical decisions require connectivity the field doesn't have
- Low-literacy patients cannot use app-based interfaces
- Patient data is siloed across systems, preventing continuity of care

> **O₂ (Oxygen) is essential for human life. O2 is the essential lifeline for rural maternal healthcare.**

---

## 2. Product Concept

O2 is an **offline-first maternal healthcare monitoring platform** with two distinct user surfaces:

### Surface A: CHW Interface (Flutter App)
A Flutter mobile app used by Community Health Workers to register patients, record vitals, receive AI-driven risk scores, generate SBAR clinical handover documents, and manage their patient panel — fully offline, with opportunistic cloud sync.

### Surface B: Patient Communication Layer (IVR + WhatsApp)
A zero-cost, zero-app communication bridge for pregnant women with basic feature phones. A missed call triggers a free callback, she speaks her concern, and her CHW receives it as a WhatsApp voice message. No smartphone, no data plan, no literacy required on the patient's side.

**The two surfaces are complementary:** the IVR layer brings patients into the O2 ecosystem who would otherwise never reach the CHW app. The CHW app manages the clinical response. Together they close the feedback loop between rural patients and the healthcare system.

---

## 3. Target Users

### Primary User: Community Health Worker (CHW / ASHA)
- Female, age 25–45, rural India
- Has a mid-range Android smartphone with WhatsApp
- Has completed government-mandated ASHA training
- Primary language: Kannada (Karnataka) or Hindi (Uttar Pradesh)
- Uses O2 app daily during home visit rounds
- Has low-to-moderate digital literacy

### Secondary User: Pregnant Woman / Rural Family Member
- Age 18–35, pregnant or new mother
- Has a basic feature phone (no smartphone, no internet data)
- May be semi-literate or illiterate
- Registered via ABHA; phone number linked to her health record
- Cannot afford airtime charges; needs zero-cost communication

### Oversight User: PHC Supervisor / Block Health Officer
- Monitors CHW activity across a Primary Health Centre
- Receives emergency escalations
- Reviews aggregate maternal health data
- **New in Phase 2:** Web dashboard for PHC-level aggregate view

---

## 4. Tech Stack

| Component | Technology | Phase |
|---|---|---|
| **CHW Mobile App** | Flutter v3.22+, Brick offline-first ORM, sqflite, SQLCipher, WorkManager, FHIR R4 | 1+ |
| **Cloud Backend** | Supabase (PostgreSQL + Auth + Realtime) | 1+ |
| **Voice I/O (CHW)** | Bhashini plugin — STT/TTS in Kannada and Hindi | 2 (live), 1 (stub) |
| **AI Inference** | Python FastAPI — rule-based (P1), shadow ML (P2), on-device quantized (P3) | 1+ |
| **Patient IVR Layer** | Twilio / Exotel — missed call, callback, voice recording, WhatsApp Business API | 1+ |
| **Ecosystem** | ABDM — data contract defined; live API integration in Phase 2 | 2 |
| **ML Risk Model** | Quantized XGBoost — shadow mode in Phase 2, on-device in Phase 3 | 2 |

### External APIs

| API | Base URL | Auth | Rate Limit | Phase |
|-----|----------|------|------------|-------|
| **NHA / ABDM** | `https://.abdm.gov.in/api/v1` | HMAC-SHA256 | 100/min | 2 |
| **Bhashini STT/TTS** | `https://meity-auth.ulcacetech.in/api/v3` | JWT Bearer | 60/min STT | 2 |
| **Twilio SMS/WhatsApp** | `https://api.twilio.com/2010-04-01` | Basic Auth | Varies | 1+ |
| **XGBoost ONNX** | Local inference | None | N/A | 2 |
| **Firebase FCM** | `https://fcm.googleapis.com/fcm/send` | FCM server key | Varies | 2 |

---

## 5. Core Product Tracks

### Track 1: Offline-First CHW App
**Phase 1 Goal:** CHW can perform all critical tasks without connectivity.

- Brick models defined in **FHIR R4 natively** — patient, vitals, observations stored as FHIR resources in local sqflite
- Local SQLite via SQLCipher (AES-256) with key stored in Android Keystore — no plaintext PHI on disk
- WorkManager background sync triggers only on WiFi + charging — respects solar-powered device patterns
- Conflict resolution: Last-Write-Wins with clinical-hierarchy override (vitals from a PHC visit override self-reported vitals)
- FHIR-compliant JSON serialization for all Supabase sync operations

**Phase 2 additions:**
- GPS auto-tag visit logs as NHM compliance proof
- GPS coordinates captured on clinical contact, stored in `clinical_contact_logs.visit_location`
- Auto-schedule follow-up visits from risk level (EMERGENCY → immediate, HIGH → 24h, MEDIUM → 48h, LOW → 7 days)

---

### Track 2: Voice-First CHW Interaction
**Phase 1 Goal:** CHW can input and review patient data via voice stubs.

- Bhashini STT/TTS stubs in `constants.dart` — placeholder language codes for Kannada/Hindi
- Voice widget scaffolded for future STT/TTS integration

**Phase 2 additions (live Bhashini API):**
- Bhashini STT for symptom input — CHW speaks in Kannada or Hindi, transcribed to structured vitals
- Bhashini TTS for risk score and SBAR playback — CHW listens to AI-generated summary
- Voice is primary UI; screen is secondary reveal for confirmations
- Radio call-and-response confirmation: STT transcription read back via TTS before commit

---

### Track 3: Clinical AI & Decision Support
**Phase 1 Goal:** Traffic-light triage via rule-based WHO thresholds; SBAR via LLM.

- On-device rule engine scoring vitals against WHO maternal health thresholds
- Risk output: **Traffic-light triage** — Emergency / High / Medium / Low
- SBAR generated by LLM (FastAPI `/sbar` endpoint) as FHIR DocumentReference
- SBAR generation follows strict JSON schema — no free-text injection

**Phase 2 additions (shadow ML):**
- Quantized XGBoost model trained on Phase 1 historical outcomes
- ML score computed alongside rule-based score (shadow mode — displayed, not used for decisions)
- Model runs locally on device for offline inference
- Sustained-deviation alerts: 3+ elevated BP readings in 48h triggers HIGH regardless of single reading
- Missed-call frequency as risk signal: 3+ missed calls in 7 days → auto-flag for outreach

---

### Track 4: Patient IVR Communication Layer
**Phase 1 Goal:** Missed call → free callback → WhatsApp voice note to CHW.

- **Missed Call → Free Callback → Voice Message** flow:
  1. Patient gives missed call to single national toll-free number
  2. IVR platform detects caller ID, disconnects immediately (no charge to patient)
  3. IVR calls patient back for free
  4. Patient hears IVR greeting in regional language (Bhashini TTS), speaks her concern
  5. Audio recorded and forwarded as WhatsApp voice message to her assigned CHW
  6. CHW listens, opens patient record in O2 app, responds via WhatsApp voice note
- Emergency keyword detection: EN/KN/HI keyword scanning in recorded audio

**Phase 2 additions:**
- IVR voice transcription via Bhashini STT — WhatsApp text summary sent alongside audio
- Transcript stored as searchable clinical note in Supabase
- WhatsApp text summary: short structured message (patient ID + chief complaint + timestamp)
- Emergency keyword detection upgraded from audio filename scan to full STT transcript analysis

---

### Track 5: ABDM Integration (NEW in Phase 2)
**Goal:** Live integration with India's Ayushman Bharat Digital Mission.

- **Phase 1:** Mod 97 checksum validation stub in `abdm_service.dart`
- **Phase 2:**
  - Replace Mod 97 with live NHA API call (ABHA verification endpoint)
  - HPR (Health Professional Registry) lookup to verify CHW credentials
  - ABDM proxy via FastAPI backend (protects API credentials)
  - 24-hour local cache of verification results for offline resilience
  - Warn + allow skip on verification failure (don't block registration)

---

### Track 6: Pilot Operations & Supervisor Visibility (NEW in Phase 2)
**Goal:** PHC supervisors can monitor aggregate health data and CHW activity.

- **PHC Supervisor Dashboard** (Flutter web or simple HTML/JS):
  - HIGH/EMERGENCY patient count by village, 7/30-day trend
  - CHW activity: visits completed, SBARs generated, patients without follow-up
  - Referral tracker: SBARs sent, acknowledgment status
  - IVR volume: missed calls, transcriptions, unresolved messages
- **Multi-recipient emergency alert:**
  - CHW → WhatsApp (Phase 1)
  - PHC Supervisor → SMS + app push (Phase 2)
  - Patient's emergency contact → SMS with patient ID + nearest PHC address (Phase 2)
- **GPS visit map:** Supervisor can view visit locations on a map

---

## 6. Key Metrics

| Metric | Phase 1 Target | Phase 2 Target |
|--------|---------------|----------------|
| App launches offline | 100% | 100% |
| Vitals sync success rate | ≥95% on WiFi | ≥95% |
| Risk triage response time | <2s (local) | <2s (local) |
| ABDM verification success | N/A | ≥95% on 3G |
| STT accuracy (Kannada/Hindi) | N/A | ≥85% |
| Emergency alert delivery | N/A | All 3 recipients within 60s |
| GPS coverage on visits | N/A | ≥90% of clinical contacts |
| ML model accuracy (vs rule-based) | N/A | ≥70% agreement |
| Supervisor dashboard availability | N/A | ≤2 taps to HIGH list |

---

## 7. What We're Not Building (Yet)

- On-device quantized LLM (Phase 3)
- Full ABDM HIU certification (Phase 3+)
- Indic-2 translation (Kannada↔Hindi) — Bhashini supports direct only
- Zero-phone patient workflow (separate track)
- 50k concurrent CHW scale testing (government mandate scenario)
- Smart reply for CHW WhatsApp follow-up messages

---

## 8. Phase 2 Success Criteria

1. **Pilot partner PHC operational** — ≥3 CHWs actively using the app in Karnataka
2. **No ABDM stub** — All patient registrations verified against live NHA API
3. **Voice pipeline live** — Bhashini STT/TTS replacing all stubs in Phase 1
4. **Supervisor on dashboard** — PHC supervisor accessing aggregate data within 1 week of pilot start
5. **ML shadow running** — Model producing scores alongside rule-based in production
6. **GPS compliance proof** — Visit logs with GPS coordinates accepted by NHM program officers

---

*Last updated: 2026-05-11 — Phase 2 strategy added*
