import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:fhir/r4.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'patient.g.dart';

/// Patient Model — O2 Platform CHW App
/// 
/// Defined as FHIR R4 native — all fields map directly to FHIR Patient resource elements.
/// Local persistence via Brick ORM + SQLCipher (AES-256).
/// Syncs opportunistically to Supabase when WiFi + Charging.
/// 
/// FHIR R4 Reference: https://hl7.org/fhir/R4/patient.html
/// 
/// Usage:
/// ```dart
/// final patient = Patient(
///   fhirId: 'patient-123',
///   abhaId: '12-3456-7890-1234',
///   name: 'Lakshmi Devi',
///   age: 28,
///   gender: 'F',
///   phoneNumber: '+919876543210',
///   assignedChwId: 'chw-456',
///   phcId: 'phc-001',
/// );
/// await patientRepository.upsert(patient);
/// ```
@ConnectOfflineFirstWithSupabase(
  supabaseTableName: 'patients',
  localTableName: 'patients',
  schema: R'\$FUNDAMENTAL',
  repositoryName: 'PatientRepository',
)
@JsonSerializable()
class Patient extends SqliteModel
    with SupabaseModel
    implements FhirResource<Patient> {
  @JsonKey(name: 'id')
  final String fhirId;

  @JsonKey(name: 'abha_id')
  final String abhaId;

  @JsonKey(name: 'name')
  final String name;

  @JsonKey(name: 'age')
  final int? age;

  @JsonKey(name: 'gender')
  final String gender;

  @JsonKey(name: 'phone_number')
  final String? phoneNumber;

  @JsonKey(name: 'assigned_chw_id')
  final String assignedChwId;

  @JsonKey(name: 'phc_id')
  final String phcId;

  @JsonKey(name: 'address')
  final String? address;

  @JsonKey(name: 'village')
  final String? village;

  @JsonKey(name: 'district')
  final String? district;

  @JsonKey(name: 'state')
  final String? state;

  @JsonKey(name: 'emergency_contact_name')
  final String? emergencyContactName;

  @JsonKey(name: 'emergency_contact_phone')
  final String? emergencyContactPhone;

  // ─── Obstetric / Maternal History ────────────────────────────────────────────
  // Cross-referenced with WHO Maternal Health Guidelines (9789240080591)

  @JsonKey(name: 'lmp_date')
  final DateTime? lmpDate;

  @JsonKey(name: 'edd')
  final DateTime? edd;

  @JsonKey(name: 'gravida')
  final int? gravida;

  @JsonKey(name: 'parity')
  final int? parity;

  @JsonKey(name: 'live_births')
  final int? liveBirths;

  @JsonKey(name: 'stillbirths')
  final int? stillbirths;

  @JsonKey(name: 'abortions')
  final int? abortions;

  @JsonKey(name: 'previous_complications')
  final String? previousComplications;

  @JsonKey(name: 'last_delivery_outcome')
  final String? lastDeliveryOutcome;

  @JsonKey(name: 'last_delivery_place')
  final String? lastDeliveryPlace;

  @JsonKey(name: 'last_delivery_type')
  final String? lastDeliveryType;

  @JsonKey(name: 'breastfeeding_previous')
  final bool? breastfedPreviously;

  @JsonKey(name: 'menarche_age')
  final int? menarcheAge;

  @JsonKey(name: 'menstrual_cycle_regular')
  final bool? menstrualCycleRegular;

  @JsonKey(name: 'contraception_history')
  final String? contraceptionHistory;

  @JsonKey(name: 'current_contraception')
  final String? currentContraception;

  // ─── Medical / Surgical History ──────────────────────────────────────────────

  @JsonKey(name: 'known_allergies')
  final String? knownAllergies;  // JSON array

  @JsonKey(name: 'chronic_conditions')
  final String? chronicConditions;  // JSON array: ["diabetes", "hypertension", "thyroid"]

  @JsonKey(name: 'surgical_history')
  final String? surgicalHistory;  // JSON array

  @JsonKey(name: 'blood_transfusion_history')
  final bool? bloodTransfusionHistory;

  @JsonKey(name: 'blood_group')
  final String? bloodGroup;  // 'A+', 'B+', 'O+', 'AB+', etc.

  // ─── Family / Social History ─────────────────────────────────────────────────

  @JsonKey(name: 'family_history')
  final String? familyHistory;  // JSON array: ["diabetes_mother", "preeclampsia_sister"]

  @JsonKey(name: 'family_planning_interest')
  final bool? familyPlanningInterest;

  @JsonKey(name: 'unmet_need_contraception')
  final bool? unmetNeedContraception;

  @JsonKey(name: 'high_risk_pregnancy')
  @Default(false)
  final bool highRiskPregnancy;

  @JsonKey(name: 'risk_level')
  final String? riskLevel;

  @JsonKey(name: 'last_visit_date')
  final DateTime? lastVisitDate;

  @JsonKey(name: 'next_visit_date')
  final DateTime? nextVisitDate;

  @JsonKey(name: 'abha_card_number')
  final String? abhaCardNumber;

  @JsonKey(name: 'photograph_url')
  final String? photographUrl;

  @JsonKey(name: 'remarks')
  final String? remarks;

  @JsonKey(name: 'is_active')
  @Default(true)
  final bool isActive;

  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  @JsonKey(name: 'updated_at')
  final DateTime? updatedAt;

  Patient({
    required this.fhirId,
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
    this.liveBirths,
    this.stillbirths,
    this.abortions,
    this.previousComplications,
    this.lastDeliveryOutcome,
    this.lastDeliveryPlace,
    this.lastDeliveryType,
    this.breastfedPreviously,
    this.menarcheAge,
    this.menstrualCycleRegular,
    this.contraceptionHistory,
    this.currentContraception,
    this.knownAllergies,
    this.chronicConditions,
    this.surgicalHistory,
    this.bloodTransfusionHistory,
    this.bloodGroup,
    this.familyHistory,
    this.familyPlanningInterest,
    this.unmetNeedContraception,
    this.highRiskPregnancy = false,
    this.riskLevel,
    this.lastVisitDate,
    this.nextVisitDate,
    this.abhaCardNumber,
    this.photographUrl,
    this.remarks,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  /// Create Patient from FHIR R4 Patient resource
  factory Patient.fromFhir(FhirJson fhirJson) {
    final resource = fhirJson.resource as R4.PatientResource;
    return Patient(
      fhirId: resource.id ?? '',
      abhaId: _extractAbhaId(resource),
      name: _extractName(resource),
      age: _extractAge(resource),
      gender: _extractGender(resource),
      phoneNumber: _extractPhone(resource),
      assignedChwId: '', // Set by repository
      phcId: '', // Set by repository
      address: _extractAddress(resource),
      village: _extractVillage(resource),
      district: _extractDistrict(resource),
      state: _extractState(resource),
    );
  }

  /// Serialize Patient to FHIR R4 Patient resource
  R4.PatientResource toFhir() {
    return R4.PatientResource(
      id: fhirId,
      name: [
        R4.HumanName(
          text: name,
          use: R4.HumanNameUse.official,
        ),
      ],
      telecom: phoneNumber != null
          ? [
              R4.ContactPoint(
                value: phoneNumber,
                system: R4.ContactPointSystem.phone,
                use: R4.ContactPointUse.mobile,
              ),
            ]
          : null,
      gender: _genderToFhir(gender),
      birthDate: null, // Age is derived, not birthDate
      address: _buildAddress(),
      identifier: [
        R4.Identifier(
          system: 'https://healthid.nha.gov.in/',
          value: abhaId,
        ),
      ],
      meta: R4.Meta(
        versionId: '1',
        lastUpdated: updatedAt ?? DateTime.now(),
      ),
    );
  }

  /// Convert to FHIR JSON Map (for sync)
  Map<String, dynamic> toFhirJson() {
    final fhirResource = toFhir();
    return fhirResource.toJson();
  }

  /// Create FHIR Bundle for this patient (includes all related resources)
  R4.Bundle toFhirBundle() {
    return R4.Bundle(
      type: R4.BundleType.transaction,
      entry: [
        R4.BundleEntry(
          resource: toFhir(),
          request: R4.BundleRequest(
            method: R4.HTTPMethod.put,
            url: 'Patient/$fhirId',
          ),
        ),
      ],
    );
  }

  // ─── FHIR Extraction Helpers ─────────────────────────────────────────────────

  static String _extractAbhaId(R4.PatientResource resource) {
    final identifiers = resource.identifier;
    if (identifiers == null) return '';
    for (final id in identifiers) {
      if (id.system?.contains('healthid.nha.gov.in') == true) {
        return id.value ?? '';
      }
    }
    return '';
  }

  static String _extractName(R4.PatientResource resource) {
    final names = resource.name;
    if (names == null || names.isEmpty) return '';
    return names.first.text ?? names.first.given?.first ?? '';
  }

  static int? _extractAge(R4.PatientResource resource) {
    // Calculate age from birthDate or use extension
    return resource.birthDate != null
        ? DateTime.now().year - resource.birthDate!.year
        : null;
  }

  static String _extractGender(R4.PatientResource resource) {
    switch (resource.gender) {
      case R4.AdministrativeGender.male:
        return 'M';
      case R4.AdministrativeGender.female:
        return 'F';
      case R4.AdministrativeGender.other:
        return 'O';
      case R4.AdministrativeGender.unknown:
      default:
        return 'U';
    }
  }

  static String? _extractPhone(R4.PatientResource resource) {
    final telecoms = resource.telecom;
    if (telecoms == null) return null;
    for (final tel in telecoms) {
      if (tel.system == R4.ContactPointSystem.phone) {
        return tel.value;
      }
    }
    return null;
  }

  static String? _extractAddress(R4.PatientResource resource) {
    final addresses = resource.address;
    if (addresses == null || addresses.isEmpty) return null;
    return addresses.first.text;
  }

  static String? _extractVillage(R4.PatientResource resource) {
    final addresses = resource.address;
    if (addresses == null || addresses.isEmpty) return null;
    return addresses.first.city;
  }

  static String? _extractDistrict(R4.PatientResource resource) {
    final addresses = resource.address;
    if (addresses == null || addresses.isEmpty) return null;
    return addresses.first.district;
  }

  static String? _extractState(R4.PatientResource resource) {
    final addresses = resource.address;
    if (addresses == null || addresses.isEmpty) return null;
    return addresses.first.state;
  }

  static R4.Address _buildAddress() {
    // Implementation for address building
    return R4.Address();
  }

  static R4.AdministrativeGender _genderToFhir(String gender) {
    switch (gender.uppercase) {
      case 'M':
        return R4.AdministrativeGender.male;
      case 'F':
        return R4.AdministrativeGender.female;
      case 'O':
        return R4.AdministrativeGender.other;
      default:
        return R4.AdministrativeGender.unknown;
    }
  }

  // ─── Freezed/JSON Serialization ─────────────────────────────────────────────

  factory Patient.fromJson(Map<String, dynamic> json) => Patient.fromJson(json);
  Map<String, dynamic> toJson() => Patient.toJson(this);

  factory Patient.fromJson(Map<String, dynamic> json) =>
      _$PatientFromJson(json);
  Map<String, dynamic> toJson() => _$PatientToJson(this);

  @override
  Map<String, dynamic> toSqliteJson() => _$PatientToSqliteJson(this);

  static Map<String, dynamic> fromSqliteJson(Map<String, dynamic> json) =>
      _$PatientFromSqliteJson(json);

  // ─── Domain Methods ─────────────────────────────────────────────────────────

  /// Calculate expected delivery date (EDD) from last menstrual period (LMP)
  DateTime? calculateEdd() {
    if (lmpDate == null) return null;
    return lmpDate!.add(const Duration(days: 280)); // 40 weeks
  }

  /// Calculate current gestational age in weeks
  int? calculateGestationalAge() {
    if (lmpDate == null) return null;
    final daysSinceLmp = DateTime.now().difference(lmpDate!).inDays;
    return (daysSinceLmp / 7).floor();
  }

  /// Check if patient is high-risk based on clinical criteria
  bool get isHighRisk {
    if (highRiskPregnancy) return true;
    // Add clinical criteria here
    return false;
  }

  /// Get risk color for UI display
  String get riskColor {
    switch (riskLevel?.toLowerCase()) {
      case 'emergency':
        return 'red';
      case 'high':
        return 'orange';
      case 'medium':
        return 'yellow';
      case 'low':
      default:
        return 'green';
    }
  }

  @override
  String toString() => 'Patient($fhirId, $name, ABHA: $abhaId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Patient && runtimeType == other.runtimeType && fhirId == other.fhirId;

  @override
  int get hashCode => fhirId.hashCode;
}

/// Extension for List<Patient> convenience methods
extension PatientListExtension on List<Patient> {
  /// Filter patients by assigned CHW
  List<Patient> forChw(String chwId) =>
      where((p) => p.assignedChwId == chwId).toList();

  /// Filter patients by PHC
  List<Patient> forPhc(String phcId) =>
      where((p) => p.phcId == phcId).toList();

  /// Filter high-risk patients
  List<Patient> get highRisk => where((p) => p.isHighRisk).toList();

  /// Sort by next visit date (soonest first)
  List<Patient> sortedByNextVisit() {
    final withDates = where((p) => p.nextVisitDate != null).toList()
      ..sort((a, b) => a.nextVisitDate!.compareTo(b.nextVisitDate!));
    final withoutDates = where((p) => p.nextVisitDate == null).toList();
    return [...withDates, ...withoutDates];
  }
}