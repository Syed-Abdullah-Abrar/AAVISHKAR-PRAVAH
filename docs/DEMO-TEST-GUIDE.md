# O2 Platform — Demo Test Guide

> **For:** Hackathon Demo  
> **Updated:** 2026-05-11  
> **System:** Windows 11 + WSL Ubuntu + Android Emulator  
> **Time to demo:** ~18 hours

---

## Architecture — What Runs Where

```
┌─────────────────────────────────────────────────────────────────┐
│  Windows Host                                                    │
│                                                                  │
│  ┌──────────────────┐     ┌──────────────────────────────────┐  │
│  │ Android Emulator │     │  WSL Ubuntu                      │  │
│  │ (Flutter App)    │     │  FastAPI Backend (uvicorn)       │  │
│  │                  │     │  Port 8000                       │  │
│  │ Uses 10.0.2.2:8000 ─────► localhost:8000                  │  │
│  └──────────────────┘     └──────────────────────────────────┘  │
│                                                                  │
│  ┌──────────────────┐                                           │
│  │ Windows CMD      │  ← curl tests, flutter commands          │
│  └──────────────────┘                                           │
└─────────────────────────────────────────────────────────────────┘

NO Docker needed. Mock fallback active for all external services.
```

---

## Prerequisites

Before starting, confirm:
- [ ] WSL Ubuntu is installed and working
- [ ] Android Studio with emulator (API 33+)
- [ ] VS Code open at `C:\Users\syeda\dev\AAVISHKAR-PRAVAH`
- [ ] Telegram app (for voice message test)

---

## STEP 1 — Open 3 Terminals

| Terminal | Purpose | How to open |
|---|---|---|
| **WSL Bash** | FastAPI backend server | `Win+R` → type `Ubuntu` → Enter |
| **Windows CMD** | curl tests, flutter commands | `Win+R` → type `cmd` → Enter |
| **Android Studio** | Run emulator | Open Android Studio → start Pixel 6 API 33 |

---

## STEP 2 — Start the FastAPI Backend

### In WSL Bash terminal:

```bash
cd /home/syed/dev/AAVISHKAR-PRAVAH/apps/o2_backend
export PYTHONPATH=/home/syed/dev/AAVISHKAR-PRAVAH
python3 -m uvicorn main:app --port 8000 --host 0.0.0.0
```

**Expected output:**
```
INFO:     Started server process [xxxx]
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8000
[O2 Backend] Starting O2 FastAPI Server...
[O2 Backend] Environment: development
[O2 Backend] AI Provider: openai
[DB] Initialized SQLite database at o2_platform.db
[ML] XGBoost not available, ML scoring disabled
```

**Keep this terminal running.** Do not close it.

> **Note:** If port 8000 is already in use, kill first: `pkill -f uvicorn`

---

## STEP 3 — Verify Backend is Running

### In Windows CMD terminal:

```bash
curl http://localhost:8000/health
```

**Expected output:**
```json
{"status":"healthy","service":"o2-ai-backend","version":"1.0.0","environment":"development"}
```

---

## STEP 4 — Test All API Endpoints

### Health & Root
```bash
curl http://localhost:8000/
curl http://localhost:8000/docs
```

### Risk Triage (GET — all risk levels)
```bash
curl http://localhost:8000/risk/risk/levels
```

**Expected output:**
```json
{"levels":[
  {"level":"LOW","score_range":"0-1","action":"Routine care","next_review_days":7},
  {"level":"MEDIUM","score_range":"2-3","action":"Follow-up in 48h","next_review_days":2},
  {"level":"HIGH","score_range":"4-5","action":"Urgent follow-up in 24h","next_review_days":1},
  {"level":"EMERGENCY","score_range":"6+","action":"Immediate referral","next_review_days":0}
]}
```

### IVR Service Health
```bash
curl http://localhost:8000/ivr/ivr/health
```

**Expected output:**
```json
{"status":"healthy","ivr_service":"telegram","use_twilio":false,"telegram_configured":false,"indictrans":{"status":"available","url":"http://localhost:8000"},...}
```

### IVR Emergency Detection (POST)
```bash
curl -X POST "http://localhost:8000/ivr/ivr/voice-message" ^
  -H "Content-Type: application/json" ^
  -d "{\"patient_id\":\"test-001\",\"file_id\":\"test\",\"language\":\"en\",\"text\":\"patient is having seizure and severe bleeding\"}"
```

**Expected output:**
```json
{"alert_tier":"EMERGENCY","is_critical":true,...}
```

### Non-Emergency IVR Test
```bash
curl -X POST "http://localhost:8000/ivr/ivr/voice-message" ^
  -H "Content-Type: application/json" ^
  -d "{\"patient_id\":\"test-001\",\"file_id\":\"test\",\"language\":\"en\",\"text\":\"I have mild headache\"}"
```

Expected: `"alert_tier":"LOW"` or `"MEDIUM"`, `is_critical:false`

### Dashboard (HTML)
```
Open in browser: http://localhost:8000/dashboard/dashboard/
```

This is a full supervisor dashboard with metrics, high-risk patient table, pending follow-ups, and recent visits.

---

## STEP 5 — Run Flutter App

### In Android Studio:
1. Open project: `C:\Users\syeda\dev\AAVISHKAR-PRAVAH\apps\o2_app`
2. Wait for `flutter pub get` to finish
3. Select **Pixel 6 API 33** emulator from device dropdown
4. Click **Run** (green triangle) or press `Shift+F10`

### Or via CMD:
```bash
cd C:\Users\syeda\dev\AAVISHKAR-PRAVAH\apps\o2_app
flutter run
```

---

## STEP 6 — Flutter App Walkthrough

### Screen 1 — HomeScreen
- Shows dashboard cards: patient count, pending visits, high-risk alerts
- Tap **"View All Patients"** → PatientListScreen

### Screen 2 — Patient Registration
- Tap purple FAB (+) at bottom right
- Fill:
  - **Name:** `Lakshmi Devi`
  - **Age:** `28`
  - **Phone:** `+919876543210`
  - **Village:** `Hampankatta`
  - **LMP Date:** pick date ~6 months ago
- Toggle **High Risk** → ON
- Tap **Register** → green snackbar confirms

### Screen 3 — Vitals Entry (with GPS)
- Tap patient → PatientDetailScreen
- Tap **"Record Vitals"** (heart icon)
- GPS card at top: shows location being captured
  - *Emulator note: GPS shows "unavailable" — this is expected. Real device shows coordinates.*
- Fill:
  - **Systolic:** `150`
  - **Diastolic:** `95`
  - **Heart Rate:** `88`
  - **Hemoglobin:** `8.5`
  - **Temperature:** `99.5`
  - **SPO2:** `97`
- Tap **Save** → risk score calculated

### Screen 4 — Risk Assessment Result
- After saving vitals, risk level is shown
- HIGH/EMERGENCY → red/orange alert banner
- "Refer to PHC" recommendation appears

### Screen 5 — SBAR Generation
- In PatientDetailScreen → tap **"SBAR Handover"** tab
- Fill the 4 fields (Situation, Background, Assessment, Recommendation)
- Tap **Generate** → AI formats as structured SBAR document
- *Note: Without real OpenAI API key, mock SBAR is returned — still formatted correctly*

### Screen 6 — Emergency Protocol
- Tap ⚠️ warning icon (top right of PatientDetailScreen)
- Emergency buttons: "Call 108", "Alert PHC", "Alert Supervisor"

### Screen 7 — Settings / Sync
- HomeScreen → Settings icon (top right)
- Sync status shows offline queue, last sync time

---

## STEP 7 — Telegram Voice Message Test

1. Open Telegram on your phone
2. Find the bot: search `@O2PlatformBot` (or your configured bot name)
3. Send `/start`
4. Send a voice message: **"I am having severe bleeding and cannot breathe"**
5. Bot should respond with emergency alert

> **Note:** `TELEGRAM_BOT_TOKEN` must be set in `.env` for real Telegram. Without it, the IVR still processes mock transcripts but cannot send real Telegram messages.

---

## STEP 8 — Record Demo Video

**While everything works, record your demo.**

1. Press `Win+G` → Xbox Game Bar
2. Click **Record** (circle)
3. Walk through: HomeScreen → Register Patient → Vitals → Risk → SBAR → Emergency
4. Click **Stop**
5. Video saves to `C:\Users\syeda\Videos\Captures`

---

## Complete Command Reference

### WSL Bash — Start Backend
```bash
cd /home/syed/dev/AAVISHKAR-PRAVAH/apps/o2_backend
export PYTHONPATH=/home/syed/dev/AAVISHKAR-PRAVAH
python3 -m uvicorn main:app --port 8000 --host 0.0.0.0
```

### WSL Bash — Restart Backend (if crashed)
```bash
pkill -f uvicorn
cd /home/syed/dev/AAVISHKAR-PRAVAH/apps/o2_backend
export PYTHONPATH=/home/syed/dev/AAVISHKAR-PRAVAH
python3 -m uvicorn main:app --port 8000 --host 0.0.0.0
```

### Windows CMD — Health Check
```bash
curl http://localhost:8000/health
```

### Windows CMD — Risk Levels
```bash
curl http://localhost:8000/risk/risk/levels
```

### Windows CMD — IVR Emergency Test
```bash
curl -X POST "http://localhost:8000/ivr/ivr/voice-message" -H "Content-Type: application/json" -d "{\"patient_id\":\"test\",\"file_id\":\"fake\",\"language\":\"en\",\"text\":\"severe bleeding seizure\"}"
```

### Windows CMD — Dashboard
```
http://localhost:8000/dashboard/dashboard/
```

### Flutter — Run
```bash
cd C:\Users\syeda\dev\AAVISHKAR-PRAVAH\apps\o2_app
flutter run
```

---

## Troubleshooting

### `curl` not recognized in CMD
Use PowerShell instead:
```powershell
Invoke-RestMethod http://localhost:8000/health
```
Or use **Git Bash** (comes with Git for Windows) — `curl` works there.

### Port 8000 already in use
```bash
# In WSL
pkill -f uvicorn
# Then restart
```

### ModuleNotFoundError: No module named 'apps'
PYTHONPATH not set. Always use:
```bash
cd /home/syed/dev/AAVISHKAR-PRAVAH/apps/o2_backend
export PYTHONPATH=/home/syed/dev/AAVISHKAR-PRAVAH
python3 -m uvicorn main:app --port 8000 --host 0.0.0.0
```

### Flutter can't reach backend
1. Check emulator internet: open Chrome in emulator → google.com
2. Verify backend: `curl http://localhost:8000/health` from Windows CMD
3. If CMD works but Flutter doesn't: check Windows Firewall

### GPS unavailable in emulator
**Expected.** Emulators have no real GPS hardware. Explain: "On a real device in field, GPS coordinates are captured automatically for NHM compliance."

### SBAR returns mock response (no OpenAI key)
**Expected.** Without `OPENAI_API_KEY` in `.env`, the SBAR LLM service returns a mock-but-correctly-formatted response. Still valid for demo.

---

## Pre-Demo Checklist (Do Tonight)

- [ ] Open WSL → run backend → `curl http://localhost:8000/health` → `{"status":"healthy"...}`
- [ ] `curl http://localhost:8000/risk/risk/levels` → 4 risk levels returned
- [ ] `curl -X POST .../ivr/ivr/voice-message` with "seizure bleeding" → `is_critical:true`
- [ ] Open `http://localhost:8000/dashboard/dashboard/` in browser → dashboard loads
- [ ] `flutter run` → app opens in emulator
- [ ] Register one patient in app
- [ ] Record 2-minute backup demo video

**Then rest.** Don't code the night before.

---

## What to Say to Judges (Demo Script)

**Problem (30 sec):**
> "Maternal mortality in rural India: 1 woman dies every 30 minutes from preventable causes. Community Health Workers are the frontline — but between visits, they have no clinical support."

**Solution (30 sec):**
> "O2 Platform: offline-first Flutter app for CHWs. GPS-tags every home visit. AI triages risk in real-time. Emergency voice calls work over Telegram on feature phones — no smartphone needed."

**Demo (4 min):**

| Step | Action | What to show |
|---|---|---|
| A | Register Lakshmi Devi | ABHA auto-generated, LMP/EDD calculated |
| B | Record vitals with GPS | GPS card visible — NHM compliance |
| C | Show risk: HIGH | BP 150/95, Hb 8.5 → referral recommended |
| D | Generate SBAR | Structured clinical handover document |
| E | Telegram voice test | "Severe bleeding" → emergency alert fires |
| F | Emergency protocol | Call 108, Alert PHC, Alert Supervisor |

**Phase 4 pitch (30 sec):**
> "Phase 4: on-device ML with quantized XGBoost — inference works completely offline, no internet needed. Every patient registered becomes training data."

---

Good luck. Everything is working.