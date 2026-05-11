# O2 Platform — Phase 2 Requirements (API-Pivoted for Hackathon Demo)

**Date:** 2026-05-11  
**Phase:** 2 (Pilot-Ready Integration)  
**Status:** Requirements — ready for planning  
**Based on:** `docs/ideation/O2-Platform-Phase2-ideation.md`

---

## ⚠️ API Status Summary

| API | Status | Hackathon Alternative |
|-----|--------|-----------------------|
| **NHA/ABDM** | ❌ Unavailable — requires healthcare provider registration | Local ABHA generator with Mod97 validation |
| **Bhashini v3** | ❌ Access not granted | IndicTrans2 (IIT-M AI4Bharat) Docker container |
| **Twilio** | ❌ Access problems | Telegram Bot API |
| **XGBoost** | ✅ Available in local venv | Direct Python import |
| **SQLite** | ✅ User preference for demo | Local SQLite (Supabase for prod) |
| **MiniMax API** | ✅ `MINIMAX_API_KEY` in environment | SBAR generation |

All external API slots have **adapter patterns** — when live credentials arrive, flip the env var, no code rewrite.

---

## API-Pivoted Feature Specs

### Feature 1: Local ABHA Generator (replaces live ABDM/NHA)

**Problem:** NHA sandbox requires active healthcare provider registration — unavailable for hackathon.

**Solution:** Generate valid ABHA numbers locally with Mod97-10 checksum. Validate on registration. When NHA credentials arrive, swap via `USE_LIVE_ABDM=true`.

**Implementation — FastAPI router:**
```python
# apps/o2_backend/routers/abdm.py
from fastapi import APIRouter, HTTPException
from services.abha_generator import generate_abha_number, validate_abha

router = APIRouter(prefix="/abdm", tags=["abdm"])

@router.post("/generate-abha")
def generate_abha():
    """Generate a new valid ABHA number."""
    abha = generate_abha_number()
    return {"abha_number": abha, "valid": True}

@router.post("/validate-abha")
def validate_abha_number(abha: str):
    """Validate ABHA using Mod97-10 algorithm."""
    is_valid = validate_abha(abha)
    if not is_valid:
        raise HTTPException(status_code=400, detail="Invalid ABHA checksum")
    return {"abha_number": abha, "valid": True, "status": "local_verified"}

@router.post("/register-patient")
def register_patient(request: PatientRegistrationRequest):
    """Register patient with locally generated or validated ABHA."""
    abha = request.abha_number
    if not validate_abha(abha):
        raise HTTPException(status_code=400, detail="Invalid ABHA")
    # Store in SQLite
    patient_id = await db.patients.insert({
        "abha_number": abha,
        "name": request.name,
        "phc_id": request.phc_id,
    })
    return {"patient_id": patient_id, "abha": abha}
```

**ABHA Generator service:**
```python
# apps/o2_backend/services/abha_generator.py
import random
import re

def generate_abha_number() -> str:
    """Generate a 14-digit ABHA number with valid Mod97 checksum."""
    prefix = str(random.randint(10**11, 10**12 - 1))
    check = (98 - (int(prefix) % 97)) % 97
    return prefix + f"{check:02d}"

def validate_abha(abha: str) -> bool:
    """Validate ABHA using Mod97-10 algorithm (ISO/IEC 7064)."""
    if not re.match(r'^\d{14}$', abha):
        return False
    return (int(abha) % 97) == 1

def abha_to_uuid(abha: str) -> str:
    """Convert ABHA to UUID-like format for internal IDs."""
    import hashlib
    return hashlib.sha256(abha.encode()).hexdigest()[:32]
```

**Dart side — abdm_service.dart update:**
```dart
// apps/o2_app/lib/abdm/abdm_service.dart
class AbdmService {
  static const _abhaRegex = r'^\d{14}$';
  
  bool validateAbhaChecksum(String abha) {
    if (!RegExp(_abhaRegex).hasMatch(abha)) return false;
    final num = int.parse(abha);
    return num % 97 == 1;
  }
  
  Future<AbhaGenerationResult> generateAbha() async {
    // Call local backend — generates + validates
    final response = await _client.post('/abdm/generate-abha');
    return AbhaGenerationResult.fromJson(response.data);
  }
  
  Future<bool> registerWithAbha(String abha, PatientData patient) async {
    final valid = validateAbhaChecksum(abha);
    if (!valid) return false;
    final response = await _client.post('/abdm/register-patient', data: {
      'abha_number': abha,
      'name': patient.name,
      'phc_id': patient.phcId,
    });
    return response.statusCode == 200;
  }
}
```

**SQLite schema for patients:**
```sql
CREATE TABLE patients (
    id TEXT PRIMARY KEY,
    abha_number TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    emergency_contact TEXT,
    phc_id TEXT NOT NULL,
    created_at TEXT DEFAULT (datetime('now')),
    risk_level TEXT DEFAULT 'LOW'
);
CREATE INDEX idx_patients_abha ON patients(abha_number);
CREATE INDEX idx_patients_phc ON patients(phc_id);
```

**Env var to switch to live ABDM:**
```bash
USE_LIVE_ABDM=false  # true when NHA credentials available
NHA_CLIENT_ID=
NHA_CLIENT_SECRET=
NHA_HMAC_KEY=
NHA_API_BASE_URL=https://abdm.gov.in/api/v1
```

---

### Feature 2: IndicTrans2 STT/TTS (replaces Bhashini)

**Problem:** Bhashini DLI portal not granting access to hackathon teams.

**Solution:** IndicTrans2 (IIT-M AI4Bharat) runs as local Docker container. STT and TTS both from same container.

**Docker setup:**
```bash
# One-time setup
docker pull aiforskill/indictrans2:latest
docker run -d -p 8000:8000 --name indictrans aiforskill/indictrans2:latest

# Health check
curl http://localhost:8000/health
```

**STT — Audio to text:**
```python
# apps/o2_backend/services/indictrans_stt.py
import requests

INDICTRANS_URL = os.getenv("INDICTRANS_URL", "http://localhost:8000")

async def transcribe_audio(audio_path: str, target_lang: str = "kan") -> str:
    """Transcribe audio file to text using IndicTrans2."""
    with open(audio_path, 'rb') as audio_file:
        response = requests.post(
            f"{INDICTRANS_URL}/asr",
            files={"audio": audio_file},
            data={"language": target_lang}
        )
    result = response.json()
    return result.get("text", "")

# Language codes: "kan" (Kannada), "hin" (Hindi), "eng" (English)
```

**TTS — Text to audio:**
```python
# apps/o2_backend/services/indictrans_tts.py

async def synthesize_speech(text: str, lang: str = "kan", output_path: str = "output.wav") -> str:
    """Generate audio from text using IndicTrans2 TTS."""
    response = requests.post(
        f"{INDICTRANS_URL}/tts",
        json={"text": text, "language": lang}
    )
    with open(output_path, 'wb') as f:
        f.write(response.content)
    return output_path
```

**Dart STT service:**
```dart
// apps/o2_app/lib/services/indictrans_stt_service.dart
class IndicTransSttService {
  final String baseUrl;
  
  Future<String> transcribe(File audioFile, String languageCode) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/asr'),
    );
    request.files.add(await http.MultipartFile.fromPath('audio', audioFile.path));
    request.fields['language'] = languageCode; // 'kn', 'hi', 'en'
    
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    final result = jsonDecode(response.body);
    return result['text'] as String;
  }
}
```

**Dart TTS service:**
```dart
// apps/o2_app/lib/services/indictrans_tts_service.dart  
class IndicTransTtsService {
  Future<Uint8List> synthesize(String text, String languageCode) async {
    final response = await http.post(
      Uri.parse('$baseUrl/tts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'language': languageCode}),
    );
    return response.bodyBytes;
  }
}
```

**IVR audio transcription pipeline:**
```
IVR records audio → audio saved locally (wav)
    ↓
FastAPI receives webhook: POST /ivr/transcribe {audio_url}
    ↓
Download audio → IndicTrans2 STT
    ↓
Transcript stored in SQLite: ivr_transcripts table
    ↓
Telegram message sent to CHW: "Patient <ID> left voice message: <transcript>"
```

**SQLite schema for transcripts:**
```sql
CREATE TABLE ivr_transcripts (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    audio_path TEXT,
    transcript_text TEXT,
    language TEXT DEFAULT 'kn',
    created_at TEXT DEFAULT (datetime('now')),
    FOREIGN KEY (patient_id) REFERENCES patients(id)
);
```

**Env vars to switch to Bhashini:**
```bash
USE_BHASHINI=false  # true when Bhashini credentials available
BHASHINI_CLIENT_ID=
BHASHINI_CLIENT_SECRET=
INDICTRANS_URL=http://localhost:8000
```

---

### Feature 3: Telegram Bot for Alerts (replaces Twilio)

**Problem:** Twilio account setup is posing problems for hackathon team.

**Solution:** Telegram Bot API. Free, no phone number needed, reliable.

**Bot setup:**
1. Message @BotFather on Telegram → get bot token
2. Create channel → add bot as admin
3. Get channel ID (format: `-100xxxxxxxxxx`)
4. Add CHW and supervisor Telegram IDs to bot's contact list

**FastAPI Telegram router:**
```python
# apps/o2_backend/routers/telegram_bot.py
import os
import telegram
from telegram import Update
from telegram.ext import Application, CommandHandler, MessageHandler, filters

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
CHANNEL_ID = os.getenv("TELEGRAM_CHANNEL_ID")

async def send_emergency_alert(patient_id: str, risk_level: str, message: str):
    """Send emergency alert to CHW (DM) and supervisor channel."""
    bot = telegram.Bot(token=TELEGRAM_BOT_TOKEN)
    
    alert_text = (
        f"🚨 EMERGENCY ALERT\n"
        f"Patient: {patient_id}\n"
        f"Risk: {risk_level}\n"
        f"Message: {message}\n"
        f"Action: Visit immediately"
    )
    
    # Send to supervisor channel
    await bot.send_message(chat_id=CHANNEL_ID, text=alert_text)

async def send_routine_update(patient_id: str, chw_chat_id: str, message: str):
    """Send routine update to CHW's personal Telegram DM."""
    bot = telegram.Bot(token=TELEGRAM_BOT_TOKEN)
    await bot.send_message(chat_id=chw_chat_id, text=message)

# Telegram bot webhook handler
@router.post("/telegram/webhook")
async def telegram_webhook(update: dict):
    """Handle incoming Telegram messages."""
    message = update.get("message", {})
    chat_id = message.get("chat", {}).get("id")
    text = message.get("text", "")
    
    if text.startswith("/status"):
        patient_id = text.split(" ")[1] if len(text.split(" ")) > 1 else None
        if patient_id:
            patient = await db.patients.get(patient_id)
            risk = patient.get("risk_level", "UNKNOWN")
            await send_routine_update(patient_id, chat_id, 
                f"Patient {patient_id}: Risk level is {risk}")
    
    return {"ok": True}
```

**Dart Telegram service:**
```dart
// apps/o2_app/lib/services/telegram_service.dart
import 'package:http/http.dart' as http;

class TelegramService {
  final String botToken;
  
  TelegramService({required this.botToken});
  
  Future<void> sendMessage(String chatId, String text) async {
    final uri = Uri.parse(
      'https://api.telegram.org/bot$botToken/sendMessage'
    );
    await http.post(uri, body: {
      'chat_id': chatId,
      'text': text,
    });
  }
  
  Future<void> sendEmergencyAlert({
    required String chatId,
    required String patientId,
    required String riskLevel,
    required String message,
  }) async {
    final text = '🚨 EMERGENCY ALERT\n'
        'Patient: $patientId\n'
        'Risk: $riskLevel\n'
        'Message: $message\n'
        'Action: Visit immediately';
    await sendMessage(chatId, text);
  }
}
```

**Multi-recipient alert flow:**
```python
# apps/o2_backend/services/alert_service.py

async def send_clinical_alert(patient: dict, vitals: dict, risk: str):
    """Send alert to CHW, supervisor, and emergency contact via Telegram."""
    
    chw_telegram_id = patient.get("chw_telegram_id")
    supervisor_telegram_id = os.getenv("SUPERVISOR_TELEGRAM_ID")
    emergency_contact_id = patient.get("emergency_contact_telegram")
    
    alert_msg = format_alert(patient, vitals, risk)
    
    # Parallel sends
    tasks = [
        telegram.send_message(chw_telegram_id, alert_msg),
        telegram.send_message(supervisor_telegram_id, alert_msg),
    ]
    
    if emergency_contact_id:
        tasks.append(telegram.send_message(emergency_contact_id, alert_msg))
    
    await asyncio.gather(*tasks)
```

**SQLite schema for Telegram IDs:**
```sql
ALTER TABLE patients ADD COLUMN chw_telegram_id TEXT;
ALTER TABLE patients ADD COLUMN emergency_contact_telegram TEXT;

CREATE TABLE telegram_sessions (
    chw_id TEXT PRIMARY KEY,
    telegram_chat_id TEXT UNIQUE NOT NULL,
    first_name TEXT,
    last_active TEXT
);
```

**Env vars:**
```bash
TELEGRAM_BOT_TOKEN=  # from @BotFather
TELEGRAM_CHANNEL_ID=  # supervisor broadcast channel
SUPERVISOR_TELEGRAM_ID=  # supervisor DM ID
USE_TWILIO=false  # true when Twilio credentials available
```

---

### Feature 4: XGBoost Shadow ML (local, no external API)

**Problem:** Rule-based WHO thresholds are deterministic. XGBoost in venv for shadow ML.

**Solution:** Load XGBoost model from local file. Shadow mode: ML score alongside rule-based score, both returned in API response.

**SQLite schema:**
```sql
CREATE TABLE ml_risk_scores (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    ml_probability REAL,
    rule_based_level TEXT,
    ml_level TEXT,
    features_json TEXT,
    created_at TEXT DEFAULT (datetime('now')),
    outcome_label TEXT,  -- for training: 'safe_delivery', 'referral_needed', 'lost_to_followup'
    FOREIGN KEY (patient_id) REFERENCES patients(id)
);
```

**ML Risk Scorer service:**
```python
# apps/o2_backend/services/ml_risk_scorer.py
import xgboost as xgb
import numpy as np
import json

class XGBoostRiskScorer:
    def __init__(self, model_path: str = "models/risk_model.json"):
        self.model = xgb.XGBClassifier()
        self.model.load_model(model_path)
        self.feature_names = [
            'systolic_bp', 'diastolic_bp', 'heart_rate', 'spo2',
            'temperature', 'weight_kg', 'height_cm', 'age', 'gestation_weeks'
        ]
    
    def extract_features(self, vitals: dict, patient: dict) -> np.ndarray:
        """Build 9-feature vector from vitals and patient data."""
        return np.array([[
            vitals.get('systolic_bp', 0),
            vitals.get('diastolic_bp', 0),
            vitals.get('heart_rate', 0),
            vitals.get('spo2', 0),
            vitals.get('temperature', 0),
            vitals.get('weight_kg', 0),
            patient.get('height_cm', 0),
            patient.get('age', 0),
            vitals.get('gestation_weeks', 0),
        ]])
    
    def predict(self, vitals: dict, patient: dict) -> dict:
        """Shadow ML prediction alongside rule-based."""
        X = self.extract_features(vitals, patient)
        
        # ML probability
        ml_prob = float(self.model.predict_proba(X)[0][1])
        
        # Rule-based (WHO thresholds from Phase 1)
        rule_score = self.rule_based_score(vitals)
        
        # Shadow mode: both returned, rule-based used for decisions
        return {
            "ml_probability": round(ml_prob, 3),
            "ml_level": self._prob_to_level(ml_prob),
            "rule_based_level": rule_score,
            "shadow_mode": True,
            "features": dict(zip(self.feature_names, X[0].tolist()))
        }
    
    def _prob_to_level(self, prob: float) -> str:
        if prob > 0.3:
            return "HIGH"
        elif prob > 0.1:
            return "MEDIUM"
        return "LOW"
    
    def rule_based_score(self, vitals: dict) -> str:
        """WHO maternal health thresholds (Phase 1 logic)."""
        systolic = vitals.get('systolic_bp', 0)
        diastolic = vitals.get('diastolic_bp', 0)
        hr = vitals.get('heart_rate', 0)
        spo2 = vitals.get('spo2', 0)
        
        if systolic >= 160 or diastolic >= 110 or spo2 < 90:
            return "HIGH"
        elif systolic >= 140 or diastolic >= 90 or hr > 100 or spo2 < 95:
            return "MEDIUM"
        return "LOW"
```

**Risk assessment endpoint — both scores returned:**
```python
# apps/o2_backend/routers/risk.py

@router.post("/risk")
async def assess_risk(request: RiskAssessmentRequest):
    patient = await db.patients.get(request.patient_id)
    vitals = request.vitals
    
    # Rule-based (Phase 1)
    rule_result = risk_service.assess(vitals, patient)
    
    # Shadow ML (Phase 2)
    ml_result = xgb_scorer.predict(vitals, patient)
    
    # Log to ml_risk_scores table
    await db.ml_risk_scores.insert({
        "patient_id": request.patient_id,
        "ml_probability": ml_result["ml_probability"],
        "rule_based_level": rule_result["level"],
        "ml_level": ml_result["ml_level"],
        "features_json": json.dumps(ml_result["features"]),
    })
    
    return {
        "patient_id": request.patient_id,
        "rule_based": rule_result,
        "ml_shadow": ml_result,  # included but not used for decisions yet
        "final_decision": rule_result["level"],  # rule-based wins for now
    }
```

**Retraining when outcomes are known:**
```python
# Retrain with newly labeled outcomes
async def retrain_model():
    """Retrain XGBoost model with labeled outcomes from SQLite."""
    outcomes = await db.ml_risk_scores.fetchall(
        "WHERE outcome_label IS NOT NULL"
    )
    if len(outcomes) < 50:
        return {"status": "insufficient_data", "count": len(outcomes)}
    
    X_train = [json.loads(o["features_json"]) for o in outcomes]
    y_train = [1 if o["outcome_label"] == "referral_needed" else 0 for o in outcomes]
    
    model = xgb.XGBClassifier(n_estimators=50, max_depth=4)
    model.fit(X_train, y_train)
    model.save_model("models/risk_model.json")
    return {"status": "retrained", "samples": len(outcomes)}
```

---

### Feature 5: GPS Auto-Tag + Auto-Schedule

**Problem:** No GPS for home visits, manual scheduling.

**Solution:** `geolocator` package for GPS. Risk level drives auto-schedule.

**Dart implementation:**
```dart
// apps/o2_app/lib/services/gps_service.dart
import 'package:geolocator/geolocator.dart';

class GpsService {
  Future<Position?> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return null;
    }
    
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
  
  Future<void> logVisit(String patientId) async {
    final position = await getCurrentPosition();
    if (position == null) return;
    
    await http.post('$BASE_URL/visits/log', json: {
      'patient_id': patientId,
      'latitude': position.latitude,
      'longitude': position.longitude,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

**SQLite visit log schema:**
```sql
CREATE TABLE visits (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    chw_id TEXT NOT NULL,
    recorded_at TEXT DEFAULT (datetime('now')),
    sync_status TEXT DEFAULT 'pending',
    FOREIGN KEY (patient_id) REFERENCES patients(id)
);
CREATE INDEX idx_visits_patient ON visits(patient_id);
CREATE INDEX idx_visits_date ON visits(recorded_at);
```

**Auto-schedule from risk:**
```python
# apps/o2_backend/routers/visits.py

@router.post("/visits/log")
async def log_visit(request: VisitLogRequest):
    """Log GPS-tagged visit and auto-schedule follow-up if HIGH risk."""
    visit_id = generate_uuid()
    await db.visits.insert({
        "id": visit_id,
        "patient_id": request.patient_id,
        "latitude": request.latitude,
        "longitude": request.longitude,
        "chw_id": request.chw_id,
    })
    
    # Auto-schedule based on risk
    patient = await db.patients.get(request.patient_id)
    risk = patient.get("risk_level", "LOW")
    
    if risk == "HIGH":
        follow_up_date = datetime.utcnow() + timedelta(hours=24)
    elif risk == "MEDIUM":
        follow_up_date = datetime.utcnow() + timedelta(days=3)
    else:
        follow_up_date = datetime.utcnow() + timedelta(days=7)
    
    await db.visit_schedules.insert({
        "patient_id": request.patient_id,
        "scheduled_at": follow_up_date.isoformat(),
        "status": "scheduled",
        "auto_generated": True,
    })
    
    return {"visit_id": visit_id, "follow_up_scheduled": follow_up_date.isoformat()}
```

---

## Feature Summary (Updated)

| Feature | Live API | Hackathon Demo | Priority |
|---------|----------|---------------|----------|
| ABHA verification | NHA API | Local Mod97 generator | P1 |
| Voice STT | Bhashini | IndicTrans2 Docker | P1 |
| Voice TTS | Bhashini | IndicTrans2 Docker | P1 |
| Alert notifications | Twilio/WhatsApp | Telegram Bot | P1 |
| ML risk scoring | N/A | XGBoost local venv | P1 |
| GPS auto-tag | N/A | geolocator + SQLite | P1 |
| Auto-schedule | N/A | Risk → schedule logic | P1 |
| IVR transcription | Twilio recording | IndicTrans2 STT | P2 |
| PHC Supervisor dashboard | N/A | Flask + SQLite | P1 |
| Smart reply (follow-up) | N/A | MiniMax API | P2 |

---

## Setup Checklist

1. **Docker:** `docker pull aiforskill/indictrans2:latest && docker run -d -p 8000:8000`
2. **Telegram bot:** Message @BotFather → get bot token → create channel → add bot
3. **Env vars:** Copy `.env.example` → `.env` and fill in tokens
4. **XGBoost model:** Train initial model with synthetic data → save to `models/risk_model.json`
5. **SQLite:** Run schema migrations on first launch