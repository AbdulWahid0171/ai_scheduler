import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reminder.dart';

enum ApiProvider { gemini, openRouter }

class ApiChatSettings {
  const ApiChatSettings({
    required this.provider,
    required this.geminiApiKey,
    required this.geminiModel,
    required this.openRouterApiKey,
    required this.openRouterModel,
  });

  final ApiProvider provider;
  final String geminiApiKey;
  final String geminiModel;
  final String openRouterApiKey;
  final String openRouterModel;

  String get activeKey =>
      provider == ApiProvider.gemini ? geminiApiKey : openRouterApiKey;

  String get activeModel =>
      provider == ApiProvider.gemini ? geminiModel : openRouterModel;

  ApiChatSettings copyWith({
    ApiProvider? provider,
    String? geminiApiKey,
    String? geminiModel,
    String? openRouterApiKey,
    String? openRouterModel,
  }) {
    return ApiChatSettings(
      provider: provider ?? this.provider,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      geminiModel: geminiModel ?? this.geminiModel,
      openRouterApiKey: openRouterApiKey ?? this.openRouterApiKey,
      openRouterModel: openRouterModel ?? this.openRouterModel,
    );
  }
}

class ApiInferenceService {
  ApiInferenceService._();

  static final ApiInferenceService instance = ApiInferenceService._();

  static const String _providerKey = 'api_chat_provider';
  static const String _geminiApiKeyPref = 'api_chat_gemini_key';
  static const String _geminiModelPref = 'api_chat_gemini_model';
  static const String _openRouterApiKeyPref = 'api_chat_openrouter_key';
  static const String _openRouterModelPref = 'api_chat_openrouter_model';

  ApiChatSettings _settings = const ApiChatSettings(
    provider: ApiProvider.gemini,
    geminiApiKey: '',
    geminiModel: 'gemini-2.5-flash',
    openRouterApiKey: '',
    openRouterModel: 'google/gemma-4-26b-a4b-it:free',
  );

  ApiChatSettings get settings => _settings;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final providerRaw = prefs.getString(_providerKey) ?? 'gemini';
    _settings = ApiChatSettings(
      provider: providerRaw == 'openrouter'
          ? ApiProvider.openRouter
          : ApiProvider.gemini,
      geminiApiKey: prefs.getString(_geminiApiKeyPref) ?? '',
      geminiModel: prefs.getString(_geminiModelPref) ?? 'gemini-2.5-flash',
      openRouterApiKey: prefs.getString(_openRouterApiKeyPref) ?? '',
      openRouterModel:
          prefs.getString(_openRouterModelPref) ??
              'google/gemma-4-26b-a4b-it:free',
    );
  }

  Future<void> saveSettings(ApiChatSettings next) async {
    final prefs = await SharedPreferences.getInstance();
    _settings = next;
    await prefs.setString(
      _providerKey,
      next.provider == ApiProvider.gemini ? 'gemini' : 'openrouter',
    );
    await prefs.setString(_geminiApiKeyPref, next.geminiApiKey);
    await prefs.setString(_geminiModelPref, next.geminiModel);
    await prefs.setString(_openRouterApiKeyPref, next.openRouterApiKey);
    await prefs.setString(_openRouterModelPref, next.openRouterModel);
  }

  Future<Map<String, dynamic>> processMessage({
    required String message,
    required List<Map<String, String>> history,
    required List<Reminder> reminders,
  }) async {
    if (_settings.activeKey.trim().isEmpty) {
      return {
        'type': 'chat',
        'message':
            'Add your ${_settings.provider == ApiProvider.gemini ? 'Gemini' : 'OpenRouter'} API key in Settings to use API Chat.',
        'shouldSave': false,
      };
    }

    final payload = _buildInstructionPayload(
      userMessage: message,
      history: history,
      reminders: reminders,
    );

    try {
      final rawText = _settings.provider == ApiProvider.gemini
          ? await _callGemini(payload)
          : await _callOpenRouter(payload);
      final normalized = _extractJson(rawText);
      final decoded = jsonDecode(normalized);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid response shape');
      }
      return _normalizeApiResult(decoded);
    } catch (_) {
      return {
        'type': 'chat',
        'message':
            'API Chat could not process that request right now. Clear the API chat or adjust the provider settings and try again.',
        'shouldSave': false,
      };
    }
  }

  Map<String, dynamic> _normalizeApiResult(Map<String, dynamic> decoded) {
    final type = decoded['type']?.toString() ?? 'chat';
    if (type == 'reminders') {
      final reminders = (decoded['reminders'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', value)))
          .toList();
      return {
        'type': 'reminders',
        'message': decoded['message']?.toString() ?? 'I added that schedule.',
        'reminders': reminders,
        'shouldSave': reminders.isNotEmpty,
      };
    }
    if (type == 'update') {
      final updates = (decoded['updates'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', value)))
          .toList();
      return {
        'type': 'update',
        'message': decoded['message']?.toString() ?? 'I updated that schedule.',
        'updates': updates,
        'shouldSave': updates.isNotEmpty,
      };
    }

    return {
      'type': 'chat',
      'message': decoded['message']?.toString() ??
          'I could not interpret that request.',
      'shouldSave': false,
    };
  }

  String _buildInstructionPayload({
    required String userMessage,
    required List<Map<String, String>> history,
    required List<Reminder> reminders,
  }) {
    final trimmedHistory = history.length > 6
        ? history.sublist(history.length - 6)
        : history;
    final historyText = trimmedHistory.isEmpty
        ? 'No prior conversation.'
        : trimmedHistory
            .map((item) => '${item['role']}: ${item['text']}')
            .join('\n');
    final reminderText = reminders
        .where((item) => !item.isCompleted)
        .take(10)
        .map(
          (item) =>
              '- id:${item.id ?? 0} | ${item.title} | ${item.dateTime.toIso8601String()}',
        )
        .join('\n');

    return '''
You are an API scheduling assistant inside a reminder app.
Reply with exactly one JSON object and nothing else.

Rules:
- Supported types: "chat", "reminders", "update"
- For unrelated chat, use type "chat"
- For creating reminders, use type "reminders" with a "reminders" array
- For updating reminders, use type "update" with an "updates" array
- Never invent reminder ids that are not in the reminder list
- If unsure, return type "chat" with a short clarification message

Recent conversation:
$historyText

Active reminders:
$reminderText

Current user request:
$userMessage

JSON shapes:
{"type":"chat","message":"short reply"}
{"type":"reminders","message":"short reply","reminders":[{"title":"Task","date_time":"2026-08-19T08:30:00","priority":"medium"}]}
{"type":"update","message":"short reply","updates":[{"id":2,"title":"Existing title","date_time":"2026-08-20T08:30:00","priority":"medium"}]}
''';
  }

  Future<String> _callGemini(String payload) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/${_settings.geminiModel}:generateContent',
      );
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('x-goog-api-key', _settings.geminiApiKey);
      request.add(
        utf8.encode(
          jsonEncode({
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': payload},
                ],
              },
            ],
          }),
        ),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('Gemini request failed');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) {
        throw const FormatException('No Gemini candidates');
      }
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? const [];
      final text = parts
          .map((part) => part['text']?.toString() ?? '')
          .join()
          .trim();
      if (text.isEmpty) {
        throw const FormatException('Empty Gemini response');
      }
      return text;
    } finally {
      client.close(force: true);
    }
  }

  Future<String> _callOpenRouter(String payload) async {
    final client = HttpClient();
    try {
      final uri = Uri.parse('https://openrouter.ai/api/v1/chat/completions');
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set(
        'Authorization',
        'Bearer ${_settings.openRouterApiKey}',
      );
      request.add(
        utf8.encode(
          jsonEncode({
            'model': _settings.openRouterModel,
            'temperature': 0.2,
            'max_tokens': 500,
            'messages': [
              {
                'role': 'user',
                'content': payload,
              },
            ],
          }),
        ),
      );
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('OpenRouter request failed');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) {
        throw const FormatException('No OpenRouter choices');
      }
      final content =
          choices.first['message']?['content']?.toString().trim() ?? '';
      if (content.isEmpty) {
        throw const FormatException('Empty OpenRouter response');
      }
      return content;
    } finally {
      client.close(force: true);
    }
  }

  String _extractJson(String text) {
    final cleaned = text
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
        .replaceAll(RegExp(r'```$', multiLine: true), '')
        .trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return cleaned;
    }
    return cleaned.substring(start, end + 1);
  }
}
