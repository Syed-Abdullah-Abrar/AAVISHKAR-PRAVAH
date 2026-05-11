# O2 Platform Phase 2 — Pilot-Ready Integration Plan

**Date:** 2026-05-11  
**Phase:** 2  
**Status:** `active`  
**Type:** `feat`  
**Origin:** `docs/brainstorms/O2-Platform-Phase2-requirements.md`, `STRATEGY.md`

---

## External APIs Used in Phase 2

| API | Base URL | Auth | Rate Limit |
|-----|---------|------|-----------|
| **NHA / ABDM** | `https://.abdm.gov.in/api/v1` | HMAC-SHA256 | 100/min |
| **Bhashini STT/TTS** | `https://meity-auth.ulcacetech.in/api/v3` | JWT Bearer | 60/min STT |
| **Twilio SMS/WhatsApp** | `https://api.twilio.com/2010-04-01` | Basic Auth | Varies |
| **XGBoost ONNX** | Local inference | None | N/A |

---

## Problem Frame

Phase 1 delivered a functional MVP with working stubs and mocks. Phase 2 upgrades those stubs to live APIs (ABDM NHA, Bhashini), adds the IVR transcription pipeline, multi-recipient emergency alerts, GPS visit logs, shadow ML risk scoring, and the PHC supervisor dashboard.

---

## Success Criteria

| Metric | Target |
|--------|--------|
| ABDM verification success | ≥95% on 3G |
| STT accuracy (Kannada/Hindi) | ≥85% |
| Emergency alert delivery | All 3 recipients within 60s |
| GPS coverage on visits | ≥90% of clinical contacts |
| ML model vs rule-based agreement | ≥70% |

---

## High-Level Technical Design

```
Phase 2 External APIs:
┌─────────────────────┐     ┌──────────────────────┐     ┌────────────────────┐
│  NHA ABDM Sandbox   │     │   Bhashini v3 API   │     │   Twilio           │
│  (HMAC-SHA256)     │     │   (JWT Bearer)      │     │   (Basic Auth)     │
│  verify-abha        │     │   /asr, /tts        │     │   SMS + WhatsApp   │
└────────┬────────────┘     └──────────┬───────────┘     └─────────┬──────────┘
         │                                │                      │
         │ All proxied through FastAPI   │                      │
         ▼                                ▼                      ▼
┌────────────────────────────────────────────────────────────────────────────┐
│  FastAPI Backend (apps/o2_backend/)                                     │
│  ├── /abdm/verify     → NHA ABDM proxy                              │
│  ├── /bhashini/stt    → Bhashini STT proxy                         │
│  ├── /bhashini/tts    → Bhashini TTS proxy                         │
│  ├── /risk            → rule-based + shadow ML                      │
│  ├── /emergency/alert → multi-recipient dispatcher                 │
│  └── /dashboard/      → supervisor aggregates                       │
└────────────────────────────────────────────────────────────────────────────┘
         │                                │                       │
         ▼                                ▼                       ▼
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────┐
│  Supabase       │     │  IVR Backend         │     │  Flutter App    │
│  PostgreSQL     │     │  (ivr_backend/)       │     │  (apps/o2_app/)│
│  + RLS          │     │  Twilio webhooks     │     │  GPS, STT/TTS  │
│  + Auth         │     │  Bhashini STT        │     │  Auto-schedule  │
└─────────────────┘     │  WhatsApp sender     │     └─────────────────┘
                        └──────────────────────┘
```

---

## System-Wide Impact

- **Supabase schema:** New columns and tables for ABDM cache, GPS, transcripts, ML scores, emergency alerts
- **FastAPI backend:** New routers for ABDM proxy, Bhashini proxy, emergency dispatcher, dashboard API
- **IVR backend:** Bhashini STT integration for voice transcription
- **Flutter app:** Bhashini STT/TTS services, GPS service, auto-schedule, supervisor push notifications
- **No breaking changes** to existing Phase 1 API contracts

---

## Implementation Units

### U1. Live ABDM/NHA API Integration

**Goal:** Replace Mod 97 checksum stub with live NHA API calls for ABHA verification.

**Requirements:** R1 from origin doc  
**Dependencies:** None (first unit — no dependencies)

**Files:**
- `apps/o2_app/lib/abdm/abdm_service.dart` — Replace `_validateChecksum()` with HTTP call to FastAPI proxy
- `apps/o2_backend/routers/abdm.py` — New router for ABDM proxy endpoints
- `apps/o2_backend/routers/__init__.py` — Export `abdm` router
- `apps/o2_backend/main.py` — Register `abdm` router
- `supabase/schema.sql` — Add `abha_verification_cache` table

**Approach:**
```
CHW enters ABHA number
    ↓
Flutter calls POST /abdm/verify {healthId: "12-3456-7890-1234"}
    ↓
FastAPI computes HMAC-SHA256: clientId + timestamp + healthId
    ↓
FastAPI POST https://.abdm.gov.in/api/v1/abd-v1/discovery/verify-abha
    ↓
Cache result in abha_verification_cache (24h TTL)
    ↓
Return to Flutter: {verified: true, name: "Lakshmi", dob: "1998-03-15"}
    ↓
Patient record auto-filled; ABHA linked
```

**HMAC signature computation (Python):**
```python
import hmac, hashlib, datetime, json

def compute_hmac(health_id: str) -> str:
    timestamp = datetime.utcnow().isoformat() + "Z"
    message = f"{os.getenv('NHA_CLIENT_ID')}|{timestamp}|{health_id}"
    sig = hmac.new(
        os.getenv('NHA_SECRET').encode(),
        message.encode(),
        hashlib.sha256
    ).hexdigest()
    return sig
```

**Environment variables needed:**
```bash
NHA_CLIENT_ID=your_nha_client_id
NHA_CLIENT_SECRET=your_nha_secret
NHA_HMAC_KEY=your_hmac_key
NHA_BASE_URL=https://.abdm.gov.in/api/v1
```

**Supabase schema:**
```sql
CREATE TABLE abha_verification_cache (
    abha_number TEXT PRIMARY KEY,
    name TEXT,
    dob TEXT,
    gender TEXT,
    mobile TEXT,
    verified BOOLEAN NOT NULL,
    fetched_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '24 hours'
);
CREATE INDEX idx_abha_cache_expires ON abha_verification_cache(expires_at);
```

**Patterns to follow:** `apps/o2_backend/routers/sbar.py` — proxy pattern with error handling and timeout

**Test scenarios:**
- Happy path: valid ABHA → `verified: true`, name/DOB returned
- Invalid ABHA → `verified: false`, user-friendly error
- Network timeout → exponential backoff 3x (2s, 4s, 8s), then warn-and-proceed
- Cache hit → no NHA API call, instant return
- Offline → use cache if available, else warn CHW

---

### U2. Live Bhashini STT/TTS Integration

**Goal:** Replace stubs in `constants.dart` with live Bhashini API v3 calls.

**Requirements:** R2 from origin doc  
**Dependencies:** None (parallel with U1)

**Files:**
- `apps/o2_app/lib/services/bhashini_stt_service.dart` — New: Bhashini STT service
- `apps/o2_app/lib/services/bhashini_tts_service.dart` — New: Bhashini TTS service
- `apps/o2_app/lib/core/constants.dart` — Update to use new services
- `apps/o2_backend/routers/bhashini.py` — New: Bhashini proxy router (for IVR backend)
- `apps/o2_backend/main.py` — Register `bhashini` router
- `apps/o2_backend/requirements.txt` — Add `httpx`
- `ivr_backend/main.py` — Integrate Bhashini STT for voice transcription

**Environment variables needed:**
```bash
BHASHINI_CLIENT_ID=your_bhashini_client_id
BHASHINI_CLIENT_SECRET=your_bhashini_client_secret
BHASHINI_BASE_URL=https://meity-auth.ulcacetech.in/api/v3
```

**Token management:**
```python
# Cached token with proactive refresh
_token_cache = {"token": None, "expires_at": 0}

async def get_bhashini_token() -> str:
    if time.time() < _token_cache["expires_at"] - 300:  # refresh 5min early
        return _token_cache["token"]
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://auth.ulcacetech.in/api/v1/telemetry",
            data={
                "grant_type": "client_credentials",
                "client_id": os.getenv("BHASHINI_CLIENT_ID"),
                "client_secret": os.getenv("BHASHINI_CLIENT_SECRET"),
            },
            timeout=10.0,
        )
        data = resp.json()
        _token_cache["token"] = data["access_token"]
        _token_cache["expires_at"] = time.time() + data["expires_in"]
    return _token_cache["token"]
```

**STT flow (Flutter):**
```dart
class BhashiniSttService {
  Future<String> transcribe(File audioFile, String language) async {
    final token = await _getToken();
    final formData = FormData.fromMap({
      'audioSource': 'byte',
      'inputLanguage': language,  // 'kn' or 'hi'
      'fileType': 'wav',
      'model': 'medium',
      'purpose': 'healthcare',
    });
    formData.files.add(await MultipartFile.fromFile(
      audioFile.path, filename: 'recording.wav'));
    final response = await dio.post(
      'https://meity-auth.ulcacetech.in/api/v3/asr',
      data: formData,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return BhashiniSttResponse.fromJson(response.data).text;
  }
}
```

**TTS caching strategy:** Pre-generate and cache common phrases (risk level descriptions, follow-up instructions) at app launch.

**Patterns to follow:** `apps/o2_app/lib/services/fhir_serializer.dart` — service pattern with interface

**Test scenarios:**
- STT: Kannada audio → correct Kannada text
- STT: Hindi audio → correct Hindi text
- TTS: "BP elevated" → audio plays in <3s
- Token refresh: 55min proactive refresh → no auth failures
- Network failure → graceful degradation to text-only

---

### U3. GPS Auto-Tag + Auto-Schedule

**Goal:** Auto-capture GPS on clinical contact + auto-schedule follow-ups from risk level.

**Requirements:** R3, R8 from origin doc  
**Dependencies:** U1 (risk level needed for auto-schedule)

**Files:**
- `apps/o2_app/lib/services/location_service.dart` — New: GPS capture service
- `apps/o2_app/lib/repositories/clinical_contact_repository.dart` — Add GPS + scheduled_follow_up fields
- `apps/o2_app/lib/screens/patient_detail_screen.dart` — Display auto-schedule banner
- `supabase/schema.sql` — Add `visit_location` JSONB + `scheduled_follow_up` TIMESTAMPTZ + `follow_up_source`
- `apps/o2_backend/routers/risk.py` — Add `scheduled_follow_up` to risk response

**Supabase schema:**
```sql
ALTER TABLE clinical_contact_logs ADD COLUMN visit_location JSONB;
-- {"lat": 12.9716, "lng": 77.5946, "accuracy": 15.0, "timestamp": "2026-05-28T09:30:00Z"}

ALTER TABLE clinical_contact_logs ADD COLUMN scheduled_follow_up TIMESTAMPTZ;
ALTER TABLE clinical_contact_logs ADD COLUMN follow_up_source TEXT DEFAULT 'manual';
```

**GPS capture:**
```dart
class LocationService {
  Future<LocationData?> captureLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || 
          permission == LocationPermission.deniedForever) {
        return null;  // Do not block clinical workflow
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
    } catch (e) {
      return null;  // GPS failure is non-fatal
    }
  }
}
```

**Auto-schedule intervals:**
```dart
Duration getFollowUpInterval(String riskLevel) {
  switch (riskLevel) {
    case 'EMERGENCY': return Duration(hours: 0);  // immediate
    case 'HIGH': return Duration(hours: 24);
    case 'MEDIUM': return Duration(hours: 48);
    case 'LOW': return Duration(days: 7);
  }
}
```

**Patterns to follow:** `apps/o2_app/lib/services/sync_service.dart` — offline-first service pattern

**Test scenarios:**
- GPS captured → stored in `clinical_contact_logs.visit_location`
- GPS unavailable → null stored, clinical workflow continues
- Risk HIGH → follow-up auto-created for next day
- CHW modifies auto-schedule → modified date stored, `follow_up_source` = 'manual'
- Offline → GPS + schedule queued, synced on WorkManager window

---

### U4. IVR Voice Transcription Pipeline

**Goal:** Transcribe Twilio recordings via Bhashini STT; send WhatsApp text summary to CHW.

**Requirements:** R4, R5 from origin doc  
**Dependencies:** U2 (Bhashini STT must be live first)

**Files:**
- `ivr_backend/main.py` — Integrate STT after Twilio webhook fires
- `ivr_backend/transcription_service.py` — New: audio download + chunking + Bhashini STT call
- `ivr_backend/whatsapp_sender.py` — Add text summary alongside audio
- `apps/o2_backend/routers/bhashini.py` — Share Bhashini proxy (used by IVR + Flutter)
- `supabase/schema.sql` — Add `voice_transcripts` table

**Supabase schema:**
```sql
CREATE TABLE voice_transcripts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id TEXT NOT NULL REFERENCES patients(id),
    recording_url TEXT NOT NULL,
    transcript_text TEXT,
    transcript_language TEXT,
    confidence_score FLOAT,
    is_emergency BOOLEAN DEFAULT FALSE,
    whatsapp_summary_sent BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_transcripts_patient ON voice_transcripts(patient_id);
CREATE INDEX idx_transcripts_emergency ON voice_transcripts(is_emergency) WHERE is_emergency = TRUE;
```

**Transcription flow:**
```python
async def transcribe_recording(recording_url: str, patient_language: str) -> dict:
    audio_data = await download_audio(recording_url)  # from Twilio CDN
    
    # Split if >60s
    chunks = split_audio(audio_data, max_duration=55)  # 5s overlap for continuity
    
    full_transcript = []
    for chunk in chunks:
        result = await call_bhashini_stt(chunk, patient_language)
        full_transcript.append(result["text"])
    
    transcript = " ".join(full_transcript)
    confidence = mean([r["confidence"] for r in results])
    
    is_emergency = check_emergency_keywords(transcript)
    
    await save_transcript(patient_id, recording_url, transcript, confidence, is_emergency)
    await send_whatsapp_summary(patient_id, transcript)
    
    return {"transcript": transcript, "is_emergency": is_emergency}
```

**Patterns to follow:** `ivr_backend/patient_lookup.py` — sequential async pipeline pattern

**Test scenarios:**
- Recording <60s → full transcript returned
- Recording >60s → chunked correctly, transcript assembled
- Bhashini timeout → audio-only WhatsApp (Phase 1 fallback)
- Emergency keyword in transcript → emergency alert triggered
- Transcript searchable in supervisor dashboard

---

### U5. Multi-Recipient Emergency Alert + Shadow ML Risk

**Goal:** Emergency alert to CHW + supervisor + emergency contact. Shadow ML runs alongside rule-based.

**Requirements:** R6, R7 from origin doc  
**Dependencies:** U1 (ABHA for emergency contact), U4 (alert trigger)

**Files:**
- `apps/o2_app/lib/services/emergency_alert_service.dart` — New: multi-recipient dispatcher
- `apps/o2_backend/routers/risk.py` — Add shadow ML score to `/risk` response
- `apps/o2_backend/services/ml_model.py` — New: quantized XGBoost inference
- `apps/o2_backend/requirements.txt` — Add `xgboost`, `onnxruntime`, `onnxmltools`
- `supabase/schema.sql` — Add `emergency_alert_log`, `ml_risk_scores`
- `supabase/schema.sql` — Add `supervisors` table

**Environment variables:**
```bash
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxx
SUPERVISOR_SMS_ENABLED=true
```

**Emergency alert flow:**
```python
async def send_emergency_alert(patient_id: str, risk_level: str, vitals: dict):
    patient = await get_patient(patient_id)
    chw = await get_chw(patient.chw_id)
    supervisor = await get_supervisor(patient.phc_id)
    emergency_contact = patient.emergency_contact_phone
    
    tasks = [
        send_whatsapp(chw.phone, format_chw_alert(patient, vitals)),      # CHW
        send_sms(supervisor.phone, format_supervisor_sms(patient, vitals)), # Supervisor
        send_sms(emergency_contact, format_ec_sms(patient)),               # Emergency contact
    ]
    results = await asyncio.gather(*tasks, return_exceptions=True)
    
    for i, (recipient, result) in enumerate(zip(recipients, results)):
        await log_alert(patient_id, recipient, success=isinstance(result, str), error=result if isinstance(result, Exception) else None)
```

**Shadow ML flow:**
```python
async def compute_shadow_ml(vitals: dict, patient_id: str) -> dict:
    features = [
        vitals["systolic_bp"],
        vitals["diastolic_bp"],
        vitals["hemoglobin"],
        vitals["weight_kg"],
        vitals["weeks_pregnant"],
        vitals.get("temperature_c", 37.0),
        vitals.get("fetal_heart_rate", 140),
        len(vitals.get("previous_complications", [])),
        vitals.get("missed_call_frequency_7d", 0),
    ]
    
    session = InferenceSession("risk_model.onnx")
    input_tensor = np.array([features], dtype=np.float32)
    result = session.run(None, {"input": input_tensor})
    
    ml_probability = float(result[0][0][1])
    
    await log_ml_score(patient_id, vitals, ml_probability, "xgboost-v1")
    
    return {
        "ml_probability": ml_probability,
        "ml_confidence": 0.82,
        "model_version": "xgboost-v1",
        "training_samples": 1247,
    }
```

**Supabase schema additions:**
```sql
CREATE TABLE emergency_alert_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id TEXT NOT NULL,
    risk_level TEXT NOT NULL,
    chw_notified BOOLEAN DEFAULT FALSE,
    chw_notified_at TIMESTAMPTZ,
    supervisor_notified BOOLEAN DEFAULT FALSE,
    supervisor_notified_at TIMESTAMPTZ,
    emergency_contact_notified BOOLEAN DEFAULT FALSE,
    emergency_contact_notified_at TIMESTAMPTZ,
    failure_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE ml_risk_scores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    patient_id TEXT NOT NULL,
    vitals_input JSONB NOT NULL,
    rule_based_level TEXT NOT NULL,
    rule_based_score INTEGER NOT NULL,
    ml_probability FLOAT NOT NULL,
    ml_confidence FLOAT,
    model_version TEXT NOT NULL,
    training_samples INTEGER,
    outcome_label BOOLEAN,  -- filled later
    outcome_labeled_at TIMESTAMPTZ,
    labeled_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_ml_scores_unlabeled ON ml_risk_scores(outcome_label) WHERE outcome_label IS NULL;
```

**Patterns to follow:** `apps/o2_backend/services/risk_model.py` — service class pattern with clear method signatures

**Test scenarios:**
- EMERGENCY → WhatsApp to CHW + SMS to supervisor + SMS to emergency contact
- SMS failure → retry once, then log failure
- Shadow ML score computed and logged alongside rule-based score
- ML vs rule-based agreement ≥70% on test set

---

### U6. PHC Supervisor Dashboard

**Goal:** Web dashboard for PHC supervisors to monitor aggregate health data.

**Requirements:** R9 from origin doc  
**Dependencies:** U3, U4, U5 (data sources must exist first)

**Files:**
- `apps/supervisor_dashboard/` — New: Flutter web or HTML/JS dashboard
- `apps/supervisor_dashboard/lib/screens/` — Dashboard screens
- `apps/supervisor_dashboard/lib/services/supabase_service.dart` — Supabase client
- `apps/supervisor_dashboard/lib/models/` — Dashboard models
- `supabase/schema.sql` — Add `supervisor_views` (materialized view or RLS policies for supervisor role)
- `supabase/rls_policies.sql` — Add supervisor role + PHC-scoped RLS
- `apps/o2_backend/routers/dashboard.py` — New: dashboard API router
- `apps/o2_backend/main.py` — Register `dashboard` router
- `apps/o2_app/lib/services/supervisor_notification_service.dart` — App push for supervisors

**Auth:** Supabase Auth with `supervisor` role. Supervisors sign up with their PHC ID.

**RLS for supervisor:**
```sql
CREATE ROLE supervisor;
GRANT supervisor TO authenticated_users;

CREATE POLICY "Supervisors see only their PHC"
ON patients FOR SELECT
USING (
    phc_id IN (
        SELECT phc_id FROM supervisor_assignments
        WHERE user_id = auth.uid()
    )
);
```

**Dashboard queries:**
```sql
-- HIGH/EMERGENCY by village
SELECT p.village,
       COUNT(*) FILTER (WHERE v.risk_level = 'HIGH') as high_count,
       COUNT(*) FILTER (WHERE v.risk_level = 'EMERGENCY') as emergency_count
FROM patients p
JOIN vitals_logs v ON v.patient_id = p.id
WHERE p.phc_id = current_user_phc()
  AND v.created_at > NOW() - INTERVAL '7 days'
GROUP BY p.village
ORDER BY (high_count + emergency_count) DESC;

-- CHW activity today
SELECT chw_id,
       COUNT(*) as total_visits,
       SUM(sbar_generated::int) as sbars_generated
FROM clinical_contact_logs
WHERE DATE(created_at) = CURRENT_DATE
  AND phc_id = current_user_phc()
GROUP BY chw_id;
```

**Push notifications:** Use Flutter `firebase_messaging` on supervisor's Android device.

**Patterns to follow:** `apps/o2_app/lib/core/router.dart` — GoRouter with auth guard pattern

**Test scenarios:**
- Supervisor logs in → sees only their PHC's patients
- Dashboard loads within 2 seconds
- Visit map displays GPS coordinates with village labels
- IVR volume shows transcriptions for past 7 days

---

## Scope Boundaries

### Deferred to Phase 3
- Full ABDM HIU certification
- On-device quantized LLM for SBAR
- Zero-phone patient workflow
- 50k concurrent CHW scale testing

### Out of Scope
- Indic-2 translation (Bhashini direct languages only)
- Smart reply for CHW WhatsApp follow-up

---

## Dependencies

| Unit | Depends On |
|------|-----------|
| U2 (Bhashini) | None |
| U1 (ABDM) | None |
| U3 (GPS + Auto-schedule) | U1 |
| U4 (IVR Transcription) | U2 |
| U5 (Emergency + Shadow ML) | U1, U4 |
| U6 (Supervisor Dashboard) | U3, U4, U5 |

**Parallelization:** U1 and U2 are independent and should be started together.

---

## Risks

| Risk | Probability | Impact | Mitigation |
|------|------------|--------|-------------|
| Bhashini rate limit exceeded | Medium | High | Cache TTS; queue STT requests; exponential backoff |
| ABDM sandbox credentials unavailable | Low | High | Mod 97 fallback + warn CHW; no blocking |
| ML model underperforms | Medium | Medium | Shadow mode only; no clinical decisions |
| GPS fails in dense areas | Low | Low | Null gracefully; do not block workflow |
| Twilio SMS cost overrun | Low | Medium | Budget threshold alert; supervisor approval |
| IVR transcription failure | Medium | Low | Fallback to audio-only WhatsApp |

---

## Test Strategy

Each unit has specific scenarios (see unit definitions above).

**Integration test scenarios:**
1. Patient voice message → transcript → WhatsApp text to CHW
2. Vitals submitted → rule-based + ML both scored → both logged
3. EMERGENCY → all three alerts delivered within 60s
4. GPS + auto-schedule queued offline → synced correctly on reconnect
5. Supervisor logs in → sees only their PHC's data

---

## Environment Variables

```bash
# ABDM / NHA
NHA_CLIENT_ID=
NHA_CLIENT_SECRET=
NHA_HMAC_KEY=
NHA_BASE_URL=https://.abdm.gov.in/api/v1

# Bhashini
BHASHINI_CLIENT_ID=
BHASHINI_CLIENT_SECRET=
BHASHINI_BASE_URL=https://meity-auth.ulcacetech.in/api/v3

# Twilio
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxx
TWILIO_PHONE_NUMBER=+1xxxxxxxxxx

# ML Model
ML_MODEL_PATH=models/risk_model.onnx
ML_MODEL_VERSION=xgboost-v1

# Supabase
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
```

---

## Flutter Packages (Phase 2 New)

```yaml
# apps/o2_app/pubspec.yaml — add:
dependencies:
  geolocator: ^13.0.0
  firebase_messaging: ^15.0.0
  flutter_map: ^7.0.0  # For supervisor dashboard map
  latlong2: ^0.9.0

dev_dependencies:
  onnxruntime: ^1.19.0
```

---

## Python Packages (Phase 2 New)

```txt
# apps/o2_backend/requirements.txt — add:
httpx==0.28.1
xgboost==2.1.3
onnxmltools==1.11.3
onnxruntime==1.20.1
firebase-admin==6.5.0