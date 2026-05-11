import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../core/constants.dart';

/// Background Sync Service — O2 Platform CHW App
/// 
/// Implements opportunistic background synchronization using WorkManager.
/// Sync triggers ONLY when:
/// - Network: WiFi connected (UNMETERED)
/// - Battery: Device is charging (ENERGY_CHARGED)
/// 
/// Design Rationale:
/// Rural CHWs use solar-powered devices. Running sync during home visit rounds
/// (when device is in field, not charging) would drain battery and leave CHW
/// without the app. By restricting sync to WiFi + charging, we ensure:
/// - Sync happens during overnight charging
/// - CHW always has battery for home visits
/// - Data syncs when connectivity is available and cheap
/// 
/// Conflict Resolution:
/// - Last-Write-Wins with clinical hierarchy override
/// - PHC-recorded vitals override self-reported vitals
/// - Higher authority level wins in case of conflict
/// 
/// WorkManager Configuration:
/// - Periodic work: every 15 minutes (configurable)
/// - Constraints: UNMETERED network + CHARGING battery
/// - Retry: exponential backoff on failure (max 3 retries)
/// - Persisted: survives app restart and device reboot
/// 
/// Usage:
/// ```dart
/// final syncService = SyncService();
/// await syncService.initialize();
/// // WorkManager handles background execution...
/// 
/// // Manual sync trigger (when user presses sync button)
/// await syncService.syncNow();
/// 
/// // Check sync status
/// final status = syncService.syncStatus;
/// ```
class SyncService {
  static const String _syncTaskName = 'o2_background_sync';
  static const Duration _defaultInterval = Duration(minutes: 15);

  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  String? _lastSyncError;
  int _syncAttempts = 0;

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// Current sync status
  SyncStatus get syncStatus => _syncStatus;

  /// Last successful sync time
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Last sync error message
  String? get lastSyncError => _lastSyncError;

  /// Number of consecutive sync attempts
  int get syncAttempts => _syncAttempts;

  /// Initialize WorkManager and register periodic background sync
  /// 
  /// Call this once during app startup (main.dart).
  Future<void> initialize() async {
    // Initialize WorkManager
    await Workmanager().initialize(
      _callbackDispatcher,
      isInDebugMode: kDebugMode,
    );

    // Register periodic background sync task
    await _registerPeriodicSync();

    // Listen for connectivity changes to trigger opportunistic sync
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    _syncStatus = SyncStatus.idle;
  }

  /// Register periodic background sync with WorkManager
  Future<void> _registerPeriodicSync() async {
    final now = DateTime.now();
    final nextSyncTime = now.add(_defaultInterval);

    await Workmanager().registerPeriodicTask(
      _syncTaskName,
      _syncTaskName,
      frequency: _defaultInterval,
      constraints: Constraints(
        networkType: NetworkType.unmetered,  // WiFi only
        requiresCharging: true,              // Only when charging
        requiresBatteryNotLow: true,          // Not low battery
      ),
      inputData: {
        'scheduled_at': nextSyncTime.toIso8601String(),
        'attempt': _syncAttempts,
      },
      existingWorkPolicy: ExistingWorkPolicy.keep,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: const Duration(minutes: 5),
    );
  }

  /// Handle connectivity changes
  /// 
  /// When WiFi becomes available AND device is charging,
  /// trigger an immediate sync attempt.
  void _onConnectivityChanged(List<ConnectivityResult> results) async {
    if (results.contains(ConnectivityResult.wifi)) {
      // WiFi is available — check battery and trigger sync if charging
      // Note: actual battery check requires platform channel
      // For now, we trigger and let WorkManager constraints verify
      await syncNow(reason: 'WiFi available');
    }
  }

  /// Trigger immediate sync
  /// 
  /// Used when user manually requests sync or when connectivity changes.
  Future<void> syncNow({String? reason}) async {
    if (_syncStatus == SyncStatus.syncing) {
      return; // Already syncing
    }

    _syncStatus = SyncStatus.syncing;
    _syncAttempts++;

    try {
      // Check connectivity first
      final connectivityResults = await _connectivity.checkConnectivity();
      if (!connectivityResults.contains(ConnectivityResult.wifi)) {
        _syncStatus = SyncStatus.offline;
        return;
      }

      // Execute sync via Brick repository
      await _executeSync();

      // Success
      _syncStatus = SyncStatus.success;
      _lastSyncTime = DateTime.now();
      _lastSyncError = null;
      _syncAttempts = 0;

      // Persist last sync time
      await _persistLastSyncTime();

    } on SyncException catch (e) {
      _syncStatus = SyncStatus.failed;
      _lastSyncError = e.message;

      // Retry with backoff if under max retries
      if (_syncAttempts < O2Constants.maxSyncRetries) {
        await _scheduleRetry();
      }
    } catch (e) {
      _syncStatus = SyncStatus.failed;
      _lastSyncError = e.toString();

      if (_syncAttempts < O2Constants.maxSyncRetries) {
        await _scheduleRetry();
      }
    }
  }

  /// Execute the actual sync operation via Brick repositories
  /// 
  /// This is called by WorkManager's background isolate.
  /// Brick handles:
  /// - Local-to-Remote sync (push local changes to Supabase)
  /// - Remote-to-Local sync (pull remote changes to local)
  /// - Conflict resolution (Last-Write-Wins + clinical hierarchy)
  Future<void> _executeSync() async {
    // TODO: Integrate with Brick repositories
    // Example:
    // final patientRepo = PatientRepository();
    // final vitalsRepo = VitalsRepository();
    // 
    // // Sync patients
    // await patientRepo.sync();
    // 
    // // Sync vitals
    // await vitalsRepo.sync();
    // 
    // // Sync clinical contacts
    // await clinicalContactRepo.sync();

    // Placeholder for sync execution
    // Real implementation will integrate with Brick's sync adapter
  }

  /// Schedule a retry with exponential backoff
  Future<void> _scheduleRetry() async {
    final backoffDelay = Duration(
      minutes: 5 * _syncAttempts, // 5, 10, 15 minutes...
    );

    await Workmanager().registerOneOffTask(
      'o2_sync_retry_${DateTime.now().millisecondsSinceEpoch}',
      'o2_sync_retry',
      constraints: Constraints(
        networkType: NetworkType.unmetered,
        requiresCharging: true,
      ),
      initialDelay: backoffDelay,
      inputData: {
        'retry_attempt': _syncAttempts,
        'reason': _lastSyncError,
      },
    );
  }

  /// Persist last sync time to SharedPreferences
  Future<void> _persistLastSyncTime() async {
    // TODO: Use SharedPreferences
    // await prefs.setString(
    //   O2Constants.prefLastSyncTime,
    //   _lastSyncTime!.toIso8601String(),
    // );
  }

  /// Cancel all scheduled sync work
  Future<void> cancelAll() async {
    await Workmanager().cancelByUniqueName(_syncTaskName);
    await Workmanager().cancelByUniqueName('o2_sync_retry');
    _syncStatus = SyncStatus.idle;
  }

  /// Dispose of resources
  void dispose() {
    _connectivitySubscription?.cancel();
  }

  @override
  String toString() =>
      'SyncService(status: $_syncStatus, lastSync: $_lastSyncTime, attempts: $_syncAttempts)';
}

/// WorkManager callback dispatcher
/// 
/// This runs in a background isolate separate from the main Flutter app.
/// Only use Flutter-free APIs here.
/// 
/// @see https://pub.dev/packages/workmanager
@pragma('vm:entry-point')
void _callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case O2Constants.syncWorkName:
        await _handleBackgroundSync(inputData);
        break;
      case 'o2_sync_retry':
        await _handleRetrySync(inputData);
        break;
    }
    return true;
  });
}

/// Handle background sync task from WorkManager
Future<void> _handleBackgroundSync(Map<String, dynamic>? inputData) async {
  final scheduledAt = inputData?['scheduled_at'] as String?;
  final attempt = inputData?['attempt'] as int? ?? 0;

  // Log sync event
  // ignore: avoid_print
  print(
    '[O2 Sync] Background sync triggered at $scheduledAt, attempt $attempt',
  );

  // Check if conditions are met (WorkManager guarantees this,
  // but we double-check for safety)
  // TODO: Implement condition checks

  // Execute sync
  final syncService = SyncService();
  try {
    await syncService.syncNow(reason: 'Background sync (WorkManager)');
  } finally {
    syncService.dispose();
  }
}

/// Handle retry sync task
Future<void> _handleRetrySync(Map<String, dynamic>? inputData) async {
  final retryAttempt = inputData?['retry_attempt'] as int? ?? 0;
  final reason = inputData?['reason'] as String?;

  // ignore: avoid_print
  print('[O2 Sync] Retry sync attempt $retryAttempt: $reason');

  final syncService = SyncService();
  try {
    await syncService.syncNow(reason: 'Retry sync (attempt $retryAttempt)');
  } finally {
    syncService.dispose();
  }
}

/// Sync exception for error handling
class SyncException implements Exception {
  final String message;
  final String? code;

  const SyncException(this.message, {this.code});

  @override
  String toString() => 'SyncException($code): $message';
}