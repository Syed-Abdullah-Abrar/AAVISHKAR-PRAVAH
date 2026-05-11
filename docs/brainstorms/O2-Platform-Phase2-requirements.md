# O2 Platform — Phase 2 Requirements

**Date:** 2026-05-11  
**Phase:** 2 (Pilot-Ready Integration)  
**Status:** Brainstormed — ready for planning  
**Based on:** `docs/ideation/O2-Platform-Phase2-ideation.md`

---

## Overview

Phase 2 upgrades Phase 1 mocks/stubs to live integrations, adds ML-based risk scoring in shadow mode, builds the voice transcription pipeline, and introduces the PHC supervisor dashboard for pilot operations.

**Principle:** No speculative complexity. Every feature must work offline-first or degrade gracefully. Live API calls are reserved for operations that genuinely require network (ABDM verification, Bhashini STT/TTS).

---

## Feature 1: Live ABDM / NHA API Integration

### What

Replace the Mod 97 checksum stub in `abdm_service.dart` with live NHA API calls. Patient ABHA IDs are verified against the Ayushman Bharat Health Account system before registration completes.

### User Flow

1. CHW enters patient's ABHA number during registration
2. App calls NHA API (via backend proxy to protect credentials)
3. API returns: verified/not found/error
4. If verified → patient linked to national health record
5. If not found → CHW prompted to correct or skip ABHA linking
6. If error → retry with exponential backoff; patient can proceed without ABHA link

### Key Decisions

| Decision | Choice | Rationale |
|----------|--------|----------|
| Call from backend, not app | NHA API proxied through FastAPI | Protects API keys; easier credential management |
| Abort or warn on failure? | Warn + allow skip | Network failures shouldn't block patient registration |
| Offline behavior | Cache last-known ABHA verification result for 24h | Handle brief connectivity loss |

### Scope Boundaries

- **In scope:** ABHA ID verification, HPR (Health Professional Registry) lookup for CHW
- **Deferred:** Full ABDM consent flow, HIU (Health Information User) certification, national health record retrieval

### Success Criteria

- ≥95% of patient registrations complete ABHA verification within 10 seconds on 3G
- ≥99% uptime for ABDM API proxy (handled by cloud provider SLA)

---

## Feature 2: Live Bhashini STT/TTS Integration

### What

Replace stubs in `lib/core/constants.dart` (`sttLanguageCode`, `ttsLanguageCode`) with live Bhashini API v3 calls. CHWs and patients use voice input/output in Kannada and Hindi.

### User Flows

**CHW Voice Input (STT):**
1. CHW taps microphone on patient form
2. App streams audio to Bhashini STT API (chunked for stability)
3. Bhashini returns text in selected language
4. App fills form field with transcribed text

**Patient Voice Output (TTS):**
1. App fetches content (risk summary, follow-up instructions)
2. Sends to Bhashini TTS API in patient's preferred language
3. Receives audio stream
4. Plays via device speaker

### Key Decisions

| Decision | Choice | Rationale |
|---------|--------|-----------|
| Streaming or recording-then-upload? | Chunked streaming for STT, pre-recorded TTS | Rural bandwidth varies; chunks recover from failure |
| Fallback when offline | Show text-only; queue TTS requests | Bhashini requires network; no offline TTS possible |
| Language selection | Per-user preference stored in Supabase, synced | CHW selects Kannada or Hindi at first launch |

### Scope Boundaries

- **In scope:** STT for CHW form entry, TTS for patient-facing instructions
- **Deferred:** Bhashini Indic-2 Indic translation (Kannada↔Hindi direct only)

### Success Criteria

- STT accuracy ≥85% for Kannada and Hindi (Bhashini benchmark)
- TTS latency ≤3s for standard messages on 3G

---

## Feature 3: Auto-Schedule Follow-Up from Risk Level

### What

When `/risk` returns a triage result, the app automatically creates a follow-up visit entry in the CHW's schedule — no manual date entry required.

### User Flow

1. CHW submits vitals → `/risk` returns HIGH
2. App shows risk result + auto-creates follow-up in 24h
3. CHW sees "Follow-up scheduled: tomorrow, 9 AM" banner
4. CHW can accept, modify, or cancel the auto-scheduled visit
5. Scheduled visit syncs to Supabase with PHC visibility

### Key Decisions

| Decision | Choice | Rationale |
|---------|--------|-----------|
| Default intervals | EMERGENCY → immediate, HIGH → 24h, MEDIUM → 48h, LOW → 7 days | From WHO maternal health protocols |
| CHW override | Always allowed | CHW has local knowledge; don't hard-block |
| Sync | Follows same WorkManager WiFi + charging constraints | No new network demand |

### Success Criteria

- ≥80% of HIGH/EMERGENCY cases have a scheduled follow-up within the protocol interval
- Zero additional taps required from CHW after submitting vitals

---

## Feature 4: IVR Voice Transcription Pipeline

### What

Twilio-recorded voice messages from feature-phone patients are transcribed via Bhashini STT. Transcription enables: (a) WhatsApp text summary to CHW, (b) searchable clinical notes, (c) keyword alerting.

### Data Flow

```
Patient voice message (Twilio recording)
    ↓
IVR Backend receives recording URL
    ↓
Audio pushed to Bhashini STT API
    ↓
Transcript returned in patient's language
    ↓
Transcript stored in Supabase (searchable notes)
    ↓
WhatsApp text message sent to CHW (short summary)
    ↓
If emergency keywords detected → emergency alert triggered
```

### Key Decisions

| Decision | Choice | Rationale |
|---------|--------|-----------|
| Transcription language detection | Detect from patient's ABHA record language preference | No ambiguity |
| Chunking for long recordings | >60s audio split before sending to Bhashini | Bhashini has 60s limit |
| Fallback on STT failure | Send audio-only WhatsApp to CHW (Phase 1 behavior) | Degrade gracefully |

### Success Criteria

- ≥80% of voice messages transcribed successfully
- Emergency keywords detected in ≥95% of messages containing them

---

## Feature 5: Multi-Recipient Emergency Alert

### What

When `/risk` returns EMERGENCY, the alert is simultaneously sent to: CHW (WhatsApp), PHC Supervisor (SMS + app push), patient's emergency contact (SMS).

### User Flow

1. Vitals submitted → `/risk` returns EMERGENCY
2. App triggers alert job (queued for offline resilience)
3. Alert sent to all three recipients simultaneously
4. Each recipient receives appropriate format:
   - CHW: WhatsApp text + deep link to patient record
   - Supervisor: SMS + app notification badge
   - Emergency contact: SMS with patient ID + nearest PHC address

### Key Decisions

| Decision | Choice | Rationale |
|---------|--------|-----------|
| Recipients | CHW, PHC supervisor (from PHC hierarchy), emergency contact (from patient record) | Configurable; supervisor comes from `phc_hierarchy` |
| Offline behavior | Queue alert job; deliver when WorkManager sync fires | Works offline; no new network dependency |
| Delivery confirmation | Log delivery status per recipient in Supabase | Audit trail for clinical safety |

### Success Criteria

- All three recipients receive alert within 60 seconds of EMERGENCY detection
- ≥99% delivery success rate to at least one channel per recipient

---

## Feature 6: PHC Supervisor Dashboard

### What

A web-based dashboard (Flutter web or simple HTML/JS) showing PHC-level aggregate data: HIGH/EMERGENCY patient count, SBAR generation rate, CHW activity, referral tracking.

### Dashboard Views

| View | Metrics |
|------|---------|
| Risk Overview | HIGH/EMERGENCY count by village, trend over 7/30 days |
| CHW Activity | Visits completed today, SBARs generated, patients without follow-up |
| Referral Tracker | SBARs sent to referral facilities, acknowledgment status |
| IVR Volume | Missed calls this week, transcriptions completed, unresolved messages |

### Key Decisions

| Decision | Choice | Rationale |
|---------|--------|-----------|
| Technology | Flutter web (reuses Flutter codebase) or simple React/HTML | Pilot scope; no heavy framework needed |
| Authentication | Supabase Auth with supervisor role | Uses existing auth infrastructure |
| Data access | Supabase RLS — supervisors see only their PHC's data | Same PHC-based isolation as CHW app |

### Success Criteria

- Supervisor can see HIGH/EMERGENCY patient list within 2 taps from dashboard landing
- Data refreshes within 30 seconds of sync completing

---

## Feature 7: Shadow-Mode ML Risk Scoring

### What

A quantized XGBoost model trained on Phase 1 historical data runs alongside the rule-based WHO thresholds. ML score is displayed but not used for clinical decisions in Phase 2 — shadow mode only.

### How It Works

```
Vitals submitted
    ↓
Rule-based /risk returns → shown to CHW (deterministic, explainable)
    ↓
ML model score computed (shadow)
    ↓
ML score logged to Supabase alongside rule-based result
    ↓
Outcome data (delivery safe? referral followed?) retroactively labels training set
```

### Key Decisions

| Decision | Choice | Rationale |
|---------|--------|-----------|
| Model type | Quantized XGBoost | Lightweight, runs on modest hardware; interpretable |
| Training data | Phase 1 vitals + outcome labels from clinical contacts | Outcome labels require manual entry or referral follow-up records |
| When to activate | After ≥500 patient-months of labeled data | Industry benchmark for quantized GB |
| Offline behavior | Model runs locally on device (on-device inference) | No network call; protects patient privacy |

### Success Criteria

- ML model achieves ≥70% agreement with rule-based triage on validation set
- Model retraining triggered automatically when 200 new labeled outcomes accumulate

---

## Feature 8: GPS Auto-Tag Visit Logs

### What

When CHW opens a patient record in the field, the app automatically captures GPS coordinates and timestamps the visit — creating an auditable home visit trail for NHM (National Health Mission) compliance.

### User Flow

1. CHW opens patient record (triggers location capture)
2. App captures GPS coordinates (accuracy ±30m acceptable; ±5m preferred)
3. Coordinates stored in `clinical_contact_logs.visit_location`
4. Sync uploads to Supabase on next WorkManager window
5. Supervisor dashboard shows visit map view

### Key Decisions

| Decision | Choice | Rationale |
|---------|--------|-----------|
| Permission | Request on first launch; explain value clearly | NHM compliance + patient safety |
| Offline | Store coordinates locally; sync later | Works without network |
| Accuracy fallback | If GPS unavailable, mark as "location unavailable" | Don't block clinical workflow |

### Success Criteria

- ≥90% of clinical contacts have valid GPS coordinates
- Supervisor can view visit locations on map within dashboard

---

## Integration Summary

| Feature | Live API Called | Offline Capable | Priority |
|---------|----------------|-----------------|---------|
| ABDM/NHA Verification | Yes (NHA API) | Partial (24h cache) | P1 |
| Bhashini STT/TTS | Yes (Bhashini v3) | STT partial, TTS no | P1 |
| Auto-Schedule | No | Yes | P1 |
| IVR Transcription | Yes (Bhashini STT) | No | P2 |
| Emergency Alert | No (WhatsApp/SMS) | Queued | P1 |
| Supervisor Dashboard | No | Yes | P2 |
| Shadow ML | No (local inference) | Yes | P2 |
| GPS Visit Logs | No | Yes | P1 |

---

## Dependencies

- **Feature 1** (ABDM): Requires NHA sandbox API credentials, data sharing agreement with NHA
- **Feature 2** (Bhashini): Requires Bhashini API key (self-service at https://bhashini.gov.in)
- **Feature 7** (ML): Requires Phase 1 outcome labels — CHW or supervisor must mark referral follow-up status
- **Feature 8** (GPS): Requires Android location permission; pilot CHWs must consent

---

## Out of Scope for Phase 2

- Full ABDM HIU certification
- Indic-2 translation (Kannada↔Hindi)
- Zero-phone patient workflow
- 50k concurrent CHW scale testing
- Smart reply for CHW follow-up messages