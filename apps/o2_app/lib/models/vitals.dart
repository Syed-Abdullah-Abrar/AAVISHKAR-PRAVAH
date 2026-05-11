import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:fhir/r4.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'vitals.g.dart';

/// Vitals Model — O2 Platform CHW App
/// 
/// Each vital sign (BP, weight, Hb, temperature) is stored as a separate
/// FHIR R4 Observation resource. Vitals are linked to a Patient via the patientFhirId field.
/// 
/// FHIR R4 Reference: https://hl7.org/fhir/R4/observation.html
/// 
/// Usage:
/// ```dart
/// final vitals = Vitals(
///   fhirId: 'obs-123',
///   patientFhirId: 'patient-123',
///   vitalType: 'blood_pressure',
///   value: '130/90',
///   unit: 'mmHg',
///   recordedBy: 'chw-456',
///   source: 'direct',
/// );
/// await vitalsRepository.upsert(vitals);
/// ```
@ConnectOfflineFirstWithSupabase(
  supabaseTableName: 'vitals_logs',
  localTableName: 'vitals_logs',
  schema: R'\$FUNDAMENTAL',
  repositoryName: 'VitalsRepository',
)
@JsonSerializable()
class Vitals extends SqliteModel
    with SupabaseModel
    implements FhirResource<Vitals> {
  @JsonKey(name: 'id')
  final String fhirId;

  @JsonKey(name: 'patient_fhir_id')
  final String patientFhirId;

  @JsonKey(name: 'vital_type')
  final String vitalType;

  @JsonKey(name: 'value')
  final String value;

  @JsonKey(name: 'unit')
  final String? unit;

  @JsonKey(name: 'recorded_by')
  final String recordedBy;

  @JsonKey(name: 'recorded_at')
  final DateTime recordedAt;

  @JsonKey(name: 'source')
  final String source;

  @JsonKey(name: 'notes')
  final String? notes;

  @JsonKey(name: 'location_lat')
  final double? locationLat;

  @JsonKey(name: 'location_lng')
  final double? locationLng;

  @JsonKey(name: 'device_id')
  final String? deviceId;

  @JsonKey(name: 'is_synced')
  @Default(false)
  final bool isSynced;

  @JsonKey(name: 'sync_attempts')
  @Default(0)
  final int syncAttempts;

  @JsonKey(name: 'last_sync_error')
  final String? lastSyncError;

  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  Vitals({
    required this.fhirId,
    required this.patientFhirId,
    required this.vitalType,
    required this.value,
    this.unit,
    required this.recordedBy,
    required this.recordedAt,
    required this.source,
    this.notes,
    this.locationLat,
    this.locationLng,
    this.deviceId,
    this.isSynced = false,
    this.syncAttempts = 0,
    this.lastSyncError,
    this.createdAt,
  });

  // ─── FHIR Conversion ─────────────────────────────────────────────────────────

  /// Convert to FHIR R4 Observation
  R4.Observation toFhir() {
    return R4.Observation(
      id: fhirId,
      status: R4.ObservationStatus.final_,
      category: [
        R4.CodeableConcept(
          coding: [
            R4.Coding(
              system: 'https://terminology.hl7.org/CodeSystem/observation-category',
              code: 'vital-signs',
              display: 'Vital Signs',
            ),
          ],
        ),
      ],
      code: R4.CodeableConcept(
        coding: [
          R4.Coding(
            system: 'https://loinc.org',
            code: _vitalTypeToLoinc(vitalType),
            display: _vitalTypeToDisplay(vitalType),
          ),
        ],
      ),
      subject: R4.Reference(reference: 'Patient/$patientFhirId'),
      effectiveDateTime: recordedAt,
      value: _buildValue(),
      performer: [
        R4.Reference(reference: 'Practitioner/$recordedBy'),
      ],
      note: notes != null ? [R4.Annotation(text: notes!)] : null,
      location: (locationLat != null && locationLng != null)
          ? R4.Reference(location: 'Location/$patientFhirId')
          : null,
    );
  }

  /// Serialize to FHIR JSON
  Map<String, dynamic> toFhirJson() => toFhir().toJson();

  /// Create FHIR Bundle with all vitals for a patient
  R4.Bundle toFhirBundle() {
    return R4.Bundle(
      type: R4.BundleType.transaction,
      entry: [
        R4.BundleEntry(
          resource: toFhir(),
          request: R4.BundleRequest(
            method: R4.HTTPMethod.post,
            url: 'Observation',
          ),
        ),
      ],
    );
  }

  // ─── Value Helpers ────────────────────────────────────────────────────────────

  /// Parse systolic BP value
  int? get systolicValue {
    if (vitalType != 'blood_pressure') return null;
    final parts = value.split('/');
    return parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  }

  /// Parse diastolic BP value
  int? get diastolicValue {
    if (vitalType != 'blood_pressure') return null;
    final parts = value.split('/');
    return parts.length > 1 ? int.tryParse(parts[1]) : null;
  }

  /// Parse numeric value (for comparison)
  double? get numericValue => double.tryParse(value);

  /// Check if value is within normal range
  bool get isNormalRange {
    switch (vitalType) {
      case 'blood_pressure':
        final sys = systolicValue;
        final dia = diastolicValue;
        if (sys == null || dia == null) return false;
        return sys < 120 && dia < 80;
      case 'heart_rate':
        final hr = numericValue;
        return hr != null && hr >= 60 && hr <= 100;
      case 'temperature':
        final temp = numericValue;
        return temp != null && temp >= 36.1 && temp <= 37.2;
      case 'hemoglobin':
        final hb = numericValue;
        return hb != null && hb >= 11.0;
      case 'blood_sugar':
        final bs = numericValue;
        return bs != null && bs < 140;
      case 'weight':
        final w = numericValue;
        return w != null && w > 0;
      default:
        return true;
    }
  }

  /// Get clinical flag based on vital type and value
  String? get clinicalFlag {
    switch (vitalType) {
      case 'blood_pressure':
        final sys = systolicValue;
        final dia = diastolicValue;
        if (sys != null && sys > 160) return 'HIGH';
        if (sys != null && sys < 90) return 'LOW';
        if (dia != null && dia > 100) return 'HIGH';
        if (dia != null && dia < 60) return 'LOW';
        return null;
      case 'heart_rate':
        final hr = numericValue;
        if (hr != null && hr > 100) return 'HIGH';
        if (hr != null && hr < 60) return 'LOW';
        return null;
      case 'temperature':
        final temp = numericValue;
        if (temp != null && temp > 38.0) return 'HIGH';
        if (temp != null && temp < 35.0) return 'LOW';
        return null;
      case 'hemoglobin':
        final hb = numericValue;
        if (hb != null && hb < 7.0) return 'CRITICAL';
        if (hb != null && hb < 11.0) return 'LOW';
        return null;
      default:
        return null;
    }
  }

  // ─── Private Helpers ──────────────────────────────────────────────────────────

  R4.ObservationValue _buildValue() {
    switch (vitalType) {
      case 'blood_pressure':
        // Blood pressure is a Component
        return R4.ObservationValue();
      case 'heart_rate':
      case 'temperature':
      case 'hemoglobin':
      case 'blood_sugar':
      case 'weight':
      case 'height':
        final quantity = R4.Quantity(
          value: numericValue ?? 0,
          unit: unit ?? '',
          system: 'http://unitsofmeasure.org',
          code: _unitToUCUM(unit ?? ''),
        );
        return R4.ObservationValue(quantity: quantity);
      default:
        return R4.ObservationValue(string: value);
    }
  }

  static String _vitalTypeToLoinc(String type) {
    switch (type) {
      case 'blood_pressure':
        return '85354-9';
      case 'heart_rate':
        return '8867-4';
      case 'temperature':
        return '8310-5';
      case 'weight':
        return '29463-7';
      case 'height':
        return '8302-2';
      case 'hemoglobin':
        return '718-7';
      case 'blood_sugar':
        return '2339-0';
      case 'fetal_heart_rate':
        return '11612-4';
      default:
        return 'unknown';
    }
  }

  static String _vitalTypeToDisplay(String type) {
    switch (type) {
      case 'blood_pressure':
        return 'Blood Pressure';
      case 'heart_rate':
        return 'Heart Rate';
      case 'temperature':
        return 'Body Temperature';
      case 'weight':
        return 'Body Weight';
      case 'height':
        return 'Body Height';
      case 'hemoglobin':
        return 'Hemoglobin';
      case 'blood_sugar':
        return 'Blood Glucose';
      case 'fetal_heart_rate':
        return 'Fetal Heart Rate';
      default:
        return type;
    }
  }

  static String _unitToUCUM(String unit) {
    switch (unit.toLowerCase()) {
      case 'mmhg':
        return 'mm[Hg]';
      case 'bpm':
        return '/min';
      case '°c':
      case 'c':
        return 'Cel';
      case 'kg':
        return 'kg';
      case 'cm':
        return 'cm';
      case 'g/dl':
        return 'g/dL';
      case 'mg/dl':
        return 'mg/dL';
      default:
        return unit;
    }
  }

  // ─── JSON Serialization ───────────────────────────────────────────────────────

  factory Vitals.fromJson(Map<String, dynamic> json) => _$VitalsFromJson(json);
  Map<String, dynamic> toJson() => _$VitalsToJson(this);

  factory Vitals.fromSqliteJson(Map<String, dynamic> json) =>
      _$VitalsFromSqliteJson(json);
  @override
  Map<String, dynamic> toSqliteJson() => _$VitalsToSqliteJson(this);

  @override
  String toString() =>
      'Vitals($vitalType: $value $unit for Patient $patientFhirId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vitals && runtimeType == other.runtimeType && fhirId == other.fhirId;

  @override
  int get hashCode => fhirId.hashCode;
}

/// Vital type constants
class VitalTypes {
  VitalTypes._();

  static const String bloodPressure = 'blood_pressure';
  static const String heartRate = 'heart_rate';
  static const String temperature = 'temperature';
  static const String weight = 'weight';
  static const String height = 'height';
  static const String hemoglobin = 'hemoglobin';
  static const String bloodSugar = 'blood_sugar';
  static const String fetalHeartRate = 'fetal_heart_rate';

  static const List<String> all = [
    bloodPressure,
    heartRate,
    temperature,
    weight,
    height,
    hemoglobin,
    bloodSugar,
    fetalHeartRate,
  ];

  static const Map<String, String> displayNames = {
    bloodPressure: 'Blood Pressure',
    heartRate: 'Heart Rate',
    temperature: 'Temperature',
    weight: 'Weight',
    height: 'Height',
    hemoglobin: 'Hemoglobin',
    bloodSugar: 'Blood Sugar',
    fetalHeartRate: 'Fetal Heart Rate',
  };

  static const Map<String, String> units = {
    bloodPressure: 'mmHg',
    heartRate: 'bpm',
    temperature: '°C',
    weight: 'kg',
    height: 'cm',
    hemoglobin: 'g/dL',
    bloodSugar: 'mg/dL',
    fetalHeartRate: 'bpm',
  };
}

/// Source of vital recording
class VitalSources {
  VitalSources._();

  static const String direct = 'direct';
  static const String phone = 'phone';
  static const String whatsapp = 'whatsapp';
  static const String ivr = 'ivr';
  static const String remote = 'remote';

  static const List<String> all = [direct, phone, whatsapp, ivr, remote];
}
