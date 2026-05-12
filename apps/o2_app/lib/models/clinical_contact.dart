/// ClinicalContact Model — O2 Platform (Demo-ready)
class ClinicalContact {
  final String id;
  final String patientId;
  final String contactType;
  final String? notes;
  final String? conductedBy;
  final DateTime? contactDate;
  final DateTime? createdAt;

  const ClinicalContact({
    required this.id,
    required this.patientId,
    required this.contactType,
    this.notes,
    this.conductedBy,
    this.contactDate,
    this.createdAt,
  });

  factory ClinicalContact.fromJson(Map<String, dynamic> json) {
    return ClinicalContact(
      id: json['id'] as String? ?? '',
      patientId: json['patient_id'] as String? ?? '',
      contactType: json['contact_type'] as String? ?? 'visit',
      notes: json['notes'] as String?,
      conductedBy: json['conducted_by'] as String?,
      contactDate: json['contact_date'] != null
          ? DateTime.tryParse(json['contact_date'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'patient_id': patientId,
        'contact_type': contactType,
        'notes': notes,
        'conducted_by': conductedBy,
        'contact_date': contactDate?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
      };

  @override
  String toString() => 'ClinicalContact($id, $contactType)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClinicalContact && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
