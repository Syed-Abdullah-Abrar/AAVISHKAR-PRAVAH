import 'dart:convert';
import 'package:fhir/r4.dart';
import '../models/patient.dart';
import '../models/vitals.dart';
import '../models/clinical_contact.dart';

/// FHIR Serializer Service — O2 Platform CHW App
/// 
/// Provides FHIR R4-compliant JSON serialization for all O2 entities.
/// 
/// Design Decision: FHIR R4 is the canonical format everywhere:
/// - Local storage: O2 models serialize to FHIR JSON before storage
/// - Sync wire format: FHIR Bundle for all Supabase sync operations
/// - External interoperability: FHIR JSON for ABDM/HMIS/NHM integration
/// 
/// Benefits:
/// 1. Single canonical model everywhere — no translation layers
/// 2. FHIR is the government-mandated standard for health data in India
/// 3. Brick sync adapter can directly serialize/deserialize FHIR
/// 4. Future ABDM integration is simplified
/// 
/// FHIR R4 Reference: https://hl7.org/fhir/R4/
/// 
/// Usage:
/// ```dart
/// final serializer = FhirSerializer();
/// 
/// // Serialize patient to FHIR JSON
/// final fhirJson = serializer.patientToFhirJson(patient);
/// 
/// // Deserialize patient from FHIR JSON
/// final patient = serializer.fhirJsonToPatient(fhirJson);
/// 
/// // Create FHIR Bundle for sync
/// final bundle = serializer.createSyncBundle(patients, vitals);
/// ```
class FhirSerializer {
  const FhirSerializer();

  // ─── Patient Serialization ─────────────────────────────────────────────────

  /// Serialize Patient to FHIR R4 JSON Map
  Map<String, dynamic> patientToFhirJson(Patient patient) {
    final fhirResource = patient.toFhir();
    return fhirResource.toJson();
  }

  /// Deserialize Patient from FHIR R4 JSON Map
  Patient fhirJsonToPatient(Map<String, dynamic> fhirJson) {
    final fhirJsonWrapper = FhirJson.fromJson(fhirJson);
    return Patient.fromFhir(fhirJsonWrapper);
  }

  /// Serialize list of Patients to FHIR JSON array
  List<Map<String, dynamic>> patientsToFhirJson(List<Patient> patients) {
    return patients.map((p) => patientToFhirJson(p)).toList();
  }

  // ─── Vitals Serialization ────────────────────────────────────────────────

  /// Serialize Vitals to FHIR R4 JSON Map
  Map<String, dynamic> vitalsToFhirJson(Vitals vitals) {
    final fhirResource = vitals.toFhir();
    return fhirResource.toJson();
  }

  /// Deserialize Vitals from FHIR R4 JSON Map
  Vitals fhirJsonToVitals(Map<String, dynamic> fhirJson) {
    // Extract from FHIR Observation
    final obs = R4.Observation.fromJson(fhirJson);
    return _observationToVitals(obs);
  }

  /// Serialize list of Vitals to FHIR JSON array
  List<Map<String, dynamic>> vitalsToFhirJsonList(List<Vitals> vitalsList) {
    return vitalsList.map((v) => vitalsToFhirJson(v)).toList();
  }

  // ─── Bundle Creation ──────────────────────────────────────────────────────

  /// Create FHIR Bundle for patient sync
  /// 
  /// Bundle type: transaction (POST to server)
  /// Contains: Patient resource + all related Observations
  R4.Bundle createPatientSyncBundle({
    required Patient patient,
    required List<Vitals> vitals,
    String? bundleId,
  }) {
    final entries = <R4.BundleEntry>[
      // Patient entry
      R4.BundleEntry(
        resource: patient.toFhir(),
        request: R4.BundleRequest(
          method: R4.HTTPMethod.put,
          url: 'Patient/${patient.fhirId}',
          ifNoneMatch: 'W/"1"', // Optimistic concurrency
        ),
      ),
    ];

    // Add all vitals as Observation entries
    for (final vital in vitals) {
      entries.add(
        R4.BundleEntry(
          resource: vital.toFhir(),
          request: R4.BundleRequest(
            method: R4.HTTPMethod.post,
            url: 'Observation',
          ),
        ),
      );
    }

    return R4.Bundle(
      id: bundleId,
      type: R4.BundleType.transaction,
      timestamp: DateTime.now(),
      entry: entries,
      meta: R4.Meta(
        lastUpdated: DateTime.now(),
      ),
    );
  }

  /// Create FHIR Bundle for full sync (all patients + all vitals)
  R4.Bundle createFullSyncBundle({
    required List<Patient> patients,
    required Map<String, List<Vitals>> patientVitals,
    String? bundleId,
  }) {
    final entries = <R4.BundleEntry>[];

    for (final patient in patients) {
      // Patient entry
      entries.add(
        R4.BundleEntry(
          resource: patient.toFhir(),
          request: R4.BundleRequest(
            method: R4.HTTPMethod.put,
            url: 'Patient/${patient.fhirId}',
          ),
        ),
      );

      // Vitals entries for this patient
      final vitals = patientVitals[patient.fhirId] ?? [];
      for (final vital in vitals) {
        entries.add(
          R4.BundleEntry(
            resource: vital.toFhir(),
            request: R4.BundleRequest(
              method: R4.HTTPMethod.post,
              url: 'Observation',
            ),
          ),
        );
      }
    }

    return R4.Bundle(
      id: bundleId,
      type: R4.BundleType.transaction,
      timestamp: DateTime.now(),
      entry: entries,
      total: entries.length,
      meta: R4.Meta(lastUpdated: DateTime.now()),
    );
  }

  // ─── FHIR JSON Utilities ──────────────────────────────────────────────────

  /// Validate FHIR JSON structure
  bool isValidFhirJson(Map<String, dynamic> json) {
    try {
      // Check for required FHIR resourceType
      if (!json.containsKey('resourceType')) return false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Pretty print FHIR JSON for debugging
  String prettyPrintFhirJson(Map<String, dynamic> fhirJson) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert(fhirJson);
  }

  /// Compress FHIR Bundle to JSON string for sync
  String bundleToJson(R4.Bundle bundle) {
    return jsonEncode(bundle.toJson());
  }

  /// Parse FHIR Bundle from JSON string
  R4.Bundle bundleFromJson(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return R4.Bundle.fromJson(json) as R4.Bundle;
  }

  // ─── Hospital Referral Export ─────────────────────────────────────────────

  /// Generate comprehensive FHIR Bundle for hospital referral.
  ///
  /// This is the "send to hospital" export — contains everything
  /// a receiving facility needs to immediately continue care:
  /// - Patient demographics + ABHA
  /// - Complete vitals history (all observations)
  /// - Risk assessment summary
  /// - SBAR handover document
  /// - Obstetric history (gravida, parity, LMP, complications)
  ///
  /// FHIR DocumentReference is the appropriate container for
  /// clinical handover in India ABDM ecosystem.
  R4.Bundle generateHospitalReferralBundle({
    required Patient patient,
    required List<Vitals> vitalsHistory,
    required String riskLevel,
    required int riskScore,
    required String sbarContent,
    required String referringChwId,
    String? referralReason,
  }) {
    final entries = <R4.BundleEntry>[];

    // 1. Patient resource
    entries.add(R4.BundleEntry(
      resource: patient.toFhir(),
      request: R4.BundleRequest(
        method: R4.HTTPMethod.put,
        url: 'Patient/${patient.fhirId}',
      ),
    ));

    // 2. All vital observations
    for (final vital in vitalsHistory) {
      entries.add(R4.BundleEntry(
        resource: vital.toFhir(),
        request: R4.BundleRequest(
          method: R4.HTTPMethod.post,
          url: 'Observation',
        ),
      ));
    }

    // 3. Risk Assessment as Observation
    final riskObservation = R4.Observation(
      id: 'risk-assessment-${patient.fhirId}',
      status: R4.ObservationStatus.final_,
      category: [
        R4.CodeableConcept(
          coding: [
            R4.Coding(
              system: 'http://terminology.hl7.org/CodeSystem/observation-category',
              code: 'risk',
              display: 'Risk Assessment',
            ),
          ],
        ),
      ],
      code: R4.CodeableConcept(
        coding: [
          R4.Coding(
            system: 'http://loinc.org',
            code: '9911001',
            display: 'Maternal risk assessment',
          ),
        ],
      ),
      subject: R4.Reference(reference: 'Patient/${patient.fhirId}'),
      effectiveDateTime: DateTime.now(),
      valueString: 'Risk Level: $riskLevel, Score: $riskScore',
      interpretation: [
        R4.CodeableConcept(
          coding: [
            R4.Coding(
              code: riskLevel == 'EMERGENCY' ? 'H' :
                   riskLevel == 'HIGH' ? 'H' :
                   riskLevel == 'MEDIUM' ? 'M' : 'N',
              display: riskLevel,
            ),
          ],
        ),
      ],
    );
    entries.add(R4.BundleEntry(
      resource: riskObservation,
      request: R4.BundleRequest(
        method: R4.HTTPMethod.post,
        url: 'Observation',
      ),
    ));

    // 4. SBAR DocumentReference
    final sbarJson = jsonEncode({
      'risk_level': riskLevel,
      'risk_score': riskScore,
      'content': sbarContent,
      'referral_reason': referralReason,
    });
    entries.add(R4.BundleEntry(
      resource: createSbarDocument(
        patientId: patient.fhirId,
        sbarContent: sbarContent,
        authorId: referringChwId,
        sbarJson: sbarJson,
      ),
      request: R4.BundleRequest(
        method: R4.HTTPMethod.post,
        url: 'DocumentReference',
      ),
    ));

    // 5. Referral Composition
    final composition = R4.Composition(
      id: 'referral-${patient.fhirId}-${DateTime.now().millisecondsSinceEpoch}',
      status: R4.CompositionStatus.final_,
      type: R4.CodeableConcept(
        coding: [
          R4.Coding(
            system: 'http://loinc.org',
            code: '60568-2',
            display: 'Referral note',
          ),
        ],
      ),
      subject: R4.Reference(reference: 'Patient/${patient.fhirId}'),
      date: DateTime.now(),
      author: [
        R4.Reference(reference: 'Practitioner/$referringChwId'),
      ],
      title: 'O2 Platform Maternal Health Referral',
      section: [
        R4.CompositionSection(
          title: 'Patient Demographics',
          code: R4.CodeableConcept(
            coding: [R4.Coding(code: 'DEM', display: 'Demographics')],
          ),
          text: R4.Narrative(
            div: '<div>Name: ${patient.name}<br/>ABHA: ${patient.abhaId}<br/>Age: ${patient.age}<br/>Phone: ${patient.phoneNumber}</div>',
          ),
        ),
        R4.CompositionSection(
          title: 'Risk Summary',
          code: R4.CodeableConcept(
            coding: [R4.Coding(code: 'RSK', display: 'Risk')],
          ),
          text: R4.Narrative(
            div: '<div>Risk Level: $riskLevel<br/>Score: $riskScore<br/>Recommendation: ${_riskRecommendation(riskLevel)}</div>',
          ),
        ),
        R4.CompositionSection(
          title: 'Vitals History',
          code: R4.CodeableConcept(
            coding: [R4.Coding(code: 'VIT', display: 'Vitals')],
          ),
          text: R4.Narrative(
            div: '<div>${vitalsHistory.length} records</div>',
          ),
        ),
      ],
    );
    entries.add(R4.BundleEntry(
      resource: composition,
      request: R4.BundleRequest(
        method: R4.HTTPMethod.post,
        url: 'Composition',
      ),
    ));

    return R4.Bundle(
      id: 'referral-bundle-${DateTime.now().millisecondsSinceEpoch}',
      type: R4.BundleType.document,
      timestamp: DateTime.now(),
      entry: entries,
      total: entries.length,
      meta: R4.Meta(lastUpdated: DateTime.now()),
    );
  }

  String _riskRecommendation(String level) {
    switch (level) {
      case 'EMERGENCY': return 'Call 108 / Immediate referral';
      case 'HIGH': return 'Urgent follow-up within 24h';
      case 'MEDIUM': return 'Schedule follow-up within 48h';
      default: return 'Routine care';
    }
  }

  // ─── SBAR Document ───────────────────────────────────────────────────────

  /// Create FHIR DocumentReference for SBAR handover document
  R4.DocumentReference createSbarDocument({
    required String patientId,
    required String sbarContent,
    required String authorId,
    required String sbarJson,
    String? docId,
  }) {
    return R4.DocumentReference(
      id: docId,
      status: R4.DocumentReferenceStatus.current,
      type: R4.CodeableConcept(
        coding: [
          R4.Coding(
            system: 'https://terminology.hl7.org/CodeSystem/doc-typecodes',
            code: 'SBAR',
            display: 'SBAR Clinical Handover',
          ),
        ],
      ),
      subject: R4.Reference(reference: 'Patient/$patientId'),
      date: DateTime.now(),
      author: [
        R4.Reference(reference: 'Practitioner/$authorId'),
      ],
      content: [
        R4.DocumentReferenceContent(
          attachment: R4.Attachment(
            contentType: 'application/json',
            data: sbarJson.codeUnits,
          ),
        ),
      ],
      context: R4.DocumentReferenceContext(
        practiceSetting: R4.CodeableConcept(
          coding: [
            R4.Coding(
              code: 'maternal-health',
              display: 'Maternal Health',
            ),
          ],
        ),
      ),
    );
  }

  // ─── Private Helpers ──────────────────────────────────────────────────────

  Vitals _observationToVitals(R4.Observation obs) {
    // Extract vital type from LOINC code
    final loincCode = obs.code?.coding?.firstOrNull?.code ?? '';
    final vitalType = _loincToVitalType(loincCode);

    // Extract value
    String value = '';
    String? unit;
    if (obs.value != null) {
      if (obs.value is R4.ObservationValueQuantity) {
        final q = obs.value as R4.ObservationValueQuantity;
        value = q.quantity?.value?.toString() ?? '';
        unit = q.quantity?.unit;
      } else if (obs.value is R4.ObservationValueString) {
        value = obs.value.toString();
      }
    }

    return Vitals(
      fhirId: obs.id ?? '',
      patientFhirId: obs.subject?.reference?.replaceFirst('Patient/', '') ?? '',
      vitalType: vitalType,
      value: value,
      unit: unit,
      recordedBy: obs.performer?.firstOrNull?.reference?.replaceFirst('Practitioner/', '') ?? '',
      recordedAt: obs.effectiveDateTime ?? DateTime.now(),
      source: 'sync',
    );
  }

  static String _loincToVitalType(String loincCode) {
    switch (loincCode) {
      case '85354-9':
        return 'blood_pressure';
      case '8867-4':
        return 'heart_rate';
      case '8310-5':
        return 'temperature';
      case '29463-7':
        return 'weight';
      case '8302-2':
        return 'height';
      case '718-7':
        return 'hemoglobin';
      case '2339-0':
        return 'blood_sugar';
      case '11612-4':
        return 'fetal_heart_rate';
      default:
        return 'unknown';
    }
  }
}

/// Singleton instance
const fhirSerializer = FhirSerializer();