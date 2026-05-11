/// O2 Platform — Telegram Service
///
/// Telegram bot integration for in-app alerts + patient voice messages.
/// Uses python-telegram-bot token already configured in FastAPI backend.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class TelegramService {
  // Use deployed backend URL — set by constants.dart
  static const String botToken = '8717671171:AAEmr0UNaBRuZvRoHeJ5SYMdd87N1-xFZYg';
  static const String baseUrl = 'http://10.0.2.2:8000'; // Android emulator

  final http.Client _client;

  TelegramService({http.Client? client}) : _client = client ?? http.Client();

  /// Send a message to a Telegram chat ID.
  /// Used for CHW notifications from Flutter app.
  Future<bool> sendMessage(String chatId, String text) async {
    try {
      final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');
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

  /// Forward a voice message file_id to the IVR backend for processing.
  /// Returns {transcript, alert_tier, is_critical}
  Future<Map<String, dynamic>> forwardVoiceMessage(
    String patientId,
    String fileId, {
    String language = 'kn',
  }) async {
    try {
      final uri = Uri.parse('$baseUrl/ivr/voice-message');
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
      } else {
        return {
          'transcript': '',
          'alert_tier': 'LOW',
          'is_critical': false,
          'error': response.statusCode,
        };
      }
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
      final uri = Uri.parse(
        'https://api.telegram.org/bot$botToken/getUpdates?offset=$offset&timeout=10',
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

  void dispose() {
    _client.close();
  }
}