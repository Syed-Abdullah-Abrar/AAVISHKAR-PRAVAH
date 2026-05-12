/// Patient Model — O2 Platform (Demo-ready, no FHIR dependency)
class Patient {
  final String id;
  final String abhaId;
  final String name;
  final int? age;
  final String gender;
  final String? phoneNumber;
  final String assignedChwId;
  final String phcId;
  final String? address;
  final String? village;
  final String? district;
  final String? state;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final DateTime? lmpDate;
  final DateTime? edd;
  final int? gravida;
  final int? parity;
  final String? chronicConditions;
  final String? knownAllergies;
  final String? bloodGroup;
  final bool highRiskPregnancy;
  final String? riskLevel;
  final DateTime? lastVisitDate;
  final DateTime? nextVisitDate;
  final String? remarks;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Patient({
    required this.id,
    required this.abhaId,
    required this.name,
    this.age,
    required this.gender,
    this.phoneNumber,
    required this.assignedChwId,
    required this.phcId,
    this.address,
    this.village,
    this.district,
    this.state,
    this.emergencyContactName,
    this.emergencyContactPhone,
    this.lmpDate,
    this.edd,
    this.gravida,
    this.parity,
    this.chronicConditions,
    this.knownAllergies,
    this.bloodGroup,
    this.highRiskPregnancy = false,
    this.riskLevel,
    this.lastVisitDate,
    this.nextVisitDate,
    this.remarks,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      id: json['id'] as String? ?? '',
      abhaId: json['abha_number'] as String? ?? '',
      name: json['name'] as String? ?? '',
      age: json['age'] as int?,
      gender: json['gender'] as String? ?? 'F',
      phoneNumber: json['phone'] as String?,
      assignedChwId: json['assigned_chw_id'] as String? ?? '',
      phcId: json['phc_id'] as String? ?? '',
      address: json['address'] as String?,
      village: json['village'] as String?,
      district: json['district'] as String?,
      state: json['state'] as String?,
      emergencyContactName: json['emergency_contact'] as String?,
      emergencyContactPhone: json['emergency_phone'] as String?,
      chronicConditions: json['medical_history'] as String?,
      knownAllergies: json['allergies'] as String?,
      bloodGroup: json['blood_group'] as String?,
      highRiskPregnancy: json['high_risk_pregnancy'] as bool? ?? false,
      riskLevel: json['risk_level'] as String?,
      lastVisitDate: json['last_visit'] != null
          ? DateTime.tryParse(json['last_visit'] as String)
          : null,
      nextVisitDate: json['next_visit'] != null
          ? DateTime.tryParse(json['next_visit'] as String)
          : null,
      remarks: json['notes'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.tryParse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'abha_number': abhaId,
        'name': name,
        'age': age,
        'gender': gender,
        'phone': phoneNumber,
        'assigned_chw_id': assignedChwId,
        'phc_id': phcId,
        'address': address,
        'village': village,
        'risk_level': riskLevel,
        'last_visit': lastVisitDate?.toIso8601String(),
        'next_visit': nextVisitDate?.toIso8601String(),
        'is_active': isActive,
      };

  /// Calculate current gestational age in weeks
  int? get gestationalAgeWeeks {
    if (lmpDate == null) return null;
    return (DateTime.now().difference(lmpDate!).inDays / 7).floor();
  }

  /// Check if patient is high-risk
  bool get isHighRisk =>
      highRiskPregnancy ||
      riskLevel?.toUpperCase() == 'HIGH' ||
      riskLevel?.toUpperCase() == 'EMERGENCY';

  /// Risk level display color name
  String get riskColor {
    switch (riskLevel?.toUpperCase()) {
      case 'EMERGENCY':
        return 'red';
      case 'HIGH':
        return 'orange';
      case 'MEDIUM':
        return 'yellow';
      default:
        return 'green';
    }
  }

  @override
  String toString() => 'Patient($id, $name, risk: $riskLevel)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Patient && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

extension PatientListExtension on List<Patient> {
  List<Patient> forChw(String chwId) =>
      where((p) => p.assignedChwId == chwId).toList();

  List<Patient> forPhc(String phcId) =>
      where((p) => p.phcId == phcId).toList();

  List<Patient> get highRisk => where((p) => p.isHighRisk).toList();

  List<Patient> sortedByNextVisit() {
    final withDates = where((p) => p.nextVisitDate != null).toList()
      ..sort((a, b) => a.nextVisitDate!.compareTo(b.nextVisitDate!));
    final withoutDates = where((p) => p.nextVisitDate == null).toList();
    return [...withDates, ...withoutDates];
  }
}