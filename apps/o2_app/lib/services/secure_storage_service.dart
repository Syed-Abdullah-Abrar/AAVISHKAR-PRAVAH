/// Secure Storage Service
/// O2 Platform — Phase 4
///
/// Wraps FlutterSecureStorage for sensitive data.
/// All secrets MUST be stored here — never in constants.dart or source code.
///
/// Keys:
/// - telegram_bot_token: Telegram bot API token
/// - supabase_anon_key: Supabase anonymous key (for reference only)
/// - encryption_key: SQLCipher database encryption key
/// - last_sync_timestamp: Unix timestamp of last successful sync

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorageService {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
    ),
  );

  // ─── Storage Keys ─────────────────────────────────────────────────────────
  static const String keyTelegramToken = 'telegram_bot_token';
  static const String keySupabaseUrl = 'supabase_url';
  static const String keySupabaseKey = 'supabase_anon_key';
  static const String keyLastSync = 'last_sync_timestamp';

  // ─── Telegram Token ────────────────────────────────────────────────────────

  /// Read Telegram bot token from secure storage
  Future<String?> getTelegramToken() async {
    try {
      return await _storage.read(key: keyTelegramToken);
    } catch (e) {
      return null;
    }
  }

  /// Store Telegram bot token securely
  Future<void> setTelegramToken(String token) async {
    await _storage.write(key: keyTelegramToken, value: token);
  }

  /// Check if Telegram token is configured
  Future<bool> hasTelegramToken() async {
    final token = await getTelegramToken();
    return token != null && token.isNotEmpty;
  }

  // ─── Supabase Config ───────────────────────────────────────────────────────

  Future<String?> getSupabaseUrl() async {
    return await _storage.read(key: keySupabaseUrl);
  }

  Future<void> setSupabaseUrl(String url) async {
    await _storage.write(key: keySupabaseUrl, value: url);
  }

  Future<String?> getSupabaseKey() async {
    return await _storage.read(key: keySupabaseKey);
  }

  Future<void> setSupabaseKey(String key) async {
    await _storage.write(key: keySupabaseKey, value: key);
  }

  // ─── Sync Timestamp ─────────────────────────────────────────────────────────

  Future<DateTime?> getLastSyncTime() async {
    final ts = await _storage.read(key: keyLastSync);
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(int.tryParse(ts) ?? 0);
  }

  Future<void> setLastSyncTime(DateTime time) async {
    await _storage.write(
      key: keyLastSync,
      value: time.millisecondsSinceEpoch.toString(),
    );
  }

  // ─── Utility ───────────────────────────────────────────────────────────────

  /// Delete all stored secrets
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// Delete a specific key
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}
