# O2 Platform — Product Strategy

**Date:** 2026-05-11  
**Phase:** 1 (Foundation — 24-hour Hackathon MVP)  
**Version:** 1.0

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

---

## 4. Tech Stack

| Component | Technology |
|---|---|
| **CHW Mobile App** | Flutter v3.22+, Brick offline-first ORM, sqflite, SQLCipher, WorkManager, FHIR R4 |
| **Cloud Backend** | Supabase (PostgreSQL + Auth + Realtime) |
| **Voice I/O (CHW)** | Bhashini plugin — STT/TTS in Kannada and Hindi |
| **AI Inference** | Python FastAPI (mock endpoints Phase 1); quantized on-device ML model (Phase 2+) |
| **Patient IVR Layer** | Twilio / Exotel — missed call, callback, voice recording, WhatsApp Business API |
| **Ecosystem** | ABDM — data contract defined; live API integration deferred past Phase 1 |

---

## 5. Core Product Tracks

### Track 1: Offline-First CHW App
**Goal:** CHW can perform all critical tasks without connectivity.

- Brick models defined in **FHIR R4 natively** — patient, vitals, observations stored as FHIR resources in local sqflite
- Local SQLite via SQLCipher (AES-256) with key stored in Android Keystore — no plaintext PHI on disk
- WorkManager background sync triggers only on WiFi + charging — respects solar-powered device patterns
- Conflict resolution: Last-Write-Wins with clinical-hierarchy override (vitals from a PHC visit override self-reported vitals)
- FHIR-compliant JSON serialization for all Supabase sync operations

**Survivor ideas incorporated:** Zero-connectivity-always (Idea 29), FHIR-as-local-schema (Idea 13), Automated conflict resolution (Idea 12), Device-bound identity (Idea 35), Aviation black-box audit trail (Idea 25)

### Track 2: Voice-First CHW Interaction
**Goal:** CHW can input and review patient data entirely via voice in Kannada/Hindi.

- Bhashini STT for symptom input — CHW speaks in Kannada or Hindi, transcribed to structured vitals
- Bhashini TTS for risk score and SBAR playback — CHW listens to AI-generated summary without reading
- Voice is primary UI; screen is secondary reveal for confirmations
- Radio call-and-response confirmation: STT transcription read back via TTS before commit
- GPS check-in at vitals entry — visit authenticity verification

**Survivor ideas incorporated:** Voice-as-primary-UI (Idea 14), Radio call-and-response confirmation (Idea 28), Pre-cached TTS (Idea 10)

### Track 3: Clinical AI & Decision Support
**Goal:** AI-driven risk assessment runs fully on-device (no connectivity required for clinical decisions).

- On-device quantized ML model (Gradient Boosting / Random Forest equivalent) for risk scoring
- Risk output: **Traffic-light triage** — Red (Emergency), Yellow (Medium Risk), Green (Low Risk) — mapped to ASHA training protocols
- Risk score is a **triage flag, not a diagnosis** — reduces regulatory surface; framed as "patients needing escalated care"
- SBAR document generated by LLM (Phase 1: cloud API; Phase 2: on-device quantized LLM) as FHIR DocumentReference
- SBAR generation follows strict schema — no free-text injection; structured JSON output only

**Survivor ideas incorporated:** On-device ML inference (Idea 32), Traffic-light triage (Idea 27), Risk as triage flag (Idea 15), SBAR as FHIR DocumentReference (Idea 21)

### Track 4: Patient IVR Communication Layer
**Goal:** Feature-phone patients can reach their CHW with zero airtime cost and no app required.

- **Missed Call → Free Callback → Voice Message** flow:
  1. Patient gives missed call to single national toll-free number
  2. IVR platform detects caller ID, disconnects immediately (no charge to patient)
  3. IVR calls patient back for free
  4. Patient hears IVR greeting in regional language (ElevenLabs TTS), speaks her concern
  5. Audio recorded and forwarded as WhatsApp voice message to her assigned CHW
  6. CHW listens, opens patient record in O2 app, responds via WhatsApp voice note
- Single national/regional IVR number with caller ID routing to correct CHW pool
- Emergency keyword detection: real-time speech analysis during recording detects "blood", "pain", "unconscious" (Kannada/Hindi equivalents) → triggers immediate CHW call and PHC escalation
- Patient identified via caller ID → ABHA mapping (no input required from patient)

**This track is the new scope from the Phase 1 brainstorming session.**

### Track 5: Security, Privacy & Compliance
**Goal:** PHI is protected at rest and in transit; patient data is never accessible after device loss.

- SQLCipher AES-256 encryption at rest — key stored in Android Keystore (hardware-backed)
- Zero-trust device model: device treated as potentially lost/stolen — remote wipe capability required
- Append-only encrypted audit log (aviation black-box pattern) — all clinical interactions logged separately from main database
- Supabase RLS policies: CHW can only read/write patients registered to their assigned PHC
- ABDM compliance: ABHA ID validation in schema; API contracts documented, live calls deferred to Phase 2
- DPDP Act compliance: patient consent captured at ABHA registration; data retention policy defined

**Survivor ideas incorporated:** Zero-trust device model (Idea 30), Aviation black-box audit trail (Idea 25), Cloud-backed key management service (Idea 17), ABDM as compliance tax (Idea 16)

### Track 6: Supabase Cloud Backend
**Goal:** Supabase provides auth, PostgreSQL storage, and opportunistic sync with full RLS enforcement.

- PostgreSQL schema: patients, vitals_logs, clinical_contact_logs, chw_assignments, phc_hierarchy
- RLS policies auto-generated from PHC hierarchy table — CHW reassignment automatically propagates to RLS
- Brick sync adapter translates between local FHIR store and Supabase PostgreSQL
- Auth: Supabase Auth with phone number (CHW) — no password, OTP-based
- Realtime: optional — CHW panel view can receive push notifications when patient contacts via IVR

**Survivor ideas incorporated:** Automated RLS policy generation from PHC hierarchy (Idea 9), FHIR schema as leverage for ecosystem (Idea 18)

---

## 6. What O2 Is NOT

- A general telemedicine platform — O2 is maternal-health-specific
- A cloud-dependent app — clinical decisions work fully offline
- A patient-facing smartphone app — patients use feature phones via IVR
- A replacement for ASHA training — O2 is a decision-support tool, not a training substitute
- A real ABDM integration in Phase 1 — API contracts are documented, live calls are stubbed

---

## 7. Phase 1 Scope Boundaries

### In Scope (24-hour Hackathon MVP)

| Deliverable | Description |
|---|---|
| Flutter CHW app | Offline-first app with Brick + FHIR models, SQLCipher encryption, WorkManager sync |
| Supabase schema | PostgreSQL tables with RLS policies for patients, vitals_logs, chw_assignments |
| FHIR serialization | Helper to serialize patient data to FHIR R4 JSON |
| Voice widget | Bhashini STT/TTS widget for symptom input and TTS playback in Kannada/Hindi |
| Risk assessment API | Python FastAPI mock endpoint — receives vitals, returns Low/Medium/High/Emergency |
| SBAR generation API | Python FastAPI LLM endpoint — receives longitudinal data, returns SBAR JSON |
| IVR backend stubs | Patient Lookup Service API (caller ID → ABHA → CHW mapping) |
| IVR mock integration | Dart service with ABDM-compliant mock REST calls for HPR/HFR/ABHA verification |

### Deferred Past Phase 1

- On-device quantized ML model (cloud AI used in Phase 1)
- WhatsApp Business API official provisioning and ABDM compliance review
- Real Twilio/Exotel IVR integration (mocked for MVP)
- Multi-language beyond Kannada and Hindi
- GPS check-in enforcement
- Two-way real-time voice call between patient and CHW

---

## 8. Success Metrics

| Metric | Phase 1 Target |
|---|---|
| CHW app loads and functions offline | 100% functionality without network |
| Patient registered and vitals recorded | Full CRUD cycle in < 5 minutes |
| Risk score generated offline | Score returned from local model in < 2 seconds |
| SBAR document generated | Structured JSON output in < 5 seconds |
| IVR callback delivered | < 90 seconds missed-call-to-CHW-notification |
| Supabase sync | Data syncs when WiFi + charging |
| SQLCipher encryption | AES-256 at rest, key in Keystore |
| RLS policy | CHW sees only their PHC-assigned patients |

---

## 9. Key Strategic Decisions Resolved

| Decision | Resolution | Rationale |
|---|---|---|
| Local schema design | FHIR R4 native in Brick models | Eliminates translation layers; FHIR is the storage format and wire format |
| Cloud AI vs on-device AI | Cloud AI for Phase 1, on-device for Phase 2 | Hackathon timeline requires cloud AI MVP; on-device is the right long-term answer |
| Voice UX paradigm | Voice-first for CHW; voice-only for patient | Low-literacy populations; voice is the natural interface |
| ABDM integration | Data contract only in Phase 1 | Real API access uncertain; document contracts and stub calls |
| IVR communication | Single national toll-free number, caller ID routing | Simplest telco partnership; caller ID mapping handles routing |
| Conflict resolution | Last-Write-Wins + clinical hierarchy override | CHWs cannot resolve merge conflicts manually; automated resolution required |

---

## 10. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Twilio/Exotel IVR access unavailable during hackathon | High | Use mock IVR server; document real integration contracts |
| Supabase RLS misconfiguration causes data leakage | Medium | Write RLS test suite before deployment; test CHW cross-access denial |
| SQLCipher key loss on device reset | Medium | Cloud-backed key recovery service (Phase 2 design) |
| Bhashini STT accuracy in rural dialects | High | Radio call-and-response confirmation; fallback to typed input |
| ABDM APIs not available in hackathon window | High | Treat ABDM as data contract only; stub all calls |
| Patient caller ID unreliable on GSM network | Low-Medium | Fallback: patient states name after callback |

---

*Generated by ce-ideate + ce-brainstorm (O2 Platform, Phase 1)*
