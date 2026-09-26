import 'dart:convert';
import 'dart:io';

/// Server-side RAG plus Gemini response. The token is supplied only to a
/// development build through --dart-define and is never committed to source.
class RemoteAssistantService {
  static const _endpoint = String.fromEnvironment(
    'GOLF_COACH_RAG_ENDPOINT',
    defaultValue: 'https://metaoffice.co.kr/golf-coach-ai/v1/answer',
  );
  static const _token = String.fromEnvironment('GOLF_COACH_API_TOKEN');

  static Future<String?> answer({
    required String message,
    required bool hasAnalysis,
  }) async {
    if (_token.isEmpty || message.length > 1000) return null;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(Uri.parse(_endpoint));
      request.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      request.write(jsonEncode({
        'message': message,
        'context': {'has_analysis': hasAnalysis, 'client': 'android'},
      }));
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) return null;
      final raw = await utf8.decoder.bind(response).join();
      final value = jsonDecode(raw);
      final reply = value is Map ? value['reply'] : null;
      return reply is String && reply.trim().length >= 2 ? reply.trim() : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
