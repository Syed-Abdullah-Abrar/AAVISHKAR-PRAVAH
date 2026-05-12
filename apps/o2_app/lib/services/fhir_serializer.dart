/// FHIR Serializer — Stubbed for Demo Build
/// 
/// Full FHIR R4 serialization requires the fhir package.
/// This stub maintains the API surface so the app compiles.
/// Production: restore fhir dependency and implementation.

import '../models/patient.dart';
import '../models/vitals.dart';

class FhirSerializer {
  /// Convert patient to FHIR-compatible JSON map
  Map<String, dynamic> patientToFhirJson(Patient patient) {
    return {
      'resourceType': 'Patient',
      'id': patient.id,
      'identifier': [
        {
          'system': 'https://healthid.nha.gov.in/',
          'value': patient.abhaId,
        }
      ],
      'name': [
        {'text': patient.name, 'use': 'official'}
      ],
      'gender': patient.gender.toLowerCase() == 'f' ? 'female' : 'male',
      'telecom': patient.phoneNumber != null
          ? [
              {
                'system': 'phone',
                'value': patient.phoneNumber,
                'use': 'mobile'
              }
            ]
          : [],
      'address': patient.village != null
          ? [
              {
                'city': patient.village,
                'district': patient.district,
                'state': patient.state,
                'country': 'IN'
              }
            ]
          : [],
    };
  }

  /// Convert vitals to FHIR Observation JSON
  Map<String, dynamic> vitalsToFhirJson(Vitals vitals) {
    return {
      'resourceType': 'Observation',
      'id': vitals.id,
      'status': 'final',
      'subject': {'reference': 'Patient/${vitals.patientId}'},
      'effectiveDateTime': vitals.recordedAt?.toIso8601String(),
      'component': [
        if (vitals.systolicBp != null)
          {
            'code': {
              'coding': [
                {'system': 'http://loinc.org', 'code': '8480-6', 'display': 'Systolic BP'}
              ]
            },
            'valueQuantity': {'value': vitals.systolicBp, 'unit': 'mmHg'}
          },
        if (vitals.diastolicBp != null)
          {
            'code': {
              'coding': [
                {'system': 'http://loinc.org', 'code': '8462-4', 'display': 'Diastolic BP'}
              ]
            },
            'valueQuantity': {'value': vitals.diastolicBp, 'unit': 'mmHg'}
          },
      ],
    };
  }

  /// Create a FHIR Bundle JSON string from patient + vitals
  String createSyncBundleJson(Patient patient, List<Vitals> vitalsList) {
    final entries = [
      {
        'resource': patientToFhirJson(patient),
        'request': {'method': 'PUT', 'url': 'Patient/${patient.id}'}
      },
      for (final v in vitalsList)
        {
          'resource': vitalsToFhirJson(v),
          'request': {'method': 'POST', 'url': 'Observation'}
        }
    ];
    return {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': entries,
    }.toString();
  }
}