---
title: "O2 Platform Phase 3 — Telegram Bot IVR, Full Flutter UI, GPS Auto-Tag"
date: 2026-05-11
category: architecture-patterns
module: o2-platform
tags: [flutter, fastapi, telegram, ivr, gps, android, indictrans]
problem_type: architecture-patterns
applies_when: "Implementing offline-first mobile healthcare with multi-channel IVR, GPS-tagged vitals, and AI decision support in low-resource rural India"
source_context: "Hackathon AAVISHKAR-PRAVAH — Phase 3 full implementation"
---

# O2 Platform Phase 3 — Telegram Bot IVR, Full Flutter UI, GPS Auto-Tag

## Context

Phase 1 MVP established the offline-first Flutter app with FastAPI AI backend and Twilio IVR. Phase 2 replaced inaccessible external APIs (NHA/Bhashini/Twilio) with local alternatives (Mod97 ABHA generator, IndicTrans2 Docker, Telegram Bot, SQLite, XGBoost shadow ML). Phase 3 completed the wiring: fully functional IVR pipeline, complete Flutter UI, GPS auto-tag on vitals, and MiniMax AI integration — leaving only on-device ML (quantized XGBoost) for Phase 4.

The core architectural challenge was maintaining offline-first principles while delivering real-time voice and AI features that require connectivity, without breaking the field-first design that keeps the app usable during poor connectivity.

## Guidance

### 1. Merging IVR Backend into FastAPI (Single-Process Deployment)

Phase 1 had `ivr_backend/` as a separate Python process with its own Twilio webhooks. Phase 3 merged it into the FastAPI app as `/ivr` router. This eliminated the cross-service coordination problem and simplified deployment:

```python
# apps/o2_backend/routers/ivr.py
router = APIRouter(prefix="/ivr", tags=["IVR"])

# apps/o2_backend/main.py
app.include_router(ivr.router, prefix="/ivr", tags=["IVR / Telegram"])
```

The adapter pattern ensures both paths work through the same interface:

```
Telegram voice → POST /ivr/voice-message → IndicTrans2 STT → emergency detection → Telegram alert
Twilio voice  → USE_TWILIO=true → same POST /ivr/voice-message → (no code change needed)
```

When real Twilio credentials arrive, set `USE_TWILIO=true` in `.env` — the IVR router routes to the appropriate channel at the Telegram Bot vs Twilio split point. No code rewrites.

### 2. Flutter Voice Pipeline (IndicTransService + TelegramService)

Flutter cannot directly call the Telegram Bot API from a mobile app (no Telegram Bot SDK for Flutter). Instead, Flutter records voice → calls FastAPI `/ivr/voice-message` → FastAPI downloads from Telegram → transcribes → returns transcript:

```dart
// apps/o2_app/lib/services/telegram_service.dart
class TelegramService {
  Future<Map<String, dynamic>> forwardVoiceMessage(
    String patientId,
    String fileId, {
    String language = 'kn',
  }) async {
    final uri = Uri.parse('$baseUrl/ivr/voice-message');
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'patient_id': patientId,
        'file_id': fileId,
        'language': language,
      }),
    );
    // FastAPI handles Telegram API calls server-side
  }
}
```

This keeps the Telegram bot token server-side only — critical for security.

### 3. GPS Auto-Tag (LocationService → VitalsRepository)

NHM compliance requires GPS coordinates on every vitals record. The `LocationService` uses `geolocator` with high accuracy:

```dart
// apps/o2_app/lib/services/location_service.dart
class LocationService {
  Future<Position> getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw LocationException('Location services disabled');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw LocationException('Location permission denied');
      }
    }
    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 10),
      ),
    );
  }
}
```

GPS is captured in `VitalsEntryScreen._captureLocation()` before the form is submitted, displayed in a location card for CHW confirmation, then stored on the `Vitals` record as `locationLat`/`locationLng`. This is a one-line addition to the vitals save flow — the `LocationException` is caught and displayed without blocking vitals entry.

### 4. Android Emulator Networking (10.0.2.2)

When testing Flutter on Android emulator, `localhost` refers to the emulator's own loopback, not the host machine. The standard alias `10.0.2.2` routes from the emulator to the host machine's localhost:

```dart
// apps/o2_app/lib/core/constants.dart
static const String aiServerUrl = 'http://10.0.2.2:8000'; // Android emulator
// For physical device or deployed: change to deployed host URL
```

CORS middleware in FastAPI must include this origin:

```python
# apps/o2_backend/main.py
allow_origins=[
    "http://localhost:3000",
    "http://localhost:8080",
    "http://10.0.2.2:3000",  # Android emulator
]
```

### 5. Full Flutter UI State Management Pattern

All placeholder `StatelessWidget` screens in `router.dart` were replaced with `StatefulWidget` implementations. Each screen follows the same pattern:

- `_isLoading` state for async operations
- `_loadData()` method called from `initState`
- `RefreshIndicator` wrapping `ListView` bodies
- Navigation via `context.push()` / `context.pop()` from GoRouter
- Service injection via constructors (already provided by `O2Router`)

TODO comments mark where Supabase credentials or native packages (dialer, share sheet) need to be wired — these are intentional gaps for Phase 4 when real backend credentials are available.

### 6. Phase 3 Files Reference

| File | Purpose |
|------|---------|
| `apps/o2_backend/routers/ivr.py` | Telegram voice → STT → alert router |
| `apps/o2_backend/.env.example` | All Phase 3 env vars (TELEGRAM_BOT_TOKEN, MINIMAX_API_KEY, etc.) |
| `apps/o2_app/lib/services/location_service.dart` | GPS with `LocationException` |
| `apps/o2_app/lib/services/indictrans_service.dart` | IndicTrans2 STT/TTS HTTP client |
| `apps/o2_app/lib/services/telegram_service.dart` | Flutter → IVR backend voice forwarding |
| `apps/o2_app/lib/core/router.dart` | Complete Flutter UI (10+ screens) |
| `apps/o2_app/pubspec.yaml` | Added `geolocator: ^13.0.2`, `permission_handler: ^11.3.1` |
| `apps/o2_app/lib/core/constants.dart` | Telegram token, API URLs, `10.0.2.2:8000` base |

## Why This Matters

The O2 Platform serves CHWs in low-resource rural settings where:
- Data plans are expensive and connectivity is unreliable
- Feature phones are common alongside smartphones
- GPS verification of visits is required for NHM compliance
- Real-time AI triage must work when connectivity drops after hours

By implementing the Telegram Bot IVR pipeline and IndicTrans2 Docker, we removed all external cloud dependencies for Phase 3 demo — the entire stack can run locally on a dev laptop connected via USB tethering. This directly addresses the hackathon's low-resource constraint.

The GPS auto-tag is not optional — it's an NHM compliance requirement. By integrating it into `VitalsEntryScreen` as a pre-save capture with visual confirmation card, we make GPS verification visible and actionable rather than a silent background process that fails silently.

## When to Apply

- Building a mobile healthcare app for community health workers in low-resource settings
- Needing multi-channel IVR (Telegram, WhatsApp, Twilio) with a unified backend router
- GPS auto-tag requirements for government health program compliance
- IndicTrans2 Docker for Indic language STT/TTS in India
- Flutter + FastAPI stack where the mobile app must work offline with selective cloud sync

## Examples

### Emergency Keyword Detection in IVR Router

```python
EMERGENCY_KEYWORDS = [
    'seizure', 'convulsion', 'bleeding', 'haemorrhage',
    'severe pain', 'cannot breathe', 'unconscious',
    # Kannada
    'ತೀವ್ರ ರಕ್ತಸ್ರಾವ', 'ಸೆಳೆವು',  # severe bleeding, seizure
]

async def _check_emergency_keywords(transcript: str) -> tuple[bool, str]:
    lower_transcript = transcript.lower()
    for keyword in EMERGENCY_KEYWORDS:
        if keyword in lower_transcript:
            return True, 'EMERGENCY'
    return False, 'MEDIUM'
```

### VitalsEntryScreen Location Capture

```dart
Future<void> _captureLocation() async {
  setState(() { _locationLoading = true; _locationError = null; });
  try {
    final locationService = LocationService();
    final position = await locationService.getCurrentPosition();
    setState(() {
      _lat = position.latitude;
      _lng = position.longitude;
      _locationLoading = false;
    });
  } on LocationException catch (e) {
    setState(() { _locationError = e.message; _locationLoading = false; });
  }
}
```

### Flutter Voice → Telegram Forwarding

```dart
Future<void> _sendViaTelegram() async {
  final telegramService = TelegramService();
  await telegramService.forwardVoiceMessage(
    widget.patientId,
    recordedFileId,
    language: _selectedLanguage,
  );
  // Telegram bot receives → /ivr/voice-message → IndicTrans2 → alert
}
```

## Prevention

- Always use `LocationException` with user-facing messages in Flutter GPS flows — raw platform exceptions are meaningless to CHWs in the field
- Keep API tokens server-side only — Flutter compiled binaries expose embedded strings; never embed Telegram bot tokens in Flutter code
- Use the `10.0.2.2` alias for Android emulator development; `localhost` fails silently because emulator loopback != host loopback
- Design IVR routers with the adapter pattern (`USE_TWILIO`, `USE_BHASHINI`) so channel changes don't require code rewrites — env var flips only
- CORS origins must include `http://10.0.2.2:3000` when developing for Android emulator — Chrome DevTools on desktop uses `localhost` but the emulator uses `10.0.2.2`

## Related Context

- Phase 2 local API alternatives: `docs/solutions/architecture-patterns/o2-platform-phase2-local-api-alternatives.md`
- Phase 3 plan: `docs/plans/2026-05-11-002-feat-o2-platform-phase3-plan.md`
- Phase 3 requirements: `docs/brainstorms/O2-Platform-Phase3-requirements.md`
