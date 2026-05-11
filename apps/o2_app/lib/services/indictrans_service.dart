/// O2 Platform — IndiTrans2 STT/TTS Service
///
/// Replace Bhashini stubs in constants.dart with this IndicTrans2 HTTP client.
/// Runs locally via Docker: docker run -d -p 8000:8000 --name indictrans aiforskill/indictrans2:latest

import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:convert';

class IndicTransService {
  // Use 10.0.2.2 for Android emulator to reach host's localhost:8000
  // For physical device, use the actual deployed server URL
  static const String baseUrl = 'http://10.0.2.2:8000';
  static const String sttEndpoint = '/asr';
  static const String ttsEndpoint = '/tts';

  final http.Client _client;

  IndicTransService({http.Client? client}) : _client = client ?? http.Client();

  /// Language code mapping (Dart-side → IndicTrans2 container)
  static const Map<String, String> langMap = {
    'kn': 'kan',  // Kannada
    'hi': 'hin',  // Hindi
    'en': 'eng',  // English
    'ta': 'tam',  // Tamil
    'te': 'tel',  // Telugu
  };

  /// Transcribe audio file to text.
  /// [audioPath] — path to audio file on device
  /// [lang] — language code: kn, hi, en
  Future<String> transcribe(String audioPath, {String lang = 'kn'}) async {
    final langCode = langMap[lang] ?? 'kan';

    try {
      final uri = Uri.parse('$baseUrl$sttEndpoint');
      final request = http.MultipartRequest('POST', uri);
      request.fields['language'] = langCode;
      request.files.add(await http.MultipartFile.fromPath('audio', audioPath));

      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['text'] ?? '';
      } else {
        return 'STT error: ${response.statusCode}';
      }
    } catch (e) {
      return 'STT failed: $e';
    }
  }

  /// Synthesize text to speech audio file.
  /// [text] — text to synthesize
  /// [lang] — language code: kn, hi, en
  /// Returns path to generated .wav file
  Future<String> synthesize(String text, {String lang = 'kn', String outputPath = 'output.wav'}) async {
    final langCode = langMap[lang] ?? 'kan';

    try {
      final uri = Uri.parse('$baseUrl$ttsEndpoint');
      final response = await _client.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'text': text, 'language': langCode}),
      );

      if (response.statusCode == 200) {
        final file = File(outputPath);
        await file.writeAsBytes(response.bodyBytes);
        return outputPath;
      } else {
        return 'TTS error: ${response.statusCode}';
      }
    } catch (e) {
      return 'TTS failed: $e';
    }
  }

  /// Health check — returns true if IndicTrans2 Docker is reachable
  Future<bool> healthCheck() async {
    try {
      final uri = Uri.parse('$baseUrl/health');
      final response = await _client.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _client.close();
  }
}