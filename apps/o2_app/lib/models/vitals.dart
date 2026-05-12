/// Vitals Model — O2 Platform (Demo-ready, no FHIR dependency)
class Vitals {
  final String id;
  final String patientId;
  final double? systolicBp;
  final double? diastolicBp;
  final double? heartRate;
  final double? temperature;
  final double? spo2;
  final double? weight;
  final double? hemoglobin;
  final double? fetalHeartRate;
  final String? vitalType;
  final String? value;
  final String? unit;
  final String? notes;
  final String? recordedBy;
  final String? source;
  final String? clinicalFlag;
  final DateTime? recordedAt;
  final DateTime? createdAt;

  const Vitals({
    required this.id,
    required this.patientId,
    this.systolicBp,
    this.diastolicBp,
    this.heartRate,
    this.temperature,
    this.spo2,
    this.weight,
    this.hemoglobin,
    this.fetalHeartRate,
    this.vitalType,
    this.value,
    this.unit,
    this.notes,
    this.recordedBy,
    this.source,
    this.clinicalFlag,
    this.recordedAt,
    this.createdAt,
  });

  factory Vitals.fromJson(Map<String, dynamic> json) {
    return Vitals(
      id: json['id'] as String? ?? '',
      patientId: json['patient_id'] as String? ?? '',
      systolicBp: (json['systolic_bp'] as num?)?.toDouble(),
      diastolicBp: (json['diastolic_bp'] as num?)?.toDouble(),
      heartRate: (json['heart_rate'] as num?)?.toDouble(),
      temperature: (json['temperature'] as num?)?.toDouble(),
      spo2: (json['spo2'] as num?)?.toDouble(),
      weight: (json['weight'] as num?)?.toDouble(),
      hemoglobin: (json['hemoglobin'] as num?)?.toDouble(),
      fetalHeartRate: (json['fetal_heart_rate'] as num?)?.toDouble(),
      vitalType: json['vital_type'] as String?,
      value: json['value']?.toString(),
      unit: json['unit'] as String?,
      notes: json['notes'] as String?,
      recordedBy: json['recorded_by'] as String?,
      source: json['source'] as String?,
      clinicalFlag: json['clinical_flag'] as String?,
      recordedAt: json['recorded_at'] != null
          ? DateTime.tryParse(json['recorded_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'systolic_bp': systolicBp,
        'diastolic_bp': diastolicBp,
        'heart_rate': heartRate,
        'temperature': temperature,
        'spo2': spo2,
        'weight': weight,
        'hemoglobin': hemoglobin,
        'fetal_heart_rate': fetalHeartRate,
        'vital_type': vitalType,
        'value': value,
        'unit': unit,
        'notes': notes,
        'recorded_by': recordedBy,
        'source': source,
        'clinical_flag': clinicalFlag,
        'recorded_at': recordedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
      };

  /// BP display string
  String get bpDisplay {
    if (systolicBp != null && diastolicBp != null) {
      return '${systolicBp!.toInt()}/${diastolicBp!.toInt()} mmHg';
    }
    return 'N/A';
  }

  bool get isBpHigh =>
      (systolicBp ?? 0) > 140 || (diastolicBp ?? 0) > 90;

  bool get isHemoglobinLow => (hemoglobin ?? 99) < 10;

  @override
  String toString() => 'Vitals($id, patient: $patientId, bp: $bpDisplay)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Vitals && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
