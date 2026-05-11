---
title: "O2 Platform Phase 2 — Hackathon Demo Integration with Local API Alternatives"
date: "2026-05-11"
category: "docs/solutions/architecture-patterns"
module: "o2-backend"
problem_type: "integration_issue"
component: "tooling"
severity: "high"
tags:
  - "o2-platform"
  - "abha"
  - "indictrans"
  - "telegram"
  - "sqlite"
  - "xgboost"
  - "hackathon"
  - "local-api-alternatives"
---

# O2 Platform Phase 2 — Hackathon Demo Integration with Local API Alternatives

## Context

Phase 2 of the O2 Platform maternal healthcare monitoring system needed to be **pilot-ready for a hackathon demo**. External APIs that were part of the Phase 1 architecture became unavailable: NHA/ABDM required healthcare provider registration (not available for hackathon), Bhashini was not granting access, and Twilio was posing integration problems. The challenge was to build a fully functional demo without relying on these external cloud services, while maintaining an adapter pattern so live APIs could be swapped in when credentials arrive.

## Guidance

### 1. Local ABHA Generator with Mod97-10 Validation

ABHA (Ayushman Bharat Health Account) numbers require the ISO/IEC 7064 Mod97-10 checksum algorithm. When the NHA API is unavailable, generate valid ABHAs locally:

```python
# apps/o2_backend/services/abha_generator.py
def generate_abha_number() -> str:
    prefix = str(random.randint(10**11, 10**12 - 1))
    check = (98 - (int(prefix) % 97)) % 97
    return prefix + f"{check:02d}"

def validate_abha(abha: str) -> bool:
    if not re.match(r'^\d{14}$', abha):
        return False
    return (int(abha) % 97) == 1
```

**Adapter pattern**: Set `USE_LIVE_ABDM=true` env var to route to live NHA API — the same function signatures work with either backend.

### 2. IndicTrans2 Docker Container for STT/TTS

Replace Bhashini with a self-hosted IndicTrans2 container (AI4Bharat/IIT-M):

```bash
docker pull aiforskill/indictrans2:latest
docker run -d -p 8000:8000 --name indictrans aiforskill/indictrans2:latest
```

```python
# apps/o2_backend/services/indictrans.py
INDICTRANS_URL = os.getenv("INDICTRANS_URL", "http://localhost:8000")
USE_LOCAL_INDICTRANS = os.getenv("USE_LOCAL_INDICTRANS", "true").lower() == "true"

LANG_MAP = {"kn": "kan", "hi": "hin", "en": "eng", "ta": "tam", "te": "tel"}

async def transcribe_audio(audio_path: str, lang: str = "kn") -> str:
    if not USE_LOCAL_INDICTRANS:
        return "[STT disabled]"
    lang_code = LANG_MAP.get(lang, "kan")
    async with httpx.AsyncClient(timeout=30.0) as client:
        resp = await client.post(f"{INDICTRANS_URL}/asr", ...)
```

### 3. SQLite for Demo Portability

Replace Supabase with SQLite using `aiosqlite` for the hackathon demo:

```python
# apps/o2_backend/services/database.py
async def init_db():
    async with aiosqlite.connect(DB_PATH) as db:
        await db.execute("""
            CREATE TABLE IF NOT EXISTS patients (
                id TEXT PRIMARY KEY,
                abha_number TEXT UNIQUE NOT NULL,
                ...
            )
        """)
```

Repository pattern ensures the same interface works with Supabase when `USE_SUPABASE=true`.

### 4. Telegram Bot for Multi-Recipient Alerts

Replace Twilio with Telegram Bot API — free, no phone number required:

```python
# apps/o2_backend/services/telegram_alerts.py
TELEGRAM_BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN")

ALERT_TIERS = {
    "EMERGENCY": ["chw", "phc_supervisor", "emergency_contact", "regional_hospital"],
    "HIGH": ["chw", "phc_supervisor"],
    "MEDIUM": ["chw", "emergency_contact"],
    "LOW": ["chw"],
}
```

### 5. XGBoost Shadow ML for Risk Scoring

Use the already-installed XGBoost in shadow mode alongside rule-based WHO thresholds:

```python
# apps/o2_backend/services/ml_risk_scorer.py
class XGBoostRiskScorer:
    FEATURES = ["systolic_bp", "diastolic_bp", "heart_rate", "spo2",
                "temperature", "weight_kg", "height_cm", "age", "gestation_weeks"]

    def score(self, vitals: dict, patient: dict = None) -> dict:
        rule_level = self._rule_based_level(vitals)
        ml_prob = self.model.predict_proba(X)[0][1] if self.model else None
        return {
            "ml_probability": ml_prob,
            "ml_level": self._prob_to_level(ml_prob),
            "rule_based_level": rule_level,
            "final_decision": rule_level,  # Always rule-based for clinical decisions
            "shadow_mode": True,
        }
```

### 6. PHC Supervisor HTML Dashboard

Serve a single-file HTML dashboard directly from FastAPI — no frontend framework needed:

```python
# apps/o2_backend/routers/dashboard.py
@router.get("/", response_class=HTMLResponse)
async def get_dashboard():
    return DASHBOARD_HTML  # Inline HTML + JS with auto-refresh every 60s
```

## Why This Matters

1. **Demo portability** — The entire stack runs on a laptop without any external API credentials
2. **Adapter pattern** — `USE_LIVE_*` env vars allow clean swap to production APIs when credentials arrive
3. **Shadow ML approach** — ML scores are computed and logged but not used for clinical decisions until the model is validated on real outcomes
4. **Risk-based auto-scheduling** — GPS visit logging automatically schedules follow-ups based on patient risk level (EMERGENCY=4h, HIGH=24h, MEDIUM=3d, LOW=7d)

## When to Apply

- When external APIs are unavailable for a demo or hackathon context
- When you need a self-contained offline-first system
- When you want to demonstrate the full flow without cloud service dependencies
- When ML models need to run in shadow mode before clinical validation

## Files Implemented

| File | Purpose |
|------|---------|
| `services/abha_generator.py` | Local ABHA generation with Mod97-10 checksum |
| `services/database.py` | SQLite with async repositories (adapter pattern) |
| `services/indictrans.py` | IndicTrans2 Docker STT/TTS client |
| `services/telegram_alerts.py` | Multi-recipient Telegram alert routing |
| `services/ml_risk_scorer.py` | XGBoost shadow ML + WHO rule-based scoring |
| `routers/abdm.py` | FastAPI ABDM router with ABHA endpoints |
| `routers/visits.py` | GPS-tagged visits with auto-scheduling |
| `routers/dashboard.py` | PHC Supervisor HTML dashboard |
| `main.py` | Updated lifespan startup for init_db + init_model |

## Related

- [O2 Platform Phase 1 MVP](docs/solutions/o2-platform-phase1-mvp.md) — foundational architecture
- [O2 Platform Phase 2 Requirements](docs/brainstorms/O2-Platform-Phase2-requirements.md) — full requirements before implementation
- [O2 Platform Phase 2 Plan](docs/plans/2026-05-11-001-feat-o2-platform-phase2-plan.md) — implementation plan with code sketches
