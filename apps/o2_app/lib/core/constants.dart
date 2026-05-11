/// O2 Platform — Application Constants
/// Version: 1.0.0
/// Environment: Production (India — Karnataka & Uttar Pradesh)

class O2Constants {
  O2Constants._();

  // ─── App Info ───────────────────────────────────────────────────────────────
  static const String appName = 'O2 Platform';
  static const String appVersion = '1.0.0';
  static const String appDescription =
      'Offline-first maternal healthcare monitoring for Community Health Workers';

  // ─── Supabase Configuration ──────────────────────────────────────────────────
  static const String supabaseUrl = 'https://<PROJECT_ID>.supabase.co';
  static const String supabaseAnonKey = '<ANON_KEY>';
  static const String supabaseServiceRoleKey = '<SERVICE_ROLE_KEY>';

  // ─── FastAPI Backend (AI Server) ────────────────────────────────────────────
  static const String aiServerUrl = 'http://<HOST>:8000';
  static const String riskEndpoint = '/risk';
  static const String sbarEndpoint = '/sbar';
  static const String healthEndpoint = '/health';
  static const Duration aiRequestTimeout = Duration(seconds: 30);

  // ─── IVR Backend (Twilio) ───────────────────────────────────────────────────
  static const String ivrBackendUrl = 'http://<HOST>:8001';
  static const String twilioWebhookMissedCall = '/twilio/missed-call';
  static const String twilioWebhookVoiceRecording = '/twilio/voice-recording';

  // ─── WorkManager Sync Configuration ─────────────────────────────────────────
  static const String syncWorkName = 'o2_background_sync';
  static const Duration syncIntervalMinutes = Duration(minutes: 15);
  static const int maxSyncRetries = 3;

  // ─── SQLCipher Encryption ───────────────────────────────────────────────────
  static const String keystoreName = 'O2KeyStore';
  static const String keystoreAlias = 'o2_sqlcipher_key';
  static const int sqlCipherKeySize = 256; // AES-256

  // ─── FHIR R4 ────────────────────────────────────────────────────────────────
  static const String fhirVersion = '4.0.1';
  static const String fhirBaseUrl = 'https://hl7.org/fhir/R4/';

  // ─── Bhashini Voice Config ───────────────────────────────────────────────────
  static const String bhashiniBaseUrl = 'https://api.bhashini.gov.in';
  static const String bhashiniSTTEndpoint = '/asr/v1';
  static const String bhashiniTTSEndpoint = '/tts/v1';

  // ─── Supported Languages ─────────────────────────────────────────────────────
  static const Map<String, String> supportedLanguages = {
    'kn': 'Kannada',
    'hi': 'Hindi',
  };
  static const String defaultLanguage = 'kn'; // Karnataka deployment
  static const String defaultRegion = 'karnataka'; // or 'uttar_pradesh'

  // ─── IVR Missed Call Config ───────────────────────────────────────────────────
  static const String tollFreeNumber = 'XXXXXXXXXX'; // TODO: Configure toll-free number
  static const Duration ivrCallbackTimeout = Duration(seconds: 30);
  static const int maxRecordingDurationSeconds = 60;

  // ─── Emergency Keywords (EN + KN + HI) ────────────────────────────────────────
  static const Map<String, List<String>> emergencyKeywords = {
    'en': ['blood', 'pain', 'unconscious', 'bleeding', 'seizure', 'fainted'],
    'kn': ['ರಕ್ತ', 'ನೋವು', 'ವಿಷಾಣ', 'ರಕ್ತಸ್ರಾವ', 'ಸೆಳೆವು'],
    'hi': ['खून', 'दर्द', 'बेहोश', 'खून आना', 'दौरा'],
  };

  // ─── Risk Thresholds (Traffic-Light Triage) ─────────────────────────────────
  static const int riskLowMax = 1;
  static const int riskMediumMax = 3;
  static const int riskHighMax = 5;
  // > riskHighMax → Emergency

  // ─── Clinical Contact Types ─────────────────────────────────────────────────
  static const List<String> contactTypes = [
    'home_visit',
    'phone_call',
    'whatsapp_voice',
    'ivr_call',
    'phc_visit',
  ];

  // ─── Vital Types ────────────────────────────────────────────────────────────
  static const List<String> vitalTypes = [
    'blood_pressure',
    'heart_rate',
    'temperature',
    'weight',
    'height',
    'hemoglobin',
    'blood_sugar',
    'fetal_heart_rate',
  ];

  // ─── API Headers ─────────────────────────────────────────────────────────────
  static const String apiKeyHeader = 'X-API-Key';
  static const String contentTypeJson = 'application/json';
  static const String authorizationHeader = 'Authorization';

  // ─── Local Storage Keys ─────────────────────────────────────────────────────
  static const String prefLanguage = 'o2_language';
  static const String prefRegion = 'o2_region';
  static const String prefLastSyncTime = 'o2_last_sync';
  static const String prefChwId = 'o2_chw_id';
  static const String prefPhcId = 'o2_phc_id';
  static const String prefSqlCipherDbName = 'o2_encrypted_db';
}

/// Risk Levels — Traffic-Light Triage
enum RiskLevel {
  low('Low', 'Green'),
  medium('Medium', 'Yellow'),
  high('High', 'Orange'),
  emergency('Emergency', 'Red');

  const RiskLevel(this.displayName, this.color);
  final String displayName;
  final String color;
}

/// Sync Status
enum SyncStatus {
  idle,
  syncing,
  success,
  failed,
  offline,
}