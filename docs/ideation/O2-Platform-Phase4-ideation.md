# O2 Platform — Phase 4 Ideation

> **Date:** 2026-05-12  
> **Subject:** Phase 4 — On-device ML, Repository Wiring, Security Hardening, Production Readiness  
> **Status:** Draft — For Hackathon Demo

---

## Subject

Phase 4 of O2 Platform: making the system production-ready for pilot deployment with offline ML inference, data persistence wiring, security hardening, and Flutter production-readiness.

---

## Grounding Context

### Codebase Context

**Project:** O2 Platform — Offline-first maternal healthcare monitoring for CHWs in India

**Stack:**
- Flutter (mobile app) — `apps/o2_app/`
- FastAPI (AI backend) — `apps/o2_backend/`
- Supabase (sync target) — `supabase/`
- XGBoost ML model — `apps/o2_backend/models/risk_model.json` (50 trees, no feature names)

**Existing Flutter structure:**
- `lib/core/router.dart` — 10 full StatefulWidget screens
- `lib/ml/` — NEW: ML module for Phase 4
- `lib/repositories/` — PatientRepository, VitalsRepository (Brick offline-first)
- `lib/services/` — Telegram, Location, IndicTrans, Sync, Encryption, FHIR

**Existing Android gap:** No `android/` directory scaffolded yet — Flutter project incomplete

**Security gap:** Telegram bot token hardcoded in `constants.dart` line 37

**ML gap:** No XGBoost inference in Flutter — only backend has it

---

## Topic Axes

1. **On-device ML inference** — Running XGBoost model in Flutter for zero-internet risk scoring
2. **Repository wiring** — Connecting UI screens to actual SQLite persistence + Supabase sync
3. **Security hardening** — Moving secrets out of source code into secure storage
4. **Android permissions** — Explicit manifest declarations for GPS, mic, internet
5. **Production deployment** — Supabase schema, error handling, voice recording

---

## Ideas

### 1. WHO Rule-Based + XGBoost Fallback (AXIS: On-device ML inference)

**Title:** Dual-mode risk inference engine

**Summary:** Implement WHO rule-based thresholds (LOW/MEDIUM/HIGH/EMERGENCY) as the primary inference engine in Flutter — no model loading needed, works immediately. When the XGBoost `.json` model is bundled in assets, use it for enhanced probabilistic scoring. Falls back to WHO rules if model unavailable.

**Basis:** `direct:` `apps/o2_backend/models/risk_model.json` — 50-tree XGBoost already exists but lacks feature names; WHO thresholds are well-documented and implementable in pure Dart.

**Why it matters:** Zero-internet risk inference works from day one without ML model deployment. XGBoost adds probabilistic confidence scoring on top. Judges see real ML pipeline with WHO as baseline.

**Meeting test:** Should we ship with WHO-only or require the XGBoost pipeline to be complete first?

---

### 2. Bundle XGBoost JSON as Flutter Asset (AXIS: On-device ML inference)

**Title:** `assets/ml/risk_model.json` bundled in APK

**Summary:** Copy `apps/o2_backend/models/risk_model.json` → `apps/o2_app/assets/ml/risk_model.json`. Load at app startup via `rootBundle`. XGBoostInference engine traverses the JSON tree structure directly in Dart — no native bindings needed.

**Basis:** `direct:` XGBoost model stored as JSON with `trees[]`, `split_conditions[]`, `base_weights[]` — all traversable in pure Dart without platform channels.

**Why it matters:** The existing model can be used immediately without retraining or conversion. Pure Dart means no iOS/Android native code complexity.

**Meeting test:** Does bundling the JSON increase APK size materially?

---

### 3. Token Injection at First Launch (AXIS: Security hardening)

**Title:** Secure onboarding flow for secrets

**Summary:** On first app launch, prompt CHW/ASHA to enter Telegram bot token and Supabase credentials. Store immediately in `FlutterSecureStorage`. All subsequent API calls read from secure storage, never from source.

**Basis:** `direct:` `constants.dart` line 37 has hardcoded Telegram token; `SecureStorageService` created in Phase 4 provides the storage layer.

**Why it matters:** Token in source code means anyone with repo access or APK binary can extract it. Secure storage uses Android Keystore — hardware-backed encryption on modern devices.

**Meeting test:** Should we provide a QR-code setup flow for supervisors to push tokens to CHW devices, or is manual entry acceptable?

---

### 4. Permission Request Flow at First Record (AXIS: Android permissions)

**Title:** Progressive permission requests

**Summary:** Don't ask for all permissions at install. At the moment the CHW tries to record their first vitals (requires GPS), show a clear explanation card: "O2 Platform needs your location to tag visits as required by NHM guidelines. Your data is encrypted and never shared." Then request `ACCESS_FINE_LOCATION`. Similarly for microphone when first voice message is recorded.

**Basis:** `reasoned:` Users decline permissions when asked out of context. Contextual permission requests at point-of-need have 3-5x higher acceptance rates (Android developer documentation).

**Why it matters:** GPS is the NHM compliance killer feature. If CHW denies it, the app loses its most important differentiator. Progressive disclosure reduces denial rates.

**Meeting test:** Should we block the specific feature (vitals save) or just warn when GPS is denied?

---

### 5. Offline-first Dashboard Aggregation (AXIS: Repository wiring)

**Title:** Aggregate risk counts from local SQLite, not backend

**Summary:** `HomeScreen` currently shows placeholder numbers. Wire it to `PatientRepository` to count HIGH/EMERGENCY patients from local SQLite. This works completely offline — no internet required to show the dashboard.

**Basis:** `direct:` `PatientRepository` and `VitalsRepository` already exist in codebase with `get()` methods returning local-first data.

**Why it matters:** The dashboard is the first thing judges see. Placeholder numbers look unfinished. Real local aggregation shows the offline-first architecture actually works.

**Meeting test:** Should the dashboard sync counts to Supabase for supervisor web view, or stay purely local?

---

### 6. Error Screen as State Not Route (AXIS: Production deployment)

**Title:** Error boundaries on every screen

**Summary:** Wrap every `FutureBuilder` and async operation in error boundaries. When an error occurs, show a contextual error card on the same screen (like "Couldn't load patients — check your internet"). Don't navigate to a separate ErrorScreen — the error should be inline and recoverable.

**Basis:** `reasoned:` CHWs work in low-connectivity environments. Errors are expected, not exceptional. Sending them to a full error page breaks context and increases abandonment.

**Why it matters:** Judges notice how the app behaves when things go wrong. A graceful error card demonstrates understanding of the target environment. A crash-to-error-screen is jarring and looks unpolished.

**Meeting test:** Should we also log errors to a local `error_logs` table for later debugging?

---

### 7. Voice Message → Telegram → IVR Chain (AXIS: Production deployment)

**Title:** End-to-end voice pipeline demo

**Summary:** CHW opens voice recording screen → records audio → `record` package saves locally → forwarded to `TelegramService` → Telegram bot receives → IVR backend processes → CHW gets transcript + risk tier back. All wired together with proper error handling at each step.

**Basis:** `direct:` `TelegramService.forwardVoiceMessage()` already calls `/ivr/ivr/voice-message` endpoint; `record` package already in `pubspec.yaml`.

**Why it matters:** This is the most visually impressive flow in the entire app. Judges can see the feature phone accessibility story — patient sends voice, CHW gets structured data. It requires all pieces working together.

**Meeting test:** Should the voice message auto-play the response or require manual tap?

---

## Rejected Ideas

| Idea | Reason for Rejection |
|------|---------------------|
| Train new XGBoost model from scratch | No labeled NFHS dataset available; requires 4-6 weeks minimum |
| Implement FHIR Subscription push from Supabase | Supabase not deployed; requires real Supabase project first |
| Multi-language (Kannada/Hindi) UI | Out of scope for Phase 4 pilot; defer to Phase 5 |
| iOS build | No Mac available; out of scope for hackathon |
| Real Bhashini STT/TTS | API credentials not available; mock already in place |

---

## Chosen Direction for Phase 4

**Implement in priority order:**

1. ✅ **4.1 WHO rule-based scorer** — Pure Dart, zero dependencies, works immediately
2. ✅ **4.2 XGBoost inference class** — Loads bundled JSON, fallback to WHO rules
3. ✅ **4.3 SecureStorageService** — Token moved from source → secure storage
4. ✅ **4.4 TelegramService rewrite** — Reads token from SecureStorageService
5. ✅ **4.5 VitalsRepository.saveVitalsWithRisk()** — Repository wired with risk assessment
6. ⏳ **4.6 AndroidManifest permissions** — Deferred (android/ not scaffolded)
7. ⏳ **4.7 Error handling** — Deferred to Phase 4 post-hackathon

**For hackathon demo:** Focus on items 1-5. Items 6-7 are important but won't affect the pitch demo flow.