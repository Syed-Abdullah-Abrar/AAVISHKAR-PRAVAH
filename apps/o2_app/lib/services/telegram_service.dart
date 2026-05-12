/// O2 Platform — Telegram Service
///
/// Telegram bot integration for in-app alerts + patient voice messages.
/// Token is read from FlutterSecureStorage — NEVER hardcoded in source.
/// Set token once via SecureStorageService().setTelegramToken(token).

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import 'secure_storage_service.dart';

class TelegramService {
  final SecureStorageService _secureStorage;
  final String _baseUrl;

  TelegramService({
    SecureStorageService? secureStorage,
    String? baseUrl,
  })  : _secureStorage = secureStorage ?? SecureStorageService(),
        _baseUrl = baseUrl ?? O2Constants.aiServerUrl;

  /// Get Telegram bot token from secure storage.
  /// Falls back to placeholder for demo if not set.
  Future<String> _getToken() async {
    final token = await _secureStorage.getTelegramToken();
    return token ?? O2Constants.telegramBotTokenPlaceholder;
  }

  /// Send a message to a Telegram chat ID.
  /// Used for CHW notifications from Flutter app.
  Future<bool> sendMessage(String chatId, String text) async {
    try {
      final token = await _getToken();
      final uri = Uri.parse('https://api.telegram.org/bot$token/sendMessage');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'chat_id': chatId,
          'text': text,
          'parse_mode': 'Markdown',
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[Telegram] Send failed: $e');
      return false;
    }
  }

  /// Forward a voice message to the IVR backend for STT processing.
  /// Backend returns {transcript, alert_tier, is_critical}
  Future<Map<String, dynamic>> forwardVoiceMessage(
    String patientId,
    String fileId, {
    String language = 'kn',
  }) async {
    try {
      final uri = Uri.parse('$_baseUrl/ivr/ivr/voice-message');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'patient_id': patientId,
          'file_id': fileId,
          'language': language,
        }),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      }
      return {
        'transcript': '',
        'alert_tier': 'LOW',
        'is_critical': false,
        'error': 'HTTP ${response.statusCode}',
      };
    } catch (e) {
      debugPrint('[Telegram] Forward voice failed: $e');
      return {
        'transcript': '',
        'alert_tier': 'LOW',
        'is_critical': false,
        'error': e.toString(),
      };
    }
  }

  /// Get recent messages from the bot (polling for patient voice messages).
  Future<List<dynamic>> getUpdates({int offset = 0}) async {
    try {
      final token = await _getToken();
      final uri = Uri.parse(
        'https://api.telegram.org/bot$token/getUpdates?offset=$offset&timeout=10',
      );
      final response = await _client.get(uri);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['result'] ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  final http.Client _client = http.Client();

  void dispose() {
    _client.close();
  }
}
