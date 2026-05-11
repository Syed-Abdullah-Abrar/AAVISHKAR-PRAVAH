# O2 Platform — Phase 2 Requirements

**Date:** 2026-05-11  
**Phase:** 2 (Pilot-Ready Integration)  
**Status:** Requirements — ready for planning  
**Based on:** `docs/ideation/O2-Platform-Phase2-ideation.md`

---

## External API Inventory

### 1. NHA / ABDM API

**Base URL (Sandbox):** `https://.abdm.gov.in/api/v1`  
**Production URL:** `https://healthidsbx.abdm.gov.in/api/v1`  
**Auth:** HMAC-SHA256 signature with API key + secret, passed as headers

**Key Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/abd-v1/discovery/verify-abha` | POST | Verify ABHA number exists |
| `/abd-v1/hpr/search-by-name` | GET | Search health professional by name |
| `/abd-v1/hfr/search` | GET | Search health facility by ID |
| `/abd-v1/consent` | POST | Request patient consent |
| `/abd-v1/health-information/hip/on-share` | POST | Receive health records |

**Headers required:**
```
Content-Type: application/json
clientId: <API_KEY>
clientSecret: <API_SECRET>
HMAC-SHA256: <signature>
timestamp: <ISO8601>
```

**Request body (ABHA verify):**
```json
{
  "healthId": "12-3456-7890-1234"
}
```

**Response:**
```json
{
  "healthIdNumber": "12-3456-7890-1234",
  "healthId": "john.doe@abdm",
  "name": "John Doe",
  "gender": "M",
  "dateOfBirth": "1990-01-15",
  "mobile": "9876543210",
  "verified": true,
  "status": "ACTIVE"
}
```

**Credentials:** Apply at https://abdm.gov.in/developers  
**Rate limit:** 100 requests/minute (sandbox), 1000/minute (production)

---

### 2. Bhashini API v3

**Base URL:** `https://meity-auth.ulcacetech.in/api/v3`  
**Auth:** JWT Bearer token, obtained via client credentials grant

**Token endpoint:**
```
POST https://auth.ulcacetech.in/api/v1/telemetry
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials
&client_id=<BHASHINI_CLIENT_ID>
&client_secret=<BHASHINI_CLIENT_SECRET>
```

**Returns:**
```json
{
  "access_token": "<JWT>",
  "token_type": "Bearer",
  "expires_in": 3600
}
```

**Key Endpoints:**

| Endpoint | Method | Purpose | Lang Codes |
|----------|--------|---------|------------|
| `/asr` | POST | Speech-to-text | `kn` (Kannada), `hi` (Hindi) |
| `/tts` | POST | Text-to-speech | `kn`, `hi` |
| `/translation/v2` | POST | Translate text | `kn→en`, `hi→en` |
| `/detectLang` | POST | Detect language | auto-detect |

**STT Request (`/asr`):**
```json
{
  "audioSource": "byte",
  "inputLanguage": "kn",
  "fileType": "wav",
  "model": "medium",
  "purpose": "healthcare"
}
```
Audio sent as multipart/form-data binary.

**STT Response:**
```json
{
  "text": "ರಕ್ತದೊತ್ತಡ 140/90",
  "confidence": 0.94,
  "language": "kn"
}
```

**TTS Request (`/tts`):**
```json
{
  "inputText": "BP is elevated at 150 over 95. Please schedule a visit within 24 hours.",
  "inputLanguage": "kn",
  "gender": "female",
  "model": "medium",
  "purpose": "healthcare"
}
```

**TTS Response:** Binary audio/wav

**Language codes:** `kn` (Kannada), `hi` (Hindi), `en` (English)  
**Credentials:** Self-service at https://bhashini.gov.in  
**Rate limit:** 60 requests/minute (STT), 30 requests/minute (TTS)

---

### 3. Twilio (Programmable SMS + WhatsApp)

**Base URL:** `https://api.twilio.com/2010-04-01`  
**Auth:** `AC<AccountSID>:<AuthToken>` (Basic Auth)

**Key Endpoints:**

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/Accounts/{AccountSid}/Messages.json` | POST | Send SMS or WhatsApp |
| `/Accounts/{AccountSid}/Calls.json` | POST | Initiate call (callback) |

**SMS Request:**
```
POST /2010-04-01/Accounts/<AC_SID>/Messages.json
Content-Type: application/x-www-form-urlencoded

To=+919876543210
From=+14155551234
Body=Patient+P001+EMERGENCY+BP+160+100.+Refer+to+PHC+immediately.
```

**WhatsApp Request:** Same as SMS, `From=whatsapp:+14155551234`, `To=whatsapp:+919876543210`

**Callbacks:** Set webhook URL in Twilio console for `POST /twilio/missed-call` and `POST /twilio/voice-recording`  
**Credentials:** `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` from console.twilio.com

---

### 4. XGBoost Quantized ML Model

**Format:** ONNX quantized model (`.onnx`) for cross-platform inference  
**Training:** Python `xgboost`, exported to ONNX via `onnxmltools`  
**Inference runtime:** `onnxruntime` (Python) or `onnxruntime_mobile` (Dart/Flutter on-device)

**Model input features (9 features):**
```
systolic_bp, diastolic_bp, hemoglobin, weight_kg,
weeks_pregnant, temperature_c, fetal_heart_rate,
previous_complications_count, missed_call_frequency
```

**Model output:** Risk probability (0.0 - 1.0)  
**Quantization:** Dynamic int16 quantization for ~90% size reduction  
**Approximate model size:** 500KB quantized

**Training pipeline:**
```python
import xgboost as xgb
from onnxmltools import convert_xgboost

# Train on Phase 1 historical data
model = xgb.XGBClassifier(
    objective='binary:logistic',
    max_depth=4,
    n_estimators=100,
    learning_rate=0.1,
    scale_pos_weight=3  # emergency cases are rare
)
model.fit(X_train, y_train)

# Convert to ONNX
onnx_model = convert_xgboost(model, initial_types=[('input', FloatTensorType([1, 9]))]
with open('risk_model.onnx', 'wb') as f:
    f.write(onnx_model.SerializeToString())
```

**Labels:** Outcome of clinical contact: `0` = safe delivery, `1` = complication/referral  
**Minimum training samples:** 500 patient-months  
**Retrain trigger:** 200 new labeled outcomes accumulated

---

## Feature 1: Live ABDM/NHA API Integration

### What

Replace the Mod 97 checksum stub in `abdm_service.dart` with live NHA API calls. Patient ABHA IDs are verified against the Ayushman Bharat Health Account system before registration completes.

### User Flow

1. CHW enters patient's ABHA number during registration
2. App calls NHA API via FastAPI proxy (`POST /abdm/verify`)
3. API proxies to NHA sandbox: `POST https://.abdm.gov.in/api/v1/abd-v1/discovery/verify-abha`
4. NHA returns: verified/not found/error with name + DOB
5. If verified → patient linked to national health record, name/DOB auto-filled
6. If not found → CHW prompted to correct or skip ABHA linking
7. If error → retry with exponential backoff (3 attempts, 2s/4s/8s); patient can proceed without ABHA link

### API Contract

**Flutter → FastAPI:**
```dart
// apps/o2_app/lib/abdm/abdm_service.dart
Future<AbdmVerifyResult> verifyAbha(String abhaNumber) async {
  final response = await dio.post(
    'https://api.o2.example.com/abdm/verify',
    data: {'healthId': abhaNumber}
  );
  return AbdmVerifyResult.fromJson(response.data);
}
```

**FastAPI endpoint:**
```python
# apps/o2_backend/routers/abdm.py
@router.post("/abdm/verify")
async def verify_abha(request: AbdmVerifyRequest) -> AbdmVerifyResponse:
    # HMAC-signed call to NHA sandbox
    headers = {
        "clientId": os.getenv("NHA_CLIENT_ID"),
        "clientSecret": os.getenv("NHA_CLIENT_SECRET"),
        "timestamp": datetime.utcnow().isoformat(),
        "HMAC-SHA256": compute_hmac(request.healthId),
        "Content-Type": "application/json"
    }
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "https://.abdm.gov.in/api/v1/abd-v1/discovery/verify-abha",
            json={"healthId": request.healthId},
            headers=headers,
            timeout=10.0
        )
    return AbdmVerifyResponse.from_nha(resp.json())
```

### Supabase Schema Addition

```sql
-- 24h cache to avoid redundant calls
CREATE TABLE abha_verification_cache (
    abha_number TEXT PRIMARY KEY,
    name TEXT,
    dob TEXT,
    gender TEXT,
    verified BOOLEAN,
    fetched_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT NOW() + INTERVAL '24 hours'
);

CREATE INDEX idx_abha_cache_expires ON abha_verification_cache(expires_at);
```

### Success Criteria

- ≥95% of patient registrations complete ABHA verification within 10 seconds on 3G
- ≥99% uptime for ABDM API proxy (cloud SLA)

---

## Feature 2: Live Bhashini STT/TTS Integration

### What

Replace stubs in `lib/core/constants.dart` with live Bhashini API v3 calls. CHWs and patients use voice input/output in Kannada and Hindi.

### API Contract

**Bhashini STT:**
```dart
// apps/o2_app/lib/services/bhashini_stt_service.dart
class BhashiniSttService {
  Future<String> transcribe(File audioFile, String languageCode) async {
    final token = await _getAccessToken();
    final formData = FormData.fromMap({
      'audioSource': 'byte',
      'inputLanguage': languageCode,  // 'kn' or 'hi'
      'fileType': 'wav',
      'model': 'medium',
      'purpose': 'healthcare',
    });
    formData.files.add(MapEntry('audioFile', 
        MultipartFile.fromFileSync(audioFile.path)));
    
    final response = await dio.post(
      'https://meity-auth.ulcacetech.in/api/v3/asr',
      data: formData,
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
    return BhashiniSttResponse.fromJson(response.data).text;
  }
}
```

**Bhashini TTS:**
```dart
// apps/o2_app/lib/services/bhashini_tts_service.dart
class BhashiniTtsService {
  Future<Uint8List> synthesize(String text, String languageCode) async {
    final token = await _getAccessToken();
    final response = await dio.post(
      'https://meity-auth.ulcacetech.in/api/v3/tts',
      data: {
        'inputText': text,
        'inputLanguage': languageCode,
        'gender': 'female',
        'model': 'medium',
        'purpose': 'healthcare',
      },
      options: Options(
        headers: {'Authorization': 'Bearer $token'},
        responseType: ResponseType.bytes,
      ),
    );
    return Uint8List.fromList(response.data);
  }
}
```

**Backend Bhashini proxy (for IVR):**
```python
# apps/o2_backend/routers/bhashini.py
@router.post("/bhashini/stt")
async def speech_to_text(audio_url: str, language: str) -> dict:
    token = await get_bhashini_token()
    audio_data = await download_audio(audio_url)  # Twilio recording URL
    files = {'audioFile': ('recording.wav', audio_data, 'audio/wav')}
    data = {
        'audioSource': 'byte',
        'inputLanguage': language,
        'fileType': 'wav',
        'model': 'medium',
        'purpose': 'healthcare'
    }
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            BHASHINI_STT_URL,
            data=data,
            files=files,
            headers={'Authorization': f'Bearer {token}'},
            timeout=30.0
        )
    return {"text": resp.json()["text"], "confidence": resp.json()["confidence"]}
```

### Key Decisions

| Decision | Choice | Rationale |
|---------|--------|-----------|
| Audio chunking | ≤60s per chunk | Bhashini limit; long recordings split |
| TTS caching | Cache common messages | 3s latency on 3G; pre-generate risk summaries |
| Token refresh | Proactive refresh at 55min | Tokens expire at 60min |
| Fallback | Text-only when offline | Bhashini needs network |

---

## Feature 3: Auto-Schedule Follow-Up from Risk Level

### What

When `/risk` returns a triage result, the app automatically creates a follow-up visit entry — no manual date entry required.

### Default Intervals

| Risk Level | Default Follow-Up |
|------------|-----------------|
| EMERGENCY | Immediate (same day, urgent flag) |
| HIGH | 24 hours |
| MEDIUM | 48 hours |
| LOW | 7 days |

### Supabase Schema Addition

```sql
ALTER TABLE clinical_contact_logs ADD COLUMN scheduled_follow_up TIMESTAMPTZ;
ALTER TABLE clinical_contact_logs ADD COLUMN follow_up_source TEXT DEFAULT 'manual';
-- follow_up_source: 'manual' | 'auto_from_risk'
```

### Success Criteria

- ≥80% of HIGH/EMERGENCY cases have a scheduled follow-up within protocol interval
- Zero additional taps required from CHW after submitting vitals

---

## Feature 4: IVR Voice Transcription Pipeline

### What

Twilio-recorded voice messages are transcribed via Bhashini STT. Transcript sent as WhatsApp text summary to CHW alongside the audio.

### Data Flow

```
Twilio records audio → webhook POST /twilio/voice-recording {RecordingUrl}
    ↓
IVR backend downloads audio from RecordingUrl
    ↓
Audio → Bhashini STT API (via FastAPI proxy)
    ↓
Transcript returned in patient's language
    ↓
Transcript stored in Supabase voice_transcripts table
    ↓
WhatsApp text message: "P001: 'BP problem' — 14:30, 28 May"
    ↓
If emergency keywords in transcript → trigger emergency alert
```

### Supabase Schema Addition

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

### Success Criteria

- ≥80% of voice messages transcribed successfully
- Emergency keywords detected in ≥95% of messages containing them

---

## Feature 5: Multi-Recipient Emergency Alert

### What

When `/risk` returns EMERGENCY, alert is simultaneously sent to: CHW (WhatsApp), PHC Supervisor (SMS + app push), patient's emergency contact (SMS).

### Alert Message Format

**CHW (WhatsApp):**
```
🚨 EMERGENCY: P001 — Lakshmi, 28 weeks pregnant
BP: 170/110 | Hemoglobin: 6.5 g/dL
Village: Byadarahalli | PHC: Harohalli
Open app: https://o2.app/patient/P001
```

**Supervisor (SMS):**
```
O2 EMERGENCY: P001 (Lakshmi) BP 170/110 Hb 6.5 at Byadarahalli PHC. CHW: Radha. https://o2.app/supervisor/P001
```

**Emergency Contact (SMS):**
```
Your family member Lakshmi needs urgent medical attention. Nearest PHC: Harohalli PHC, 3km. Ambulance: 108.
```

### Supabase Schema Addition

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
```

### Success Criteria

- All three recipients receive alert within 60 seconds of EMERGENCY detection
- ≥99% delivery success to at least one channel per recipient

---

## Feature 6: PHC Supervisor Dashboard

### What

A web dashboard (Flutter web or simple HTML/JS) showing PHC-level aggregate data.

### Dashboard Queries

```sql
-- HIGH/EMERGENCY by village (last 7 days)
SELECT p.village, COUNT(*) as high_risk_count
FROM patients pa
JOIN vitals_logs v ON v.patient_id = pa.id
JOIN clinical_contact_logs c ON c.patient_id = pa.id
WHERE v.risk_level IN ('HIGH', 'EMERGENCY')
  AND c.created_at > NOW() - INTERVAL '7 days'
GROUP BY p.village
ORDER BY high_risk_count DESC;

-- CHW activity today
SELECT chw_id, COUNT(*) as visits, 
       SUM(CASE WHEN sbar_generated THEN 1 ELSE 0 END) as sbars
FROM clinical_contact_logs
WHERE DATE(created_at) = CURRENT_DATE
GROUP BY chw_id;
```

### Views

| View | Description |
|------|-------------|
| Risk Overview | HIGH/EMERGENCY by village, 7/30-day trend |
| CHW Activity | Visits, SBARs, unfollowed patients |
| IVR Volume | Missed calls, transcriptions, unresolved |
| Referral Tracker | SBARs sent, acknowledgment status |

---

## Feature 7: Shadow-Mode ML Risk Scoring

### What

Quantized XGBoost model runs alongside rule-based WHO thresholds in shadow mode.

### Model Input (from Flutter app)

```json
{
  "systolic_bp": 155,
  "diastolic_bp": 98,
  "hemoglobin": 9.5,
  "weight_kg": 62,
  "weeks_pregnant": 28,
  "temperature_c": 37.2,
  "fetal_heart_rate": 142,
  "previous_complications_count": 1,
  "missed_call_frequency_7d": 2
}
```

### Model Output (logged, not used clinically)

```json
{
  "rule_based_level": "HIGH",
  "rule_based_score": 4,
  "ml_probability": 0.73,
  "ml_confidence": 0.82,
  "model_version": "xgboost-v2-20260511",
  "training_samples": 1247
}
```

### Supabase Schema Addition

```sql
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
    outcome_label BOOLEAN,  -- filled later: delivery safe?
    outcome_labeled_at TIMESTAMPTZ,
    labeled_by TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_ml_scores_patient ON ml_risk_scores(patient_id);
CREATE INDEX idx_ml_scores_unlabeled ON ml_risk_scores(outcome_label) WHERE outcome_label IS NULL;
```

### Success Criteria

- ML model ≥70% agreement with rule-based triage on validation set
- Retraining triggered automatically when 200 new labeled outcomes accumulate

---

## Feature 8: GPS Auto-Tag Visit Logs

### What

When CHW opens a patient record, GPS coordinates are automatically captured and stored with the visit.

### Supabase Schema Addition

```sql
ALTER TABLE clinical_contact_logs ADD COLUMN visit_location JSONB;
-- JSONB: {"lat": 12.9716, "lng": 77.5946, "accuracy": 15.0, "timestamp": "2026-05-28T09:30:00Z"}
```

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

- **Feature 1** (ABDM): NHA sandbox credentials at https://abdm.gov.in/developers
- **Feature 2** (Bhashini): Bhashini API key at https://bhashini.gov.in
- **Feature 3** (GPS): Android location permission + `geolocator` package
- **Feature 4** (IVR Transcription): Bhashini STT + Twilio recording webhook
- **Feature 5** (Emergency): Twilio SMS + supervisor/emergency contact in patient record
- **Feature 7** (ML): Training data labels from `ml_risk_scores.outcome_label`

---

## Out of Scope for Phase 2

- Full ABDM HIU certification
- Indic-2 translation (Kannada↔Hindi)
- Zero-phone patient workflow
- 50k concurrent CHW scale testing
- Smart reply for CHW follow-up messages