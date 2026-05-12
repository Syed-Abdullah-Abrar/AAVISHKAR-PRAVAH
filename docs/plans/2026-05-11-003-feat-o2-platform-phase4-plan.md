# O2 Platform — Phase 4 Plan

> **Document status:** In progress — 2026-05-12  
> **Hackathon demo:** ~12 hours away  
> **Focus:** On-device ML + security + repository wiring

---

## Phase 4 Objectives

### ✅ DONE — Implemented This Session

| # | Item | File | Status |
|---|------|------|--------|
| 4.1a | **WHO Rule-Based Risk Scorer** | [`lib/ml/risk_scorer.dart`](apps/o2_app/lib/ml/risk_scorer.dart) | ✅ Complete |
| 4.1b | **XGBoost Inference Engine** | [`lib/ml/xgboost_inference.dart`](apps/o2_app/lib/ml/xgboost_inference.dart) | ✅ Complete |
| 4.2a | **SecureStorageService** | [`lib/services/secure_storage_service.dart`](apps/o2_app/lib/services/secure_storage_service.dart) | ✅ Complete |
| 4.3 | **TelegramService rewrite** — reads token from SecureStorage | [`lib/services/telegram_service.dart`](apps/o2_app/lib/services/telegram_service.dart) | ✅ Complete |
| 4.2b | **VitalsRepository.saveVitalsWithRisk()** | [`lib/repositories/vitals_repository.dart`](apps/o2_app/lib/repositories/vitals_repository.dart) | ✅ Complete |
| — | **ML module export** | [`lib/ml/ml.dart`](apps/o2_app/lib/ml/ml.dart) | ✅ Complete |
| — | **Token removed from source** | [`lib/core/constants.dart`](apps/o2_app/lib/core/constants.dart:36) | ✅ Complete |
| — | **Phase 4 ideation** | [`docs/ideation/O2-Platform-Phase4-ideation.md`](docs/ideation/O2-Platform-Phase4-ideation.md) | ✅ Complete |

### ⏳ DEFERRED — Post-Hackathon

| # | Item | Notes |
|---|------|-------|
| 4.4 | **AndroidManifest permissions** | No `android/` directory scaffolded — Flutter project needs `flutter create` |
| 4.5 | **Supabase deployment** | Requires actual Supabase project setup |
| 4.6 | **ErrorScreen wiring** | Wrap FutureBuilders with error boundaries |
| 4.7 | **Voice recording wired** | `record` package already in `pubspec.yaml` |
| 4.8 | **XGBoost model retraining** | NFHS dataset needed, 4-6 week effort |
| 4.9 | **Bhashini live API** | Credentials not available |

---

## 4.1a — WHO Rule-Based Risk Scorer

**File:** `apps/o2_app/lib/ml/risk_scorer.dart`

WHO-compliant risk assessment using established thresholds:

| Risk Factor | LOW | MEDIUM | HIGH | EMERGENCY |
|---|---|---|---|---|
| BP (mmHg) | <130/<80 | 130-139/80-89 | 140-159/90-109 | ≥160/≥110 |
| Hemoglobin (g/dL) | ≥11.0 | 10.0-10.9 | 7.0-9.9 | <7.0 |
| SpO2 (%) | ≥95 | — | 90-94 | <90 |
| Temperature (°C) | <37.5 | 37.5-38.0 | 38.1-39.0 | >39.0 |
| Maternal Age | 18-35 | 35-40 | <18 or ≥40 | — |

**WHO Danger Signs (always emergency):**
- Convulsion / seizure → +5 points
- Vaginal bleeding → +5 points
- Severe headache → +3 points
- Blurred vision → +3 points

**Output:** Risk level (LOW/MEDIUM/HIGH/EMERGENCY) + score + flag list + recommendation

---

## 4.1b — XGBoost Inference Engine

**File:** `apps/o2_app/lib/ml/xgboost_inference.dart`

Pure Dart XGBoost inference from bundled JSON model.

**Model:** `apps/o2_backend/models/risk_model.json` — 50 trees  
**Features (implicit):** [systolic_bp, diastolic_bp, hb, weeks_pregnant, temp, heart_rate, spo2, bmi, age, parity]

**Inference:** Traverses all 50 trees in Dart, sums leaf values, applies softmax  
**Fallback:** If model not bundled, falls back to WHO rules automatically

**Usage:**
```dart
final scorer = WHORiskScorer();
final result = scorer.assess(RiskInput(
  systolicBp: 150,
  diastolicBp: 95,
  hemoglobin: 8.5,
  weeksPregnant: 28,
  temperature: 99.5,
  heartRate: 88,
));
// result.level = 'HIGH'
// result.score = 7
// result.flags = ['SEVERE HYPERTENSION', 'MODERATE ANEMIA']
```

---

## 4.2 — Flutter Repository Wiring

**File:** `apps/o2_app/lib/repositories/vitals_repository.dart`

New method `saveVitalsWithRisk()`:
```dart
await vitalsRepo.saveVitalsWithRisk(
  patientFhirId: patient.fhirId,
  vitalType: 'blood_pressure',
  value: '150/95',
  unit: 'mmHg',
  recordedBy: 'chw-001',
  source: 'direct',
  locationLat: position.latitude,
  locationLng: position.longitude,
  riskLevel: 'HIGH',
  riskScore: 7,
);
```

---

## 4.3 — Security Hardening

**Files:**
- `apps/o2_app/lib/services/secure_storage_service.dart` — new
- `apps/o2_app/lib/services/telegram_service.dart` — rewritten
- `apps/o2_app/lib/core/constants.dart` — token removed

**Before (DANGER):**
```dart
static const String telegramBotToken = '8717671171:AAEmr0UNaBRuZv...'; // IN SOURCE!
```

**After (SAFE):**
```dart
// constants.dart — placeholder only
static const String telegramBotTokenPlaceholder = '<TELEGRAM_BOT_TOKEN>';

// telegram_service.dart — reads from secure storage
final token = await SecureStorageService().getTelegramToken();

// secure_storage_service.dart — Android Keystore backed
const storage = FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));
```

---

## Post-Hackathon: What's Next

After the hackathon demo, Phase 4 continues with:

1. **AndroidManifest** — `flutter create apps/o2_app` to scaffold Android project, add permissions
2. **ErrorScreen wiring** — wrap async builders with `AsyncErrorBoundary`
3. **Voice recording** — wire `record` package to `VoiceInputScreen`
4. **Model retraining** — obtain NFHS-5 individual woman dataset, retrain XGBoost with named features
5. **Supabase deployment** — create real Supabase project, deploy RLS policies

---

## Verification

After Phase 4 completion, the following must work **with airplane mode on**:

1. `WHORiskScorer().assess(input)` → returns correct risk level
2. `SecureStorageService().getTelegramToken()` → reads stored token
3. `TelegramService().sendMessage()` → uses secure storage token
4. `VitalsRepository.saveVitalsWithRisk()` → persists with risk level

---

> **Last updated:** 2026-05-12 — Phase 4 ML + security implementation in progress, hackathon demo imminent