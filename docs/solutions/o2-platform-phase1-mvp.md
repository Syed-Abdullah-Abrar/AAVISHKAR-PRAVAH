# O2 Platform — Phase 1 MVP: Architecture & Decisions

**Date**: 2026-05-11  
**Phase**: MVP (Unit 1–6)  
**Status**: ✅ Implemented

---

## Problem Statement

Maternal healthcare monitoring is insufficient in low-resource regions. ASHA workers (Community Health Workers / CHWs) in rural India need a mobile-first tool that works offline, integrates with India's health infrastructure (ABDM/ABHA), and provides clinical decision support — all within a 24-hour hackathon window.

---

## Architectural Decisions

### 1. FHIR R4 as Canonical Format

**Decision**: All O2 domain models serialize to FHIR R4 native types (Patient, Observation, DocumentReference) rather than proprietary JSON.

**Rationale**:
- Eliminates impedance mismatch between app models and backend AI services
- Enables future FHIR server integration (HIE-on-FHIR)
- `fhir` Dart package provides native deserialization

**Implementation**: [`lib/models/patient.dart`](apps/o2_app/lib/models/patient.dart) → `Patient`, [`lib/models/vitals.dart`](apps/o2_app/lib/models/vitals.dart) → `Observation`, [`lib/services/fhir_serializer.dart`](apps/o2_app/lib/services/fhir_serializer.dart) for bidirectional conversion.

---

### 2. SQLCipher + Android Keystore Encryption

**Decision**: Local SQLite database encrypted with AES-256 via SQLCipher. Encryption key generated on first launch and stored in hardware-backed Android Keystore via platform channel.

**Rationale**:
- Patient data is PHI — must be encrypted at rest
- Hardware-backed Keystore resists root/tamper attacks
- SQLCipher provides transparent encryption without app-level byte handling

**Implementation**: [`lib/services/encryption_service.dart`](apps/o2_app/lib/services/encryption_service.dart) — `_getOrCreateEncryptionKey()` checks Keystore first, falls back to `_getOrCreateKeyFallback()` on emulators.

---

### 3. WorkManager Sync with Constraints

**Decision**: Background sync runs via WorkManager with `NetworkType.unmetered` + `requiresCharging: true`.

**Rationale**:
- Rural CHWs have limited, expensive data
- Sync only on WiFi prevents cellular bill shock
- Charging constraint prevents battery drain during sync

**Implementation**: [`lib/services/sync_service.dart`](apps/o2_app/lib/services/sync_service.dart) — periodic task with 15-minute flex window.

---

### 4. PHC-Based RLS Isolation

**Decision**: Supabase Row Level Security policies use a `get_user_phc_ids()` SQL function that returns all PHC IDs assigned to the authenticated CHW.

**Rationale**:
- CHWs serve specific PHC catchment areas
- No cross-PHC data leakage
- Policy-level enforcement regardless of app-layer queries

**Implementation**: [`supabase/rls_policies.sql`](supabase/rls_policies.sql) — `patients`, `vitals_logs`, `clinical_contact_logs` all use `phc_id = ANY(get_user_phc_ids())`.

---

### 5. Traffic-Light Triage (Rule-Based)

**Decision**: Risk scoring uses deterministic WHO maternal health thresholds (not ML) for Phase 1. Four tiers: Low / Medium / High / Emergency.

**Rationale**:
- 24-hour MVP: no time for model training/tuning
- WHO thresholds are clinically validated and explainable
- Easy to escalate to LLM-based risk in Phase 2

**Thresholds** (see [`apps/o2_backend/services/risk_model.py`](apps/o2_backend/services/risk_model.py)):
- BP Systolic ≥ 160 → Emergency
- BP Diastolic ≥ 100 → Emergency
- Hemoglobin < 7 g/dL → Emergency
- Weight gain > 0.5 kg/week in 3rd trimester → High risk

---

### 6. SBAR LLM with Strict JSON Schema

**Decision**: SBAR generation uses OpenAI/Anthropic with enforced JSON schema output via `response_format=json_schema` (Pydantic model binding).

**Rationale**:
- Clinical summaries must be structured for EHR ingestion
- Unstructured text risks misinterpretation
- Schema enforcement prevents malformed output

**Implementation**: [`apps/o2_backend/services/sbar_llm.py`](apps/o2_backend/services/sbar_llm.py) — `SBAR_SYSTEM_PROMPT` with JSON output instructions, Section-to-Meta pattern for structure.

---

### 7. IVR Missed-Call Routing

**Decision**: Single toll-free number routes by caller ID (CLI) to patient record → CHW WhatsApp. No per-patient DID provisioning.

**Flow**:
1. Patient gives missed call to toll-free number
2. Twilio webhook hits `/twilio/missed-call` with CLI
3. `patient_lookup.py` maps CLI → patient → CHW WhatsApp number
4. System calls patient back (free)
5. Patient records voice message
6. Twilio forwards recording URL to `whatsapp_sender.py`
7. CHW receives WhatsApp voice note

**Implementation**: [`ivr_backend/main.py`](ivr_backend/main.py), [`ivr_backend/patient_lookup.py`](ivr_backend/patient_lookup.py), [`ivr_backend/whatsapp_sender.py`](ivr_backend/whatsapp_sender.py).

---

### 8. ABDM Mock with Mod 97 Checksum

**Decision**: ABHA ID validation uses local Mod 97 checksum (ISO 7064) rather than calling ABDM NHA server.

**Rationale**:
- Offline MVP: no external network dependency for validation
- Mod 97 is the official ABHA checksum algorithm
- Phase 2 can upgrade to real NHA API calls

**Implementation**: [`lib/abdm/abdm_service.dart`](apps/o2_app/lib/abdm/abdm_service.dart) — `_validateChecksum()`: `number % 97 == 1`.

---

## Files Created

### Flutter App (`apps/o2_app/`)
| File | Purpose |
|------|---------|
| [`pubspec.yaml`](apps/o2_app/pubspec.yaml) | Dependencies: brick_offline_first_with_supabase, sqflite_sqlcipher, workmanager, fhir, flutter_riverpod, go_router |
| [`lib/core/constants.dart`](apps/o2_app/lib/core/constants.dart) | API endpoints, sync intervals, emergency keywords (EN/KN/HI), risk thresholds |
| [`lib/core/theme.dart`](apps/o2_app/lib/core/theme.dart) | Material 3 theme with traffic-light risk colors |
| [`lib/core/router.dart`](apps/o2_app/lib/core/router.dart) | GoRouter with all screen routes |
| [`lib/models/patient.dart`](apps/o2_app/lib/models/patient.dart) | Patient model with FHIR R4 serialization |
| [`lib/models/vitals.dart`](apps/o2_app/lib/models/vitals.dart) | Vitals (Observation) with clinical flag detection |
| [`lib/models/clinical_contact.dart`](apps/o2_app/lib/models/clinical_contact.dart) | Clinical contact log |
| [`lib/services/encryption_service.dart`](apps/o2_app/lib/services/encryption_service.dart) | SQLCipher + Android Keystore key management |
| [`lib/services/sync_service.dart`](apps/o2_app/lib/services/sync_service.dart) | WorkManager periodic sync |
| [`lib/services/fhir_serializer.dart`](apps/o2_app/lib/services/fhir_serializer.dart) | FHIR ↔ O2 model conversion |
| [`lib/repositories/patient_repository.dart`](apps/o2_app/lib/repositories/patient_repository.dart) | Brick offline-first repository |
| [`lib/repositories/vitals_repository.dart`](apps/o2_app/lib/repositories/vitals_repository.dart) | Vitals with trend analysis |
| [`lib/abdm/abdm_service.dart`](apps/o2_app/lib/abdm/abdm_service.dart) | ABDM mock with Mod 97 validation |
| [`lib/app.dart`](apps/o2_app/lib/app.dart) | Riverpod ProviderScope, theme, router setup |
| [`lib/main.dart`](apps/o2_app/lib/main.dart) | App entry point |

### Supabase (`supabase/`)
| File | Purpose |
|------|---------|
| [`schema.sql`](supabase/schema.sql) | Tables: phc_hierarchy, chw_assignments, patients, vitals_logs, clinical_contact_logs, sbar_documents |
| [`rls_policies.sql`](supabase/rls_policies.sql) | PHC-based RLS isolation via `get_user_phc_ids()` |

### FastAPI Backend (`apps/o2_backend/`)
| File | Purpose |
|------|---------|
| [`main.py`](apps/o2_backend/main.py) | FastAPI app, CORS, routers for /risk and /sbar |
| [`routers/risk.py`](apps/o2_backend/routers/risk.py) | `POST /risk` — traffic-light triage |
| [`routers/sbar.py`](apps/o2_backend/routers/sbar.py) | `POST /sbar` — LLM clinical summary |
| [`services/risk_model.py`](apps/o2_backend/services/risk_model.py) | WHO threshold rule engine |
| [`services/sbar_llm.py`](apps/o2_backend/services/sbar_llm.py) | OpenAI/Anthropic SBAR generation |

### IVR Backend (`ivr_backend/`)
| File | Purpose |
|------|---------|
| [`main.py`](ivr_backend/main.py) | Twilio webhook handlers |
| [`patient_lookup.py`](ivr_backend/patient_lookup.py) | CLI → patient → CHW WhatsApp mapping |
| [`whatsapp_sender.py`](ivr_backend/whatsapp_sender.py) | WhatsApp Business API voice forwarding |
| [`emergency_detector.py`](ivr_backend/emergency_detector.py) | Keyword detection for EN/KN/HI emergency words |

---

## What Would Be Different in Phase 2

1. **Real ABDM integration** — Replace mock with live NHA API calls for HPR verification and ABHA authentication
2. **ML-based risk scoring** — Train model on historical maternal health outcomes; use Phase 1 data as training signal
3. **Bhashini real integration** — Replace `sttLanguageCode`/`ttsLanguageCode` stubs in [`constants.dart`](apps/o2_app/lib/core/constants.dart) with live Bhashini API calls
4. **FHIR Server** — Point Flutter sync at a real FHIR R4 server instead of Supabase
5. **IVR transcription** — Use ElevenLabs or Bhashini STT to convert voice messages to searchable text
6. **Push notifications** — Twilio Notify or Firebase Cloud Messaging for CHW alerts

---

## Tags

`offline-first` `fhir-r4` `sqlcipher` `workmanager` `abdm` `abha` `ivr` `twilio` `whatsapp` `fastapi` `flutter` `brick-orm` `supabase` `rls` `traffic-light-triage` `sbar` `llm` `phc-hierarchy`