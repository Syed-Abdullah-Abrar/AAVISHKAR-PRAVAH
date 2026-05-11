import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'clinical_contact.g.dart';

/// Clinical Contact Model — O2 Platform CHW App
/// 
/// Tracks all clinical interactions between CHW and patient:
/// - Home visits
/// - Phone/WhatsApp calls
/// - IVR inbound calls from patients
/// - PHC visits
/// 
/// Usage:
/// ```dart
/// final contact = ClinicalContact(
///   fhirId: 'contact-123',
///   patientFhirId: 'patient-123',
///   contactType: 'home_visit',
///   chwId: 'chw-456',
///   summary: 'Routine checkup, vitals normal',
///   outcome: 'Patient stable',
/// );
/// ```
@ConnectOfflineFirstWithSupabase(
  supabaseTableName: 'clinical_contact_logs',
  localTableName: 'clinical_contact_logs',
  schema: R'\$FUNDAMENTAL',
  repositoryName: 'ClinicalContactRepository',
)
@JsonSerializable()
class ClinicalContact extends SqliteModel
    with SupabaseModel {
  @JsonKey(name: 'id')
  final String fhirId;

  @JsonKey(name: 'patient_fhir_id')
  final String patientFhirId;

  @JsonKey(name: 'contact_type')
  final String contactType;

  @JsonKey(name: 'chw_id')
  final String chwId;

  @JsonKey(name: 'contact_date')
  final DateTime contactDate;

  @JsonKey(name: 'summary')
  final String? summary;

  @JsonKey(name: 'outcome')
  final String? outcome;

  @JsonKey(name: 'patient_response')
  final String? patientResponse;

  @JsonKey(name: 'action_taken')
  final String? actionTaken;

  @JsonKey(name: 'next_steps')
  final String? nextSteps;

  @JsonKey(name: 'is_emergency')
  @Default(false)
  final bool isEmergency;

  @JsonKey(name: 'ivr_call_sid')
  final String? ivrCallSid;

  @JsonKey(name: 'whatsapp_message_id')
  final String? whatsappMessageId;

  @JsonKey(name: 'location_lat')
  final double? locationLat;

  @JsonKey(name: 'location_lng')
  final double? locationLng;

  @JsonKey(name: 'duration_minutes')
  final int? durationMinutes;

  @JsonKey(name: 'is_synced')
  @Default(false)
  final bool isSynced;

  @JsonKey(name: 'created_at')
  final DateTime? createdAt;

  ClinicalContact({
    required this.fhirId,
    required this.patientFhirId,
    required this.contactType,
    required this.chwId,
    required this.contactDate,
    this.summary,
    this.outcome,
    this.patientResponse,
    this.actionTaken,
    this.nextSteps,
    this.isEmergency = false,
    this.ivrCallSid,
    this.whatsappMessageId,
    this.locationLat,
    this.locationLng,
    this.durationMinutes,
    this.isSynced = false,
    this.createdAt,
  });

  factory ClinicalContact.fromJson(Map<String, dynamic> json) =>
      _$ClinicalContactFromJson(json);
  Map<String, dynamic> toJson() => _$ClinicalContactToJson(this);

  factory ClinicalContact.fromSqliteJson(Map<String, dynamic> json) =>
      _$ClinicalContactFromSqliteJson(json);
  @override
  Map<String, dynamic> toSqliteJson() => _$ClinicalContactToSqliteJson(this);

  @override
  String toString() =>
      'ClinicalContact($contactType on $contactDate for $patientFhirId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClinicalContact &&
          runtimeType == other.runtimeType &&
          fhirId == other.fhirId;

  @override
  int get hashCode => fhirId.hashCode;
}

/// Contact Type Constants
class ContactTypes {
  ContactTypes._();

  static const String homeVisit = 'home_visit';
  static const String phoneCall = 'phone_call';
  static const String whatsappVoice = 'whatsapp_voice';
  static const String ivrCall = 'ivr_call';
  static const String phcVisit = 'phc_visit';

  static const List<String> all = [
    homeVisit,
    phoneCall,
    whatsappVoice,
    ivrCall,
    phcVisit,
  ];

  static const Map<String, String> displayNames = {
    homeVisit: 'Home Visit',
    phoneCall: 'Phone Call',
    whatsappVoice: 'WhatsApp Voice',
    ivrCall: 'IVR Call',
    phcVisit: 'PHC Visit',
  };
}
