import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/router.dart';
import 'models/patient.dart';
import 'models/vitals.dart';
import 'repositories/patient_repository.dart';
import 'repositories/vitals_repository.dart';
import 'services/sync_service.dart';

export 'models/patient.dart';
export 'models/vitals.dart';
export 'models/clinical_contact.dart';
export 'core/constants.dart';
export 'core/theme.dart';
export 'services/sync_service.dart';
export 'services/fhir_serializer.dart';

// ─── Providers ────────────────────────────────────────────────────────────────

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository();
});

final vitalsRepositoryProvider = Provider<VitalsRepository>((ref) {
  return VitalsRepository();
});

final syncServiceProvider = Provider<SyncService>((ref) {
  return SyncService();
});

final syncStatusStreamProvider = StreamProvider<SyncStatus>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.syncStatusStream;
});

final patientListProvider = FutureProvider<List<Patient>>((ref) async {
  final repo = ref.watch(patientRepositoryProvider);
  return repo.getAllPatients();
});

final selectedPatientProvider = StateProvider<Patient?>((ref) {
  return null;
});

final selectedPatientVitalsProvider = FutureProvider<List<Vitals>>((ref) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return [];
  final repo = ref.watch(vitalsRepositoryProvider);
  return repo.getVitalsForPatient(patient.id);
});

// ─── Root App ─────────────────────────────────────────────────────────────────

class O2App extends ConsumerWidget {
  const O2App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = O2Router(ref: ref).router;
    return MaterialApp.router(
      title: 'O₂ Platform',
      debugShowCheckedModeBanner: false,
      theme: O2Theme.lightTheme,
      darkTheme: O2Theme.darkTheme,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
  }
}
