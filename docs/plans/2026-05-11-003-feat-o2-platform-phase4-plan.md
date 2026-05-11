# O2 Platform — Phase 4 Plan

> **Goal:** Make O2 Platform production-ready for pilot deployment  
> **Timeline:** 4–6 weeks post-hackathon  
> **Focus:** On-device ML + repository wiring + security hardening

---

## Phase 4 Objectives

### P0 — Must Have (MVP for Pilot)

| # | Item | Description |
|---|------|-------------|
| 4.1 | **On-device ML** | Quantized XGBoost model (.pkl) loaded at app startup — risk inference works with **zero internet** |
| 4.2 | **Flutter repository wiring** | `VitalsEntryScreen` → `VitalsRepository.save()`, `PatientDetailScreen` → `PatientRepository.load()`, `HomeScreen` stats from `PatientRepository` |
| 4.3 | **Security hardening** | Move Telegram bot token from `constants.dart` → `FlutterSecureStorage`, remove from git |

### P1 — Should Have (Pilot Quality)

| # | Item | Description |
|---|------|-------------|
| 4.4 | **AndroidManifest permissions** | Explicit `<uses-permission>` for `ACCESS_FINE_LOCATION`, `RECORD_AUDIO`, `INTERNET`, `ACCESS_NETWORK_STATE` |
| 4.5 | **Supabase deployment** | Deploy actual Supabase project with RLS policies, test auth flow |
| 4.6 | **Flutter error handling** | Add `ErrorScreen` wired to all `catch` blocks, show user-friendly messages |
| 4.7 | **Voice recording** | `record` package — actual voice recording in Flutter, not just forwarding |

### P2 — Nice to Have (Polish)

| # | Item | Description |
|---|------|-------------|
| 4.8 | **Real IndicTrans2** | Self-hosted `indictrans-server` Docker for actual Kannada/English STT |
| 4.9 | **CHW push notifications** | Telegram bot notifications for HIGH/EMERGENCY alerts to supervisor |
| 4.10 | **Real ABDM** | Live NHA API for ABHA validation |
| 4.11 | **Performance** | Lazy loading in `PatientListScreen`, vitals pagination |

---

## 4.1 — On-Device ML (Quantized XGBoost)

### Goal
Risk scoring inference runs entirely on the Flutter device — no backend call needed, no internet required.

### Approach
1. Train XGBoost model on synthetic historical data (or real NHM dataset if available)
2. Quantize to INT8 using `skl2onnx` + `onnxruntime`
3. Export as `.pkl` or `.json` model bundled in Flutter assets
4. Load model at app startup in `main.dart`
5. Call `riskModel.predict(vitals)` in `VitalsRepository.save()` — offline

### Files to create/modify
```
apps/o2_app/lib/ml/
  risk_model.dart         # XGBoost inference class (INT8 quantized)
  risk_model.json         # Model weights bundled in assets
  train_model.py          # Training script (runs on dev machine, not in app)
```

### Risk model format
```dart
class RiskInput {
  final int systolic;
  final int diastolic;
  final double hemoglobin;
  final int weeksPregnant;
  final double temperature;
  final int heartRate;
}

class RiskOutput {
  final String level; // LOW / MEDIUM / HIGH / EMERGENCY
  final int score;
  final List<String> flags;
  final String recommendation;
}
```

---

## 4.2 — Flutter Repository Wiring

### Current State
`VitalsEntryScreen`, `PatientDetailScreen`, `HomeScreen` are built but data is hardcoded or not persisted.

### Target State

```
VitalsEntryScreen
  → VitalsRepository.save(VitalsRecord)
    → Local SQLite (offline-first)
    → SyncService.enqueue(vitals_record) → Supabase when online

PatientDetailScreen
  → PatientRepository.getById(id) → Patient
  → VitalsRepository.getForPatient(patientId) → List<VitalsRecord>

HomeScreen
  → PatientRepository.countByRisk(riskLevel) → Map<String, int>
  → VitalsRepository.pendingFollowUps(days: 7) → List<VitalsRecord>
```

### Files to modify
- `apps/o2_app/lib/repositories/patient_repository.dart` — add actual SQLite + Supabase logic
- `apps/o2_app/lib/repositories/vitals_repository.dart` — add actual save/load
- `apps/o2_app/lib/services/sync_service.dart` — enqueue, flush, conflict resolution

---

## 4.3 — Security Hardening

### Move Telegram Token
```dart
// constants.dart — REMOVE the token
// BEFORE (dangerous):
static const String telegramBotToken = '8717671171:AAEmr...';

// AFTER:
// Token read from secure storage at runtime, never in source code
class TelegramService {
  Future<String> get token async {
    return await FlutterSecureStorage().read(key: 'telegram_bot_token');
  }
}
```

### Add `.env` / `.gitignore` entries
```
# .gitignore additions:
*.env
apps/o2_app/.env
```

---

## Phase 4 File Structure

```
apps/o2_app/
  lib/
    ml/
      risk_model.dart       # On-device XGBoost inference
      risk_model.json       # Bundled model weights
      train_model.py        # Training script (desktop only)
    repositories/
      patient_repository.dart  # Wired to SQLite + Supabase
      vitals_repository.dart  # Wired to SQLite + Supabase
    services/
      secure_storage_service.dart  # FlutterSecureStorage wrapper
```

---

## Verification

After Phase 4, the following must work **with airplane mode on**:

1. Register patient → saved locally
2. Record vitals → risk score calculated on-device
3. View patient list → loads from local DB
4. GPS coordinates captured → stored with vitals
5. App restart → all data persisted

---

## Out of Scope for Phase 4

- Real Bhashini API (Phase 5)
- FHIR server sync (Phase 5)
- iOS app (Phase 6)
- Multi-language support beyond Kannada/English (Phase 6)

---

> **Ready to start after:** Hackathon demo complete, Supabase deployed with test data