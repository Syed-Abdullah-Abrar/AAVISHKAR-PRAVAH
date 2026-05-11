# O2 Platform — Phase 2 Implementation Plan (API-Pivoted)

**Date:** 2026-05-11  
**Phase:** 2 (Pilot-Ready Integration)  
**Status:** Implementation Plan — ready to execute  
**Based on:** `docs/ideation/O2-Platform-Phase2-ideation.md` + `docs/brainstorms/O2-Platform-Phase2-requirements.md`

---

## API Pivot Summary

| Original API | Status | Hackathon Alternative |
|-------------|--------|----------------------|
| NHA/ABDM | ❌ Unavailable | Local ABHA generator + Mod97 validation |
| Bhashini v3 | ❌ Access denied | IndicTrans2 Docker (IIT-M AI4Bharat) |
| Twilio | ❌ Access problems | Telegram Bot API |
| XGBoost | ✅ In local venv | Direct Python import |
| Supabase | For prod | SQLite for demo |
| MiniMax API | ✅ In environment | SBAR generation |

---

## Implementation Units

### U1: Local ABHA Generator (replaces live ABDM/NHA)

**What to build:**
1. `apps/o2_backend/services/abha_generator.py` — Mod97-10 ABHA generation and validation
2. `apps/o2_backend/routers/abdm.py` — FastAPI endpoints: `/abdm/generate-abha`, `/abdm/validate-abha`, `/abdm/register-patient`
3. Update `apps/o2_app/lib/abdm/abdm_service.dart` — local validation + backend calls
4. SQLite schema for patients table with ABHA

**Files to create/modify:**
- `apps/o2_backend/services/abha_generator.py` (new)
- `apps/o2_backend/routers/abdm.py` (new)
- `apps/o2_app/lib/abdm/abdm_service.dart` (update)
- `apps/o2_backend/services/database.py` (new — SQLite setup)
- `supabase/schema.sql` (update — add patient table DDL for SQLite migration)

**Code contracts:**

```python
# apps/o2_backend/services/abha_generator.py
import random
import re

def generate_abha_number() -> str:
    """14-digit ABHA with valid Mod97 checksum."""
    prefix = str(random.randint(10**11, 10**12 - 1))
    check = (98 - (int(prefix) % 97)) % 97
    return prefix + f"{check:02d}"

def validate_abha(abha: str) -> bool:
    """Mod97-10 validation (ISO/IEC 7064)."""
    if not re.match(r'^\d{14}$', abha):
        return False
    return (int(abha) % 97) == 1
```

```python
# apps/o2_backend/routers/abdm.py
@router.post("/abdm/generate-abha")
def generate_abha():
    return {"abha_number": generate_abha_number(), "valid": True}

@router.post("/abdm/validate-abha")
def validate_abha(abha: str):
    if not validate_abha(abha):
        raise HTTPException(status_code=400, detail="Invalid ABHA checksum")
    return {"abha_number": abha, "valid": True, "source": "local"}
```

**SQLite schema:**
```sql
CREATE TABLE patients (
    id TEXT PRIMARY KEY,
    abha_number TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    phone TEXT,
    emergency_contact TEXT,
    emergency_contact_phone TEXT,
    chw_telegram_id TEXT,
    emergency_contact_telegram TEXT,
    phc_id TEXT NOT NULL,
    risk_level TEXT DEFAULT 'LOW',
    created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX idx_patients_abha ON patients(abha_number);
CREATE INDEX idx_patients_phc ON patients(phc_id);
```

**Env vars:**
```bash
USE_LIVE_ABDM=false
# Set true + fill NHA vars when credentials arrive
```

**Dependencies:** `aiosqlite` for async SQLite

---

### U2: IndicTrans2 STT/TTS (replaces Bhashini)

**What to build:**
1. `apps/o2_backend/services/indictrans_stt.py` — audio → text
2. `apps/o2_backend/services/indictrans_tts.py` — text → audio
3. `apps/o2_app/lib/services/indictrans_stt_service.dart` (new)
4. `apps/o2_app/lib/services/indictrans_tts_service.dart` (new)
5. IVR transcription pipeline: audio → IndicTrans2 STT → SQLite → Telegram message

**Files to create/modify:**
- `apps/o2_backend/services/indictrans_stt.py` (new)
- `apps/o2_backend/services/indictrans_tts.py` (new)
- `apps/o2_backend/routers/telegram_bot.py` (new — IVR → Telegram pipeline)
- `apps/o2_app/lib/services/indictrans_stt_service.dart` (new)
- `apps/o2_app/lib/services/indictrans_tts_service.dart` (new)
- `ivr_backend/requirements.txt` (add `requests`)

**Code contracts:**

```python
# apps/o2_backend/services/indictrans_stt.py
INDICTRANS_URL = os.getenv("INDICTRANS_URL", "http://localhost:8000")

async def transcribe_audio(audio_path: str, lang: str = "kan") -> str:
    with open(audio_path, 'rb') as f:
        resp = requests.post(
            f"{INDICTRANS_URL}/asr",
            files={"audio": f},
            data={"language": lang}
        )
    return resp.json().get("text", "")

async def transcribe_from_url(audio_url: str, lang: str = "kan") -> str:
    audio_data = requests.get(audio_url).content
    resp = requests.post(
        f"{INDICTRANS_URL}/asr",
        files={"audio": ("recording.wav", audio_data, "audio/wav")},
        data={"language": lang}
    )
    return resp.json().get("text", "")
```

```python
# apps/o2_backend/services/indictrans_tts.py

async def synthesize_speech(text: str, lang: str = "kan", output_path: str = "output.wav") -> str:
    resp = requests.post(
        f"{INDICTRANS_URL}/tts",
        json={"text": text, "language": lang}
    )
    with open(output_path, 'wb') as f:
        f.write(resp.content)
    return output_path
```

**SQLite schema:**
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

**Env vars:**
```bash
INDICTRANS_URL=http://localhost:8000
USE_BHASHINI=false  # true when Bhashini credentials available
```

**Dependencies:** `requests` (add to ivr_backend/requirements.txt and apps/o2_backend/requirements.txt)

**One-time Docker setup:**
```bash
docker pull aiforskill/indictrans2:latest
docker run -d -p 8000:8000 --name indictrans aiforskill/indictrans2:latest
```

---

### U3: GPS Auto-Tag + Auto-Schedule

**What to build:**
1. `apps/o2_app/lib/services/gps_service.dart` — geolocator + visit logging
2. `apps/o2_backend/routers/visits.py` — `/visits/log` endpoint with auto-schedule logic
3. SQLite `visits` table and `visit_schedules` table
4. Update patient model to store GPS of last visit

**Files to create/modify:**
- `apps/o2_app/lib/services/gps_service.dart` (new)
- `apps/o2_backend/routers/visits.py` (new)
- `apps/o2_app/lib/repositories/patient_repository.dart` (update — add visit fields)
- `apps/o2_app/pubspec.yaml` (add `geolocator` dependency)

**Code contracts:**

```dart
// apps/o2_app/lib/services/gps_service.dart
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class GpsService {
  final String baseUrl;
  
  Future<Position?> getCurrentPosition() async {
    bool service = await Geolocator.isLocationServiceEnabled();
    if (!service) return null;
    
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }
  
  Future<void> logVisit(String patientId) async {
    final pos = await getCurrentPosition();
    if (pos == null) return;
    
    await http.post(Uri.parse('$baseUrl/visits/log'), json: {
      'patient_id': patientId,
      'latitude': pos.latitude,
      'longitude': pos.longitude,
      'chw_id': currentChwId,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }
}
```

```python
# apps/o2_backend/routers/visits.py
from datetime import datetime, timedelta

@router.post("/visits/log")
async def log_visit(request: VisitLogRequest):
    visit_id = generate_uuid()
    await db.visits.insert({
        "id": visit_id,
        "patient_id": request.patient_id,
        "latitude": request.latitude,
        "longitude": request.longitude,
        "chw_id": request.chw_id,
    })
    
    # Auto-schedule from risk
    patient = await db.patients.get(request.patient_id)
    risk = patient.get("risk_level", "LOW")
    
    if risk == "HIGH":
        follow_up = datetime.utcnow() + timedelta(hours=24)
    elif risk == "MEDIUM":
        follow_up = datetime.utcnow() + timedelta(days=3)
    else:
        follow_up = datetime.utcnow() + timedelta(days=7)
    
    await db.visit_schedules.insert({
        "patient_id": request.patient_id,
        "scheduled_at": follow_up.isoformat(),
        "status": "scheduled",
        "auto_generated": True,
    })
    
    return {"visit_id": visit_id, "follow_up": follow_up.isoformat()}
```

**SQLite schema:**
```sql
CREATE TABLE visits (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    chw_id TEXT NOT NULL,
    recorded_at TEXT DEFAULT (datetime('now')),
    sync_status TEXT DEFAULT 'synced'
);
CREATE INDEX idx_visits_patient ON visits(patient_id);

CREATE TABLE visit_schedules (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    scheduled_at TEXT NOT NULL,
    status TEXT DEFAULT 'pending',
    auto_generated INTEGER DEFAULT 1,
    created_at TEXT DEFAULT (datetime('now'))
);
```

**Flutter pubspec add:**
```yaml
dependencies:
  geolocator: ^13.0.0
  permission_handler: ^11.3.0
```

**Android manifest add:**
```xml
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

---

### U4: IVR Voice Transcription Pipeline

**What to build:**
1. `ivr_backend/transcriber.py` — IndicTrans2 STT integration with IVR audio files
2. Update `ivr_backend/main.py` to call transcription on recorded audio
3. Telegram message dispatch to CHW with transcript text

**Files to create/modify:**
- `ivr_backend/transcriber.py` (new)
- `ivr_backend/main.py` (update — call transcriber on voice recording)
- `apps/o2_backend/routers/telegram_bot.py` (update — `/telegram/webhook` handler)

**Code contracts:**

```python
# ivr_backend/transcriber.py
import sys
sys.path.insert(0, '/home/syed/dev/AAVISHKAR-PRAVAH/apps/o2_backend')
from services.indictrans_stt import transcribe_from_url
from services.telegram_service import send_transcript_to_chw

async def process_ivr_recording(audio_url: str, patient_id: str, chw_telegram_id: str):
    """Process IVR voice recording: transcribe + send to CHW via Telegram."""
    try:
        transcript = await transcribe_from_url(audio_url, lang="kan")
        
        # Store in SQLite
        await db.ivr_transcripts.insert({
            "id": generate_uuid(),
            "patient_id": patient_id,
            "audio_url": audio_url,
            "transcript_text": transcript,
        })
        
        # Send to CHW via Telegram
        await send_transcript_to_chw(
            chat_id=chw_telegram_id,
            patient_id=patient_id,
            transcript=transcript,
            audio_url=audio_url
        )
        
        return {"status": "success", "transcript": transcript}
    except Exception as e:
        return {"status": "error", "message": str(e)}
```

```python
# ivr_backend/main.py — add to existing IVR flow
from transcriber import process_ivr_recording

@app.post("/ivr/recording-complete")
async def recording_complete(request: RecordingCompleteRequest):
    # existing: save recording to disk
    audio_path = save_recording(request.audio_url)
    
    # NEW: transcribe + send to CHW
    patient = await patient_lookup(request.caller_id)
    if patient:
        result = await process_ivr_recording(
            audio_url=request.audio_url,
            patient_id=patient["id"],
            chw_telegram_id=patient["chw_telegram_id"]
        )
    
    return {"status": "processed"}
```

---

### U5: Multi-Recipient Alerts + XGBoost Shadow ML

**What to build:**
1. `apps/o2_backend/services/alert_service.py` — multi-recipient Telegram alerts
2. `apps/o2_backend/services/ml_risk_scorer.py` — XGBoost shadow ML
3. Update `/risk` endpoint to return both scores
4. SQLite schema for ml_risk_scores

**Files to create/modify:**
- `apps/o2_backend/services/alert_service.py` (new)
- `apps/o2_backend/services/ml_risk_scorer.py` (new)
- `apps/o2_backend/routers/risk.py` (update — add ml_shadow to response)
- `apps/o2_backend/routers/sbar.py` (update — use risk from ml_risk_scorer)

**Code contracts:**

```python
# apps/o2_backend/services/alert_service.py
import telegram
import os

TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")
SUPERVISOR_CHAT_ID = os.getenv("SUPERVISOR_TELEGRAM_ID")

async def send_clinical_alert(patient: dict, vitals: dict, risk_level: str):
    """Send alert to CHW + supervisor + emergency contact via Telegram."""
    alert_text = format_clinical_alert(patient, vitals, risk_level)
    
    bot = telegram.Bot(token=TELEGRAM_BOT_TOKEN)
    
    recipients = [
        patient.get("chw_telegram_id"),
        SUPERVISOR_CHAT_ID,
        patient.get("emergency_contact_telegram"),
    ]
    
    await asyncio.gather(*[
        bot.send_message(chat_id=cid, text=alert_text)
        for cid in recipients if cid
    ])

def format_clinical_alert(patient, vitals, risk) -> str:
    return (
        f"🚨 CLINICAL ALERT\n"
        f"Patient: {patient.get('name')} ({patient.get('abha_number')})\n"
        f"Risk Level: {risk}\n"
        f"Vitals: BP {vitals.get('systolic_bp')}/{vitals.get('diastolic_bp')}, "
        f"HR {vitals.get('heart_rate')}, SpO2 {vitals.get('spo2')}\n"
        f"Action: {'EMERGENCY - visit immediately' if risk == 'HIGH' else 'Schedule within 24h'}"
    )
```

```python
# apps/o2_backend/services/ml_risk_scorer.py
import xgboost as xgb
import numpy as np

class XGBoostRiskScorer:
    def __init__(self, model_path: str = "models/risk_model.json"):
        self.model = xgb.XGBClassifier()
        self.model.load_model(model_path)
        self.features = [
            'systolic_bp', 'diastolic_bp', 'heart_rate', 'spo2',
            'temperature', 'weight_kg', 'height_cm', 'age', 'gestation_weeks'
        ]
    
    def predict(self, vitals: dict, patient: dict) -> dict:
        X = np.array([[vitals.get(f, 0) for f in self.features]])
        prob = float(self.model.predict_proba(X)[0][1])
        return {
            "ml_probability": round(prob, 3),
            "ml_level": "HIGH" if prob > 0.3 else "MEDIUM" if prob > 0.1 else "LOW",
            "features": dict(zip(self.features, X[0].tolist()))
        }
    
    def rule_based(self, vitals: dict) -> str:
        s, d, hr, spo2 = (vitals.get(k, 0) for k in 
            ['systolic_bp', 'diastolic_bp', 'heart_rate', 'spo2'])
        if s >= 160 or d >= 110 or spo2 < 90:
            return "HIGH"
        if s >= 140 or d >= 90 or hr > 100 or spo2 < 95:
            return "MEDIUM"
        return "LOW"
```

**SQLite schema:**
```sql
CREATE TABLE ml_risk_scores (
    id TEXT PRIMARY KEY,
    patient_id TEXT NOT NULL,
    ml_probability REAL,
    rule_based_level TEXT,
    ml_level TEXT,
    features_json TEXT,
    outcome_label TEXT,
    created_at TEXT DEFAULT (datetime('now'))
);
CREATE INDEX idx_ml_patient ON ml_risk_scores(patient_id);
```

**Env vars:**
```bash
TELEGRAM_BOT_TOKEN=
SUPERVISOR_TELEGRAM_ID=
```

**XGBoost model file:** `models/risk_model.json` — train with synthetic data before demo

---

### U6: PHC Supervisor Dashboard

**What to build:**
1. `apps/o2_backend/routers/dashboard.py` — Flask HTML dashboard
2. `apps/o2_backend/routers/summary.py` — aggregate stats endpoints
3. `templates/supervisor_dashboard.html` — HTML/JS dashboard (single file, no frontend framework needed)
4. `apps/o2_backend/services/ml_risk_scorer.py` — already exists from U5

**Files to create/modify:**
- `apps/o2_backend/routers/dashboard.py` (new)
- `apps/o2_backend/routers/summary.py` (new)
- `templates/supervisor_dashboard.html` (new)
- `apps/o2_backend/main.py` (update — register dashboard routes)

**Code contracts:**

```python
# apps/o2_backend/routers/dashboard.py
from fastapi import FastAPI, Request
from fastapi.responses import HTMLResponse
import os

router = APIRouter()

@router.get("/dashboard", response_class=HTMLResponse)
async def supervisor_dashboard():
    with open("templates/supervisor_dashboard.html") as f:
        return f.read()

@router.get("/api/summary")
async def get_summary(phc_id: str):
    patients = await db.patients.fetchall(
        "WHERE phc_id = ?", (phc_id,)
    )
    high_risk = [p for p in patients if p.get("risk_level") == "HIGH"]
    medium_risk = [p for p in patients if p.get("risk_level") == "MEDIUM"]
    
    return {
        "total_patients": len(patients),
        "high_risk": len(high_risk),
        "medium_risk": len(medium_risk),
        "low_risk": len(patients) - len(high_risk) - len(medium_risk),
        "recent_visits": await db.visits.fetchall(
            "WHERE recorded_at > datetime('now', '-7 days')"
        ),
        "scheduled_follow_ups": await db.visit_schedules.fetchall(
            "WHERE scheduled_at > datetime('now') AND status = 'pending'"
        )
    }

@router.get("/api/patients/high-risk")
async def get_high_risk_patients(phc_id: str):
    return await db.patients.fetchall(
        "WHERE phc_id = ? AND risk_level = 'HIGH'", (phc_id,)
    )
```

```html
<!-- templates/supervisor_dashboard.html -->
<!DOCTYPE html>
<html>
<head>
  <title>PHC Supervisor Dashboard — O2 Platform</title>
  <meta charset="utf-8">
  <style>
    body { font-family: system-ui, sans-serif; margin: 40px; background: #f5f5f5; }
    .card { background: white; border-radius: 12px; padding: 24px; margin: 16px 0; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    .metric { display: inline-block; margin: 16px 32px; }
    .metric-value { font-size: 48px; font-weight: 700; }
    .metric-label { font-size: 14px; color: #666; text-transform: uppercase; }
    .high-risk { color: #dc2626; }
    .medium-risk { color: #f59e0b; }
    .low-risk { color: #16a34a; }
    table { width: 100%; border-collapse: collapse; }
    th, td { padding: 12px; text-align: left; border-bottom: 1px solid #eee; }
    th { background: #fafafa; }
  </style>
</head>
<body>
  <h1>📊 PHC Supervisor Dashboard</h1>
  <div id="summary"></div>
  <div id="high-risk-list"></div>
  <script>
    async function loadDashboard() {
      const resp = await fetch('/api/summary?phc_id=PHC001');
      const data = await resp.json();
      
      document.getElementById('summary').innerHTML = `
        <div class="card">
          <div class="metric">
            <div class="metric-value">${data.total_patients}</div>
            <div class="metric-label">Total Patients</div>
          </div>
          <div class="metric">
            <div class="metric-value high-risk">${data.high_risk}</div>
            <div class="metric-label">High Risk</div>
          </div>
          <div class="metric">
            <div class="metric-value medium-risk">${data.medium_risk}</div>
            <div class="metric-label">Medium Risk</div>
          </div>
          <div class="metric">
            <div class="metric-value low-risk">${data.low_risk}</div>
            <div class="metric-label">Low Risk</div>
          </div>
        </div>
      `;
      
      const patients = await fetch('/api/patients/high-risk?phc_id=PHC001').then(r => r.json());
      document.getElementById('high-risk-list').innerHTML = `
        <div class="card">
          <h2>🚨 High Risk Patients</h2>
          <table>
            <tr><th>Name</th><th>ABHA</th><th>Risk</th><th>Last Visit</th></tr>
            ${patients.map(p => `<tr><td>${p.name}</td><td>${p.abha_number}</td><td>${p.risk_level}</td><td>${p.last_visit || 'N/A'}</td></tr>`).join('')}
          </table>
        </div>
      `;
    }
    loadDashboard();
  </script>
</body>
</html>
```

**Env vars:**
```bash
SUPERVISOR_DASHBOARD_PORT=8080
SUPERVISOR_PHC_ID=PHC001  # for demo, single PHC
```

**Access:** `http://localhost:8080/dashboard` in browser

---

## SQLite Setup (Demo Database)

```python
# apps/o2_backend/services/database.py
import aiosqlite, os

DB_PATH = os.getenv("DB_PATH", "o2_platform.db")

async def init_db():
    async with aiosqlite.connect(DB_PATH) as db:
        await db.executescript("""
            CREATE TABLE IF NOT EXISTS patients (
                id TEXT PRIMARY KEY,
                abha_number TEXT UNIQUE NOT NULL,
                name TEXT NOT NULL,
                phone TEXT,
                emergency_contact TEXT,
                emergency_contact_phone TEXT,
                chw_telegram_id TEXT,
                emergency_contact_telegram TEXT,
                phc_id TEXT NOT NULL,
                risk_level TEXT DEFAULT 'LOW',
                created_at TEXT DEFAULT (datetime('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_patients_abha ON patients(abha_number);
            CREATE INDEX IF NOT EXISTS idx_patients_phc ON patients(phc_id);
            
            CREATE TABLE IF NOT EXISTS vitals (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                systolic_bp INTEGER,
                diastolic_bp INTEGER,
                heart_rate INTEGER,
                spo2 INTEGER,
                temperature REAL,
                recorded_at TEXT DEFAULT (datetime('now'))
            );
            
            CREATE TABLE IF NOT EXISTS visits (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                latitude REAL NOT NULL,
                longitude REAL NOT NULL,
                chw_id TEXT NOT NULL,
                recorded_at TEXT DEFAULT (datetime('now')),
                sync_status TEXT DEFAULT 'synced'
            );
            CREATE INDEX IF NOT EXISTS idx_visits_patient ON visits(patient_id);
            
            CREATE TABLE IF NOT EXISTS visit_schedules (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                scheduled_at TEXT NOT NULL,
                status TEXT DEFAULT 'pending',
                auto_generated INTEGER DEFAULT 1
            );
            
            CREATE TABLE IF NOT EXISTS ivr_transcripts (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                audio_path TEXT,
                transcript_text TEXT,
                language TEXT DEFAULT 'kn',
                created_at TEXT DEFAULT (datetime('now'))
            );
            
            CREATE TABLE IF NOT EXISTS ml_risk_scores (
                id TEXT PRIMARY KEY,
                patient_id TEXT NOT NULL,
                ml_probability REAL,
                rule_based_level TEXT,
                ml_level TEXT,
                features_json TEXT,
                outcome_label TEXT,
                created_at TEXT DEFAULT (datetime('now'))
            );
        """)
```

---

## Dependencies (Updated)

**Python (apps/o2_backend/requirements.txt):**
```
fastapi==0.115.0
uvicorn[standard]==0.30.0
pydantic==2.9.0
fhir.resources==7.1.0
aiosqlite==0.20.0
requests==2.32.0
xgboost==2.1.0
python-telegram-bot==21.0.0
```

**Flutter (apps/o2_app/pubspec.yaml):**
```yaml
dependencies:
  geolocator: ^13.0.0
  permission_handler: ^11.3.0
  http: ^1.2.0
  # existing: brick, flutter_bloc, etc.
```

**IVR backend (ivr_backend/requirements.txt):**
```
fastapi==0.115.0
uvicorn==0.30.0
requests==2.32.0
twilio==9.0.0
```

**One-time setup commands:**
```bash
# 1. Clone repo and setup venv
cd /home/syed/dev/AAVISHKAR-PRAVAH
python3 -m venv venv
source venv/bin/activate
pip install -r apps/o2_backend/requirements.txt

# 2. Pull IndicTrans2 Docker
docker pull aiforskill/indictrans2:latest
docker run -d -p 8000:8000 --name indictrans aiforskill/indictrans2:latest

# 3. Setup Telegram bot
# Message @BotFather → /newbot → get token
# Create channel → add bot as admin → get channel ID

# 4. Initialize SQLite DB
cd apps/o2_backend
python -c "import asyncio; from services.database import init_db; asyncio.run(init_db())"

# 5. Train initial XGBoost model with synthetic data
python -c "from services.ml_risk_scorer import XGBoostRiskScorer; import json, numpy as np; m=XGBoostRiskScorer(); m.model.fit(np.random.rand(100,9), np.random.randint(0,2,100)); m.model.save_model('models/risk_model.json')"

# 6. Start backend
uvicorn main:app --reload --port 8000

# 7. Start IVR backend
cd /home/syed/dev/AAVISHKAR-PRAVAH/ivr_backend
uvicorn main:app --reload --port 8001

# 8. Run Flutter app
cd /home/syed/dev/AAVISHKAR-PRAVAH/apps/o2_app
flutter run
```

---

## Execution Order

1. **U1** (ABHA generator) — foundation for patient registration
2. **U3** (GPS + auto-schedule) — immediate value for CHW workflow
3. **U5** (XGBoost ML + alerts) — core clinical logic
4. **U2** (IndicTrans2) — voice pipeline
5. **U4** (IVR transcription) — uses U2
6. **U6** (Supervisor dashboard) — last, needs all data populated

---

*Plan generated: 2026-05-11*
*API pivot applied: NHA unavailable → local ABHA, Bhashini blocked → IndicTrans2, Twilio problematic → Telegram*