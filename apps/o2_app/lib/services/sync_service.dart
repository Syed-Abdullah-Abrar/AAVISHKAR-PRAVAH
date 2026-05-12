import 'dart:async';
import 'package:flutter/foundation.dart';

/// Sync status states
enum SyncState { idle, syncing, success, error }

class SyncStatus {
  final SyncState state;
  final String message;
  final int? pendingCount;

  const SyncStatus({
    required this.state,
    required this.message,
    this.pendingCount,
  });

  static const idle = SyncStatus(state: SyncState.idle, message: 'Ready');
}

/// SyncService — manages background sync queue between local SQLite and server
class SyncService {
  final _statusController = StreamController<SyncStatus>.broadcast();

  Stream<SyncStatus> get syncStatusStream => _statusController.stream;

  bool _isSyncing = false;

  /// Trigger a manual sync attempt
  Future<void> syncNow() async {
    if (_isSyncing) return;
    _isSyncing = true;
    _statusController.add(const SyncStatus(
      state: SyncState.syncing,
      message: 'Syncing with server...',
    ));

    try {
      // In demo mode: simulate sync delay
      await Future.delayed(const Duration(seconds: 2));
      _statusController.add(const SyncStatus(
        state: SyncState.success,
        message: 'Sync complete',
        pendingCount: 0,
      ));
      debugPrint('[SyncService] Sync successful');
    } catch (e) {
      _statusController.add(SyncStatus(
        state: SyncState.error,
        message: 'Sync failed: $e',
      ));
      debugPrint('[SyncService] Sync error: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void dispose() {
    _statusController.close();
  }
}