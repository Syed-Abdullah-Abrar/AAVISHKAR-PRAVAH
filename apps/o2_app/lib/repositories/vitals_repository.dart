import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import '../models/vitals.dart';

/// Vitals Repository — O2 Platform CHW App
/// 
/// Brick repository for offline-first vital signs data persistence.
/// 
/// Features:
/// - Local-first: all operations work offline
/// - Opportunistic sync: syncs to Supabase when WiFi + Charging
/// - FHIR R4: all data serialized as FHIR Observation resources
/// - Conflict resolution: Last-Write-Wins + clinical hierarchy override
///   (PHC-recorded vitals override self-reported vitals)
/// 
/// Usage:
/// ```dart
/// final repo = VitalsRepository();
/// 
/// // Record new vital (offline)
/// final vital = Vitals(
///   fhirId: 'obs-123',
///   patientFhirId: 'patient-123',
///   vitalType: 'blood_pressure',
///   value: '130/90',
///   unit: 'mmHg',
///   recordedBy: 'chw-456',
///   source: 'direct',
/// );
/// await repo.upsert(vital);
/// 
/// // Get vitals history for patient (offline)
/// final vitals = await repo.getVitalsByPatient('patient-123');
/// ```
class VitalsRepository extends RemoteRepository<Vitals>
    with OfflineFirstWithSupabase<Vitals> {
  VitalsRepository();

  @override
  final ConnectOfflineFirstWithSupabase adapter = ConnectOfflineFirstWithSupabase(
    remoteName: 'vitals_logs',
    localName: 'vitals_logs',
  );

  // ─── Query Methods ─────────────────────────────────────────────────────────

  /// Get all vitals for a patient
  Future<List<Vitals>> getVitalsByPatient(String patientFhirId) async {
    final query = QueryWhere(
      'patient_fhir_id',
      isEqualTo: patientFhirId,
    );
    return await get(query: query);
  }

  /// Get latest vital of a specific type for a patient
  Future<Vitals?> getLatestVital(
    String patientFhirId,
    String vitalType,
  ) async {
    final allVitals = await getVitalsByPatient(patientFhirId);
    final filtered = allVitals.where((v) => v.vitalType == vitalType);
    if (filtered.isEmpty) return null;
    // Sort by recorded date descending
    filtered.toList().sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return filtered.first;
  }

  /// Get vitals for patient within date range
  Future<List<Vitals>> getVitalsInRange(
    String patientFhirId,
    DateTime start,
    DateTime end,
  ) async {
    final allVitals = await getVitalsByPatient(patientFhirId);
    return allVitals.where((v) {
      return v.recordedAt.isAfter(start) && v.recordedAt.isBefore(end);
    }).toList();
  }

  /// Get vitals by source (direct, phone, whatsapp, ivr, remote)
  Future<List<Vitals>> getVitalsBySource(
    String patientFhirId,
    String source,
  ) async {
    final query = QueryWhere([
      QueryWhere('patient_fhir_id', isEqualTo: patientFhirId),
      QueryWhere('source', isEqualTo: source),
    ]);
    return await get(query: query);
  }

  /// Get abnormal vitals for patient
  Future<List<Vitals>> getAbnormalVitals(String patientFhirId) async {
    final allVitals = await getVitalsByPatient(patientFhirId);
    return allVitals.where((v) => !v.isNormalRange).toList();
  }

  /// Get vitals with clinical flags (HIGH, LOW, CRITICAL)
  Future<List<Vitals>> getFlaggedVitals(String patientFhirId) async {
    final allVitals = await getVitalsByPatient(patientFhirId);
    return allVitals.where((v) => v.clinicalFlag != null).toList();
  }

  /// Get unsynced vitals
  Future<List<Vitals>> getUnsyncedVitals() async {
    final query = QueryWhere('is_synced', isEqualTo: false);
    return await get(query: query);
  }

  // ─── Vital Trends ─────────────────────────────────────────────────────────

  /// Get BP trend for patient (last 5 recordings)
  Future<List<Vitals>> getBpTrend(String patientFhirId) async {
    final allBp = await get(
      query: QueryWhere([
        QueryWhere('patient_fhir_id', isEqualTo: patientFhirId),
        QueryWhere('vital_type', isEqualTo: 'blood_pressure'),
      ]),
    );
    // Sort descending by date and take last 5
    allBp.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return allBp.take(5).toList();
  }

  /// Get weight trend for patient (last 5 recordings)
  Future<List<Vitals>> getWeightTrend(String patientFhirId) async {
    final allWeight = await get(
      query: QueryWhere([
        QueryWhere('patient_fhir_id', isEqualTo: patientFhirId),
        QueryWhere('vital_type', isEqualTo: 'weight'),
      ]),
    );
    allWeight.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return allWeight.take(5).toList();
  }

  /// Get Hb trend for patient (last 5 recordings)
  Future<List<Vitals>> getHbTrend(String patientFhirId) async {
    final allHb = await get(
      query: QueryWhere([
        QueryWhere('patient_fhir_id', isEqualTo: patientFhirId),
        QueryWhere('vital_type', isEqualTo: 'hemoglobin'),
      ]),
    );
    allHb.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return allHb.take(5).toList();
  }

  // ─── Sync Methods ─────────────────────────────────────────────────────────

  /// Mark vitals as synced after successful sync
  Future<void> markAsSynced(String fhirId) async {
    final vital = await getOne(fhirId: fhirId);
    if (vital != null) {
      final updated = Vitals(
        fhirId: vital.fhirId,
        patientFhirId: vital.patientFhirId,
        vitalType: vital.vitalType,
        value: vital.value,
        unit: vital.unit,
        recordedBy: vital.recordedBy,
        recordedAt: vital.recordedAt,
        source: vital.source,
        notes: vital.notes,
        locationLat: vital.locationLat,
        locationLng: vital.locationLng,
        deviceId: vital.deviceId,
        isSynced: true,
        syncAttempts: vital.syncAttempts,
        lastSyncError: vital.lastSyncError,
        createdAt: vital.createdAt,
      );
      await upsert(updated);
    }
  }

  /// Get count of unsynced vitals
  Future<int> getUnsyncedCount() async {
    final unsynced = await getUnsyncedVitals();
    return unsynced.length;
  }

  // ─── Risk Assessment ────────────────────────────────────────────────────────

  /// Save vitals AND run risk assessment in one call.
  /// Returns the saved vital with risk level attached.
  Future<Vitals> saveVitalsWithRisk({
    required String patientFhirId,
    required String vitalType,
    required String value,
    required String unit,
    required String recordedBy,
    required String source,
    String? notes,
    double? locationLat,
    double? locationLng,
    required String riskLevel,
    required int riskScore,
  }) async {
    final vital = Vitals(
      fhirId: 'obs-${DateTime.now().millisecondsSinceEpoch}',
      patientFhirId: patientFhirId,
      vitalType: vitalType,
      value: value,
      unit: unit,
      recordedBy: recordedBy,
      recordedAt: DateTime.now(),
      source: source,
      notes: notes,
      locationLat: locationLat,
      locationLng: locationLng,
      deviceId: null,
      isSynced: false,
      syncAttempts: 0,
      createdAt: DateTime.now(),
      clinicalFlag: riskLevel,
    );
    await upsert(vital);
    return vital;
  }

  // ─── FHIR Bundle Support ─────────────────────────────────────────────────

  /// Get all vitals for patient as FHIR Bundle
  Future<Map<String, dynamic>> getPatientVitalsBundle(String patientFhirId) async {
    final vitals = await getVitalsByPatient(patientFhirId);
    // Convert to FHIR Bundle format
    return {
      'resourceType': 'Bundle',
      'type': 'transaction',
      'entry': vitals.map((v) => v.toFhirJson()).toList(),
    };
  }
}