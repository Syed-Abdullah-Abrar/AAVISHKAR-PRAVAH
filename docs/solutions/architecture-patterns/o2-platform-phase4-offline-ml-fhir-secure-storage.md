---
title: "O2 Platform Phase 4 — Offline ML Risk Assessment & Secure Storage"
date: 2026-05-12
category: architecture-patterns
module: o2-platform
tags: [flutter, ml, offline-first, fhir, maternal-health, who-guidelines, xgboost]
problem_type: architecture-patterns
track: knowledge
summary: "Pure-Dart offline ML inference using WHO rule-based risk scorer + XGBoost model, FHIR-first design with hospital referral bundle export, and FlutterSecureStorage for secrets management"
applies_when: "Implementing offline ML inference, FHIR serialization for hospital referrals, or secrets management in Flutter mobile apps for maternal healthcare"
---

## Context

O2 Platform is an offline-first maternal healthcare monitoring app for Community Health Workers (CHWs) in Karnataka & Uttar Pradesh, India. Phase 4 added three capabilities needed for the hackathon demo:

1. **Offline ML Risk Assessment** — WHO rule-based scorer + XGBoost inference engine in pure Dart
2. **FHIR Hospital Referral Bundle** — Export complete patient records for hospital handoff
3. **Secure Secrets Management** — Telegram token moved from source code to FlutterSecureStorage

The app runs on low-resource Android phones with intermittent connectivity. All ML inference must work offline. FHIR R4 is the canonical format everywhere (local storage, sync wire format, external interoperability).

---

## Guidance

### 1. Pure-Dart Offline ML Inference

**Decision:** Implement ML inference entirely in Dart instead of platform channels or native libraries.

**Rationale:** No native library distribution complexity, no platform channel overhead, works offline by default, and the model (50-tree XGBoost, 10 features) is small enough to run in-process.

**Architecture:**

```
lib/ml/
├── ml.dart              # Barrel export
├── risk_scorer.dart     # WHO rule-based scorer (primary)
└── xgboost_inference.dart  # XGBoost JSON model runner (secondary)
```

**WHO Rule-Based Scorer** (`risk_scorer.dart`):
- Primary risk assessment engine
- 9 assessment axes: BP, Hemoglobin, Temperature, Heart Rate, SpO2, Danger Signs, Gestational Age, Previous Complications, Maternal Age
- Score capped at 10, mapped to 4 levels: LOW/MEDIUM/HIGH/EMERGENCY
- Danger signs (convulsion, vaginal bleeding) get +5 — immediate referral
- BP thresholds: ≥160/110 = +4, ≥140/90 = +3, ≥130/80 = +1
- Hb thresholds: <7.0 = +4, <10.0 = +2, <11.0 = +1
- Falls back to itself when XGBoost model unavailable

**XGBoost Inference Engine** (`xgboost_inference.dart`):
- Loads `risk_model.json` from Flutter assets (`assets/ml/risk_model.json`)
- 10 features in order: `[systolic_bp, diastolic_bp, hb, weeks_pregnant, temp, heart_rate, spo2, bmi, age, parity]`
- Traverses left_children/right_children/split_conditions/split_indices arrays per tree
- Softmax over 4-class margins to get probabilities
- Falls back to WHO rule-based `_fallbackPrediction()` when model not loaded

**Key pattern:**
```dart
XGBoostPrediction predict(XGBoostFeatures features) {
  if (!_loaded || _modelJson == null) {
    return _fallbackPrediction(features); // WHO rules
  }
  try {
    return _runInference(features);
  } catch (e) {
    return _fallbackPrediction(features); // graceful degradation
  }
}
```

**Asset bundling:** The model JSON must be placed at `assets/ml/risk_model.json` and registered in `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/ml/risk_model.json
```

### 2. FHIR-First Design

**Decision:** Use FHIR R4 as the single canonical format everywhere — no translation layers.

**Rationale:** Government-mandated standard for health data in India, Brick ORM sync adapter handles FHIR natively, future ABDM/HMIS/NHM integration simplified, single data model to maintain.

**All FHIR resources used:**
- `PatientResource` — Patient demographics + ABHA identifier
- `Observation` — Vitals (BP, Hb, temperature, etc.) with LOINC coding
- `DocumentReference` — SBAR handover documents
- `Composition` — Referral note with structured sections
- `Bundle` — Transaction bundle for sync, document bundle for referral

**FHIR Serializer (`fhir_serializer.dart`):**
- `createPatientSyncBundle()` — Transaction bundle for Supabase sync
- `createFullSyncBundle()` — Full patient + all vitals sync
- `generateHospitalReferralBundle()` — Document bundle for hospital handoff (lines 215-379)
- `createSbarDocument()` — SBAR DocumentReference creator

**Hospital Referral Bundle** contains:
1. Patient resource
2. All vital observations
3. Risk Assessment Observation (LOINC 9911001)
4. SBAR DocumentReference
5. Referral Composition (LOINC 60568-2)

**LOINC codes for vital types:**
- 85354-9: Blood pressure
- 8867-4: Heart rate
- 8310-5: Temperature
- 29463-7: Weight
- 8302-2: Height
- 718-7: Hemoglobin
- 2339-0: Blood sugar
- 11612-4: Fetal heart rate

### 3. Secure Secrets Management

**Decision:** Store all secrets in FlutterSecureStorage, never in source code.

**Rationale:** Android Keystore-backed AES-256 encryption, survives app updates, separate from source control, tokens not visible in APK decompilation.

**SecureStorageService (`secure_storage_service.dart`):**
```dart
static const String keyTelegramToken = 'telegram_bot_token';
static const String keySupabaseUrl = 'supabase_url';
static const String keySupabaseKey = 'supabase_anon_key';
static const String keyLastSync = 'last_sync_timestamp';
```

**Security rules:**
- Telegram token: stored once via `setTelegramToken()`, read via `getTelegramToken()`
- Falls back to placeholder `<TELEGRAM_BOT_TOKEN>` for demo
- Real token must be provisioned at first launch (not in source)

**Constants (`constants.dart`):**
```dart
// ⚠️ SECURITY: Token moved to FlutterSecureStorage in Phase 4
// Read via: await SecureStorageService().getTelegramToken()
// NEVER store real tokens in source code
static const String telegramBotTokenPlaceholder = '<TELEGRAM_BOT_TOKEN>';
```

### 4. Maternal History Fields

**Decision:** Add WHO-compliant obstetric history fields to Patient model for comprehensive records.

**Fields added (lines 83-160):**
- Obstetric: `lmpDate`, `edd`, `gravida`, `parity`, `liveBirths`, `stillbirths`, `abortions`, `previousComplications` (JSON), `lastDeliveryOutcome`, `lastDeliveryPlace`, `lastDeliveryType`, `breastfedPreviously`
- Gynecological: `menarcheAge`, `menstrualCycleRegular`, `contraceptionHistory` (JSON), `currentContraception`
- Medical: `knownAllergies` (JSON), `chronicConditions` (JSON), `surgicalHistory` (JSON), `bloodTransfusionHistory`, `bloodGroup`
- Family/Social: `familyHistory` (JSON), `familyPlanningInterest`, `unmetNeedContraception`

**Cross-reference:** Fields cross-referenced with WHO Maternal Health Guidelines document `9789240080591-eng.pdf` (second edition, 2025).

---

## Why This Matters

**Offline ML** enables CHWs to assess risk without connectivity. In Karnataka villages where 3G drops mid-session, this is the difference between a functional and broken demo.

**FHIR hospital referral** is the ABDM compliance path. When a patient needs referral, the receiving facility gets a complete, structured FHIR bundle — not a hand-written note that gets lost.

**Secure storage** prevents token leakage in open-source repos. The Telegram bot token was previously in `constants.dart` source — now it lives in Android Keystore, outside source control.

---

## When to Apply

- **Offline ML:** Use pure Dart when model is small (<1MB JSON), no training needed at runtime, and platform channel complexity isn't justified
- **FHIR-first:** Use when government-mandated standard applies (India: ABDM), Brick ORM is in use, or hospital referral interoperability is planned
- **Secure storage:** Always — never hardcode tokens, API keys, or user credentials in Flutter source

---

## Examples

### WHO Risk Assessment with Danger Sign
```dart
final input = RiskInput(
  systolicBp: 165,
  diastolicBp: 112,
  hemoglobin: 8.5,
  weeksPregnant: 34,
  temperature: 37.8,
  heartRate: 98,
  convulsion: true, // WHO danger sign → EMERGENCY
  vaginalBleeding: false,
);
final scorer = WHORiskScorer();
final output = scorer.assess(input);
// output.level = 'EMERGENCY', output.score = 10, flags contains danger signs
```

### Generate Hospital Referral Bundle
```dart
final bundle = fhirSerializer.generateHospitalReferralBundle(
  patient: patient,
  vitalsHistory: [bpVital, hbVital, tempVital],
  riskLevel: 'HIGH',
  riskScore: 5,
  sbarContent: 'Situation: High BP with mild anemia...',
  referringChwId: 'chw-001',
  referralReason: 'Hypertension requiring specialist care',
);
// Bundle type is 'document' (not 'transaction')
// Contains all 5 resource types for complete handover
```

### Telegram Token Setup (First Launch)
```dart
final secureStorage = SecureStorageService();
await secureStorage.setTelegramToken('1234567890:ABCdefGHIjklMNOpqrsTUVwxyz');
// Token now in Android Keystore, survives app updates
```

---

## Deferred Items

These were identified but not implemented in Phase 4 (hackathon timeline):

- **AndroidManifest.xml** — Needs `flutter create` scaffolding for proper Android permissions
- **ErrorScreen widget** — Global error boundary for production
- **Voice recording** — Recording patient voice messages for IVR
- **Supabase production config** — Demo uses SQLite-only, Supabase sync deferred post-hackathon

---

## Related Files

| File | Purpose |
|------|---------|
| `apps/o2_app/lib/ml/risk_scorer.dart` | WHO rule-based maternal risk scorer (425 lines) |
| `apps/o2_app/lib/ml/xgboost_inference.dart` | Pure Dart XGBoost JSON inference (335 lines) |
| `apps/o2_app/lib/ml/ml.dart` | Barrel export |
| `apps/o2_app/lib/services/fhir_serializer.dart` | FHIR R4 serialization + hospital referral bundle |
| `apps/o2_app/lib/services/secure_storage_service.dart` | FlutterSecureStorage wrapper |
| `apps/o2_app/lib/services/telegram_service.dart` | Telegram bot (token from secure storage) |
| `apps/o2_app/lib/models/patient.dart` | Patient model with maternal history fields |
| `apps/o2_app/lib/core/constants.dart` | App constants (token replaced with placeholder) |
| `apps/o2_backend/models/risk_model.json` | XGBoost 50-tree model (10 features, 4 classes) |
| `docs/ideation/O2-Platform-Phase4-ideation.md` | Phase 4 ideation — 7 ideas, direction chosen |
| `docs/plans/2026-05-11-003-feat-o2-platform-phase4-plan.md` | Phase 4 implementation plan |
| `docs/DEMO-TEST-GUIDE.md` | Demo walkthrough with all endpoint paths |
| `pitch.md` | Hackathon pitch with Phase 3/4 status |
