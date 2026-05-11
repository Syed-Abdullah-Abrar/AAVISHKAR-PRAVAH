# O2 Platform Phase 2 — Pilot-Ready Integration Plan

**Date:** 2026-05-11  
**Phase:** 2  
**Status:** `active`  
**Type:** `feat`  
**Origin:** `docs/brainstorms/O2-Platform-Phase2-requirements.md`, `STRATEGY.md`

---

## Problem Frame

Phase 1 delivered a functional MVP with working stubs and mocks. Phase 2 upgrades those stubs to live APIs (ABDM NHA, Bhashini), adds the IVR transcription pipeline, multi-recipient emergency alerts, GPS visit logs, shadow ML risk scoring, and the PHC supervisor dashboard.

---

## Success Criteria

| Metric | Target |
|--------|--------|
| ABDM verification success (live NHA API) | ≥95% on 3G |
| STT accuracy (Kannada/Hindi) | ≥85% |
| Emergency alert delivery | All 3 recipients within 60s |
| GPS coverage on visits | ≥90% of clinical contacts |
| ML model vs rule-based agreement | ≥70% |

---

## High-Level Technical Design

```
Patient voice message (Twilio recording URL)
    ↓
IVR Backend: audio → Bhashini STT → transcript
    ↓
Transcript → Supabase (searchable notes) + WhatsApp text to CHW
    ↓
If emergency keywords → multi-recipient alert (CHW + supervisor + emergency contact)
    ↓
Meanwhile: FastAPI /risk runs rule-based + ML shadow → both logged

GPS auto-tag: clinical_contact_logs.visit_location = {lat, lng, accuracy, timestamp}
    ↓
Supervisor Dashboard: reads from Supabase → aggregate view per PHC
```

---

## System-Wide Impact

- **Supabase schema:** New columns in `clinical_contact_logs`, new tables for GPS and alert delivery status
- **FastAPI backend:** New endpoints for ABDM proxy, Bhashini STT/TTS, GPS, multi-recipient alerts
- **IVR backend:** Bhashini STT integration, WhatsApp text message sending
- **Flutter app:** New screens for supervisor dashboard (web or mobile), GPS auto-capture, auto-scheduling
- **No breaking changes** to existing Phase 1 API contracts

---

## Implementation Units

### U1. Live ABDM/NHA API Integration

**Goal:** Replace Mod 97 checksum stub with live NHA API calls for ABHA verification.

**Requirements:** R1 from `docs/brainstorms/O2-Platform-Phase2-requirements.md`

**Dependencies:** None (first unit)

**Files:**
- `apps/o2_app/lib/abdm/abdm_service.dart` — Replace `_validateChecksum()` with NHA API call
- `apps/o2_backend/main.py` — Add ABDM proxy endpoints
- `apps/o2_backend/routers/abdm.py` — New router for ABDM proxy
- `supabase/schema.sql` — Add `abha_verification_cache` table (24h TTL)

**Approach:**
- NHA API requires a signed request with API key. Proxy through FastAPI to keep keys server-side.
- On patient registration, `abdm_service.dart` calls `POST /abdm/verify` on FastAPI backend.
- FastAPI proxies to NHA sandbox URL: `https://.abdm.gov.in/api/v1/discovery/verify-abha`.
- 24h cache in Supabase prevents redundant calls during brief connectivity loss.
- On API failure: log error, return `verification_failed` status, allow CHW to proceed without ABHA link.

**Test scenarios:**
- Happy path: valid ABHA number → verified response with name + DOB
- Invalid ABHA → not_found response with user-friendly message
- Network timeout → fallback to cache or warn-and-proceed
- API error → logged, user notified, registration allowed

---

### U2. Live Bhashini STT/TTS Integration

**Goal:** Replace stubs in `constants.dart` with live Bhashini API v3 calls.

**Requirements:** R2 from requirements doc

**Dependencies:** None (can run parallel with U1)

**Files:**
- `apps/o2_app/lib/core/constants.dart` — Replace stub language codes with live API calls
- `apps/o2_app/lib/services/bhashini_stt_service.dart` — New STT service
- `apps/o2_app/lib/services/bhashini_tts_service.dart` — New TTS service
- `apps/o2_backend/routers/bhashini.py` — New router (STT proxy for IVR backend)
- `ivr_backend/main.py` — Integrate Bhashini STT for voice transcription
- `apps/o2_backend/requirements.txt` — Add `bhashini` package

**Approach:**
- Bhashini API v3 requires JWT token. Backend generates tokens; app and IVR backend call via proxy.
- STT: Chunked upload (60s max per chunk) for stability on 3G.
- TTS: Pre-generate common messages (risk summaries, follow-up instructions) and cache.
- Language detection: Patient's preferred language stored in Supabase; passed with every request.
- Graceful degradation: If Bhashini is down, show text-only UI.

**Test scenarios:**
- STT: Kannada audio → correct Kannada text transcript
- STT: Hindi audio → correct Hindi text transcript
- STT: Network failure → fallback to audio-only (Phase 1 behavior)
- TTS: Risk summary → audio plays in <3s on 3G
- TTS: Offline → show text instead of playing audio

---

### U3. GPS Auto-Tag Visit Logs + Auto-Schedule

**Goal:** Auto-capture GPS on clinical contact + auto-schedule follow-ups from risk level.

**Requirements:** R3, R8 from requirements doc

**Dependencies:** U1 (risk level needed for auto-schedule)

**Files:**
- `apps/o2_app/lib/services/location_service.dart` — New GPS capture service
- `apps/o2_app/lib/repositories/vitals_repository.dart` — Add GPS to clinical contact
- `supabase/schema.sql` — Add `visit_location` column to `clinical_contact_logs`
- `apps/o2_app/lib/screens/patient_detail_screen.dart` — Display auto-scheduled follow-up
- `apps/o2_app/lib/core/router.dart` — Add follow-up confirmation route

**Approach:**
- GPS captured via `geolocator` package on patient record open. Accuracy ±30m acceptable.
- If GPS unavailable, mark `visit_location` as null — do not block clinical workflow.
- Auto-schedule: Risk level from `/risk` → interval map: EMERGENCY=immediate, HIGH=24h, MEDIUM=48h, LOW=7d.
- CHW can accept, modify, or cancel auto-scheduled visit. Override always allowed.
- Scheduled visits stored in Supabase `clinical_contact_logs` with `scheduled_at` field.

**Test scenarios:**
- GPS captured on patient record open → coordinates stored in `clinical_contact_logs.visit_location`
- GPS unavailable → `visit_location` null, clinical workflow continues
- Risk HIGH → follow-up auto-created for next day → CHW sees banner
- CHW modifies auto-schedule → modified date stored
- Works offline → GPS + schedule queued, synced on next WorkManager window

---

### U4. IVR Voice Transcription Pipeline

**Goal:** Transcribe Twilio voice recordings via Bhashini STT; send WhatsApp text summary to CHW.

**Requirements:** R4, R5 from requirements doc

**Dependencies:** U2 (Bhashini STT must be live first)

**Files:**
- `ivr_backend/main.py` — Modify `/twilio/voice-recording` to call Bhashini STT
- `ivr_backend/transcription_service.py` — New: Bhashini STT call + chunking for >60s
- `ivr_backend/whatsapp_sender.py` — Add text summary alongside audio
- `supabase/schema.sql` — Add `voice_transcripts` table (searchable)
- `apps/o2_backend/routers/bhashini.py` — Bhashini STT proxy (shared with U2)

**Approach:**
- Twilio webhook fires with recording URL → IVR backend downloads audio.
- Audio split into ≤60s chunks → sent to Bhashini STT API (via FastAPI proxy).
- Transcript returned in patient's preferred language → stored in `voice_transcripts` table.
- WhatsAppSender updated: send text summary (patient ID + chief complaint + transcript snippet) alongside audio.
- Emergency keywords scanned in transcript → if found, trigger emergency alert pipeline.

**Test scenarios:**
- Voice recording <60s → full transcript returned and stored
- Voice recording >60s → chunked correctly, transcript assembled
- Bhashini STT timeout → audio-only WhatsApp sent (Phase 1 fallback)
- Emergency keyword in transcript → emergency alert triggered
- Transcript searchable by keyword in supervisor dashboard

---

### U5. Multi-Recipient Emergency Alerts + Shadow ML Risk

**Goal:** Emergency alert to CHW + supervisor + emergency contact. Shadow ML runs alongside rule-based.

**Requirements:** R6, R7 from requirements doc

**Dependencies:** U1 (ABHA for emergency contact lookup), U4 (alert trigger integration)

**Files:**
- `apps/o2_app/lib/services/emergency_alert_service.dart` — Multi-recipient alert dispatcher
- `apps/o2_backend/routers/risk.py` — Add shadow ML score to `/risk` response
- `apps/o2_backend/services/ml_model.py` — New: quantized XGBoost shadow model
- `supabase/schema.sql` — Add `emergency_alert_log` table (delivery status per recipient)
- `supabase/schema.sql` — Add `ml_risk_scores` table (shadow score log)
- `apps/o2_backend/requirements.txt` — Add `xgboost`, `scikit-learn`

**Approach:**
- Emergency alert: When `/risk` returns EMERGENCY, job queued (offline-resilient). Three simultaneous sends: WhatsApp to CHW (existing), SMS to supervisor, SMS to emergency contact.
- SMS via Twilio programmable SMS (add to existing Twilio account).
- Supervisor fetched from `phc_hierarchy` table. Emergency contact from patient record.
- Shadow ML: On `/risk` call, quantized XGBoost model (pre-trained on synthetic Phase 1 data) computes shadow score. Both rule-based and ML scores logged to `ml_risk_scores`. ML score shown in app with label "ML (shadow)". Clinical decisions still use rule-based only.
- Retraining: When 200 new labeled outcomes accumulate (referral followed: yes/no), trigger retraining job.

**Test scenarios:**
- EMERGENCY risk → CHW WhatsApp + supervisor SMS + emergency contact SMS all sent simultaneously
- SMS delivery failure → fallback to WhatsApp link, retry once
- Alert delivery logged per recipient with status
- Shadow ML score computed and logged alongside rule-based score
- ML model accuracy validated against rule-based on test set ≥70%

---

### U6. PHC Supervisor Dashboard

**Goal:** Web dashboard for PHC supervisors to monitor aggregate health data.

**Requirements:** R9 from requirements doc

**Dependencies:** U3 (GPS data), U4 (transcription data), U5 (emergency alerts)

**Files:**
- `apps/supervisor_dashboard/` — New Flutter web or HTML/JS dashboard app
- `supabase/schema.sql` — Add `supervisor_views` materialized view for aggregate queries
- `supabase/rls_policies.sql` — Add supervisor role + PHC-based RLS for dashboard
- `apps/o2_backend/routers/dashboard.py` — New router for dashboard API
- `apps/o2_app/lib/models/supervisor_notification.dart` — App push notification model

**Approach:**
- Flutter web (shares `apps/o2_app/lib/` models) or simple HTML/JS (faster for pilot).
- Supabase Auth with supervisor role. Supervisors see only their PHC's data (same RLS as CHW app).
- Dashboard views: Risk overview (HIGH/EMERGENCY by village), CHW activity, IVR volume, referral tracker.
- App push: Flutter `firebase_messaging` for supervisor push notifications (Android).
- GPS map: Use `flutter_map` + OpenStreetMap tiles (offline-cacheable) to display visit locations.

**Test scenarios:**
- Supervisor logs in → sees only their PHC's patients
- Dashboard shows HIGH/EMERGENCY count updated within 30s of sync
- Visit map displays GPS coordinates with village labels
- IVR volume shows missed calls + transcriptions for past 7 days
- Referral tracker shows SBARs sent and acknowledgment status

---

## Scope Boundaries

### Deferred to Phase 3
- Full ABDM HIU certification
- On-device quantized LLM for SBAR generation
- Zero-phone patient workflow
- 50k concurrent CHW scale testing
- Smart reply for CHW WhatsApp follow-up

### Out of Scope
- Indic-2 translation (Bhashini direct languages only)

---

## Dependencies

| Unit | Depends On |
|------|-----------|
| U2 (Bhashini) | None |
| U1 (ABDM) | None |
| U3 (GPS + Auto-schedule) | U1 (for risk level) |
| U4 (IVR Transcription) | U2 (Bhashini STT) |
| U5 (Emergency + Shadow ML) | U1, U4 |
| U6 (Supervisor Dashboard) | U3, U4, U5 |

---

## Risks

| Risk | Mitigation |
|------|-----------|
| Bhashini API rate limits exceeded | Cache TTS responses; queue STT requests |
| ABDM sandbox credentials unavailable | Use Mod 97 fallback + warn CHW |
| ML model underperforms on real data | Shadow mode only; no clinical decisions |
| GPS fails in dense urban areas | Null gracefully; do not block clinical flow |
| Twilio SMS cost overrun | Alert supervisor on SMS budget threshold |

---

## Test Strategy

Each unit has its own test scenarios (see unit definitions above).

Integration test scenarios:
- End-to-end: patient voice message → transcript → WhatsApp text to CHW
- End-to-end: vitals submitted → rule-based + ML both scored → both logged
- End-to-end: EMERGENCY → all three alerts delivered within 60s
- Offline: GPS + auto-schedule queued → synced correctly on reconnect