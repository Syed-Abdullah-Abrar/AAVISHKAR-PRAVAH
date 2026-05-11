import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'core/constants.dart';
import 'core/router.dart';
import 'services/encryption_service.dart';
import 'services/sync_service.dart';

/// O2 Platform — Main Application Entry Point
/// 
/// Offline-first maternal healthcare monitoring for Community Health Workers.
/// 
/// Architecture:
/// - Flutter for cross-platform mobile UI
/// - Brick ORM for offline-first data persistence
/// - SQLCipher for AES-256 encryption at rest
/// - WorkManager for background sync (WiFi + Charging only)
/// - FHIR R4 for clinical data standardization
/// - Bhashini for voice input/output in Kannada/Hindi
/// 
/// Phase 1 MVP:
/// - Patient registration and vitals recording (offline)
/// - Risk assessment via Python FastAPI AI server
/// - SBAR handover document generation
/// - IVR patient communication layer (missed call → WhatsApp)
/// - ABDM mock integration
/// 
/// @see STRATEGY.md for full product strategy
/// @see docs/plans/2026-05-11-001-feat-o2-platform-phase1-plan.md for implementation plan
class O2App extends ConsumerStatefulWidget {
  const O2App({super.key});

  @override
  ConsumerState<O2App> createState() => _O2AppState();
}

class _O2AppState extends ConsumerState<O2App> with WidgetsBindingObserver {
  late final O2Router _appRouter;
  final SyncService _syncService = SyncService();
  bool _isInitialized = false;
  String? _initError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // App resumed — check sync status
        _checkSyncStatus();
        break;
      case AppLifecycleState.paused:
        // App paused — sync service continues in background via WorkManager
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _initialize() async {
    try {
      // Initialize encryption service (opens encrypted database)
      final db = await encryptionService.openDatabase();
      
      // Initialize sync service (registers WorkManager background tasks)
      await _syncService.initialize();

      // Initialize router
      _appRouter = O2Router(
        patientRepository: patientRepositoryProvider,
        vitalsRepository: vitalsRepositoryProvider,
      );

      setState(() {
        _isInitialized = true;
      });
    } on EncryptionException catch (e) {
      setState(() {
        _initError = 'Encryption error: ${e.message}';
      });
    } catch (e) {
      setState(() {
        _initError = 'Initialization failed: $e';
      });
    }
  }

  Future<void> _checkSyncStatus() async {
    // Trigger sync if conditions are met
    await _syncService.syncNow(reason: 'App resumed');
  }

  @override
  Widget build(BuildContext context) {
    if (_initError != null) {
      return MaterialApp(
        title: O2Constants.appName,
        theme: O2Theme.lightTheme,
        home: ErrorInitializationScreen(error: _initError!),
      );
    }

    if (!_isInitialized) {
      return MaterialApp(
        title: O2Constants.appName,
        theme: O2Theme.lightTheme,
        home: const SplashScreen(),
      );
    }

    return MaterialApp.router(
      title: O2Constants.appName,
      theme: O2Theme.lightTheme,
      debugShowCheckedModeBanner: false,
      routerConfig: _appRouter.router,
    );
  }
}

/// Splash Screen shown during initialization
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: O2Theme.primaryGreen,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo placeholder
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.favorite,
                size: 64,
                color: O2Theme.primaryGreen,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'O2 Platform',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Maternal Healthcare',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            const Text(
              'Initializing secure storage...',
              style: TextStyle(
                fontSize: 12,
                color: Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Error Screen shown when initialization fails
class ErrorInitializationScreen extends StatelessWidget {
  final String error;
  const ErrorInitializationScreen({super.key, required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: O2Theme.error,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 80,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
              const Text(
                'Initialization Failed',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                'Please contact your supervisor or try restarting the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white60,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Riverpod Providers ─────────────────────────────────────────────────────────

import 'repositories/patient_repository.dart';
import 'repositories/vitals_repository.dart';

/// Patient Repository Provider
final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository();
});

/// Vitals Repository Provider
final vitalsRepositoryProvider = Provider<VitalsRepository>((ref) {
  return VitalsRepository();
});

/// Sync Status Provider
final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final syncService = ref.watch(syncServiceProvider);
  return syncService.syncStatusStream;
});

/// Sync Service Provider
final syncServiceProvider = Provider<SyncService>((ref) {
  final service = SyncService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Current CHW Provider (from secure storage)
final currentChwProvider = FutureProvider<String?>((ref) async {
  // TODO: Load from secure storage
  return null;
});

/// Current PHC Provider (from secure storage)
final currentPhcProvider = FutureProvider<String?>((ref) async {
  // TODO: Load from secure storage
  return null;
});

/// App Language Provider
final appLanguageProvider = StateProvider<String>((ref) {
  return O2Constants.defaultLanguage;
});

/// App Region Provider  
final appRegionProvider = StateProvider<String>((ref) {
  return O2Constants.defaultRegion;
});

/// Patient List Provider
final patientListProvider = FutureProvider<List<Patient>>((ref) async {
  final repo = ref.watch(patientRepositoryProvider);
  final chwId = await ref.watch(currentChwProvider.future);
  if (chwId == null) return [];
  return repo.getPatientsByChw(chwId);
});

/// Selected Patient Provider
final selectedPatientProvider = StateProvider<Patient?>((ref) {
  return null;
});

/// Vitals for Selected Patient Provider
final selectedPatientVitalsProvider = FutureProvider<List<Vitals>>((ref) async {
  final patient = ref.watch(selectedPatientProvider);
  if (patient == null) return [];
  final repo = ref.watch(vitalsRepositoryProvider);
  return repo.getVitalsByPatient(patient.fhirId);
});

// Re-export models for convenience
export 'models/patient.dart';
export 'models/vitals.dart';
export 'models/clinical_contact.dart';
export 'core/constants.dart';
export 'core/theme.dart';
export 'services/encryption_service.dart';
export 'services/sync_service.dart';
export 'services/fhir_serializer.dart';
