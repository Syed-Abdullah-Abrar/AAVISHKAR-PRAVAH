import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import '../models/patient.dart';

/// Patient Repository — O2 Platform CHW App
/// 
/// Brick repository for offline-first patient data persistence.
/// Acts as single source of truth for patient records.
/// 
/// Features:
/// - Local-first: all operations work offline
/// - Opportunistic sync: syncs to Supabase when WiFi + Charging
/// - FHIR R4: all data serialized as FHIR resources
/// - Conflict resolution: Last-Write-Wins + PHC hierarchy override
/// 
/// Usage:
/// ```dart
/// final repo = PatientRepository();
/// 
/// // Get patient by ID (offline)
/// final patient = await repo.get('patient-123');
/// 
/// // Register new patient (offline)
/// await repo.upsert(newPatient);
/// 
/// // Get all patients for this CHW (offline)
/// final patients = await repo.getPatientsByChw('chw-456');
/// ```
class PatientRepository extends RemoteRepository<Patient>
    with OfflineFirstWithSupabase<Patient> {
  PatientRepository();

  @override
  final ConnectOfflineFirstWithSupabase adapter = ConnectOfflineFirstWithSupabase(
    remoteName: 'patients',
    localName: 'patients',
  );

  // ─── Query Methods ─────────────────────────────────────────────────────────

  /// Get all patients assigned to a CHW
  Future<List<Patient>> getPatientsByChw(String chwId) async {
    final query = QueryWhere(
      'assigned_chw_id',
      isEqualTo: chwId,
    );
    return await get(query: query);
  }

  /// Get all patients for a PHC
  Future<List<Patient>> getPatientsByPhc(String phcId) async {
    final query = QueryWhere(
      'phc_id',
      isEqualTo: phcId,
    );
    return await get(query: query);
  }

  /// Get high-risk patients
  Future<List<Patient>> getHighRiskPatients(String chwId) async {
    final query = QueryWhere([
      QueryWhere('assigned_chw_id', isEqualTo: chwId),
      QueryWhere('high_risk_pregnancy', isEqualTo: true),
    ]);
    return await get(query: query);
  }

  /// Get patients with upcoming visits (next 7 days)
  Future<List<Patient>> getUpcomingVisits(String chwId) async {
    final now = DateTime.now();
    final weekFromNow = now.add(const Duration(days: 7));
    
    // Query for patients with next_visit_date between now and weekFromNow
    // Note: This requires custom SQL in Brick - simplified here
    final allPatients = await getPatientsByChw(chwId);
    return allPatients.where((p) {
      if (p.nextVisitDate == null) return false;
      return p.nextVisitDate!.isAfter(now) && 
             p.nextVisitDate!.isBefore(weekFromNow);
    }).toList();
  }

  /// Get overdue patients (missed scheduled visits)
  Future<List<Patient>> getOverduePatients(String chwId) async {
    final now = DateTime.now();
    final allPatients = await getPatientsByChw(chwId);
    return allPatients.where((p) {
      if (p.nextVisitDate == null) return false;
      return p.nextVisitDate!.isBefore(now);
    }).toList();
  }

  /// Get active pregnancies (EDD not passed)
  Future<List<Patient>> getActivePregnancies(String chwId) async {
    final allPatients = await getPatientsByChw(chwId);
    final now = DateTime.now();
    return allPatients.where((p) {
      if (p.eddDate == null) return true; // Include if EDD unknown
      return p.eddDate!.isAfter(now);
    }).toList();
  }

  /// Get patients by village
  Future<List<Patient>> getPatientsByVillage(String chwId, String village) async {
    final query = QueryWhere([
      QueryWhere('assigned_chw_id', isEqualTo: chwId),
      QueryWhere('village', isEqualTo: village),
    ]);
    return await get(query: query);
  }

  // ─── Sync Methods ─────────────────────────────────────────────────────────

  /// Force sync with remote (for manual refresh)
  Future<void> sync() async {
    await syncRemote();
  }

  /// Get count of unsynced patients
  Future<int> getUnsyncedCount() async {
    final query = QueryWhere('is_synced', isEqualTo: false);
    final patients = await get(query: query);
    return patients.length;
  }

  // ─── FHIR Bundle Support ─────────────────────────────────────────────────

  /// Get patient with FHIR Bundle (for sync)
  Future<Map<String, dynamic>> getPatientBundle(String fhirId) async {
    final patient = await getOne(fhirId: fhirId);
    if (patient == null) {
      throw PatientNotFoundException(fhirId);
    }
    return patient.toFhirJson();
  }
}

/// Exception thrown when patient is not found
class PatientNotFoundException implements Exception {
  final String fhirId;
  const PatientNotFoundException(this.fhirId);

  @override
  String toString() => 'Patient not found: $fhirId';
}
