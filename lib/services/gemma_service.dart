import 'dart:async';
import 'dart:convert';

import 'package:flutter_gemma/flutter_gemma.dart';

import '../models/reminder.dart';
import '../utils/date_utils.dart';
import 'nl_parser.dart';

enum GemmaStatus {
  uninitialized,
  checking,
  downloading,
  loading,
  ready,
  error,
  unavailable
}

class GemmaService {
  GemmaService._();

  static final GemmaService instance = GemmaService._();

  final FlutterGemmaPlugin _gemma = FlutterGemmaPlugin.instance;
  final NaturalLanguageParser _parser = NaturalLanguageParser();
  final StreamController<GemmaStatus> _statusController =
      StreamController<GemmaStatus>.broadcast();

  InferenceModel? _model;
  GemmaStatus _status = GemmaStatus.uninitialized;
  int _consecutiveModelFailures = 0;

  GemmaStatus get status => _status;
  Stream<GemmaStatus> get statusStream => _statusController.stream;

  Future<void> loadModel() async {
    if (_status == GemmaStatus.ready || _status == GemmaStatus.loading) {
      return;
    }

    _updateStatus(GemmaStatus.loading);
    try {
      await FlutterGemma.installModel(modelType: ModelType.gemmaIt)
          .fromAsset('assets/models/gemma3-1b-it-int4.task')
          .install();

      _model = await _gemma.createModel(
        modelType: ModelType.gemmaIt,
        maxTokens: 1024,
      );

      _updateStatus(_model != null ? GemmaStatus.ready : GemmaStatus.unavailable);
    } catch (_) {
      _updateStatus(GemmaStatus.unavailable);
    }
  }

  Future<void> unloadModel() async {
    _model = null;
    _updateStatus(GemmaStatus.uninitialized);
  }

  Future<Map<String, dynamic>> processMessage(
    String message, {
    List<Reminder> contextReminders = const [],
    List<Map<String, String>> history = const [],
    bool isRetry = false,
  }) async {
    final trimmed = message.trim();
    final generalQuestion = _extractGeneralQuestion(trimmed);
    if (generalQuestion != null) {
      return _processGeneralQuestion(generalQuestion);
    }

    final localResult = _handleLocally(trimmed, contextReminders);
    if (localResult != null) {
      return localResult;
    }

    if (!_shouldUseModel(trimmed)) {
      return _nonSchedulingReply();
    }

    if (_status != GemmaStatus.ready || _model == null) {
      return _nonSchedulingReply(
        suffix:
            ' Try asking about reminders, today, tomorrow, or creating a task with a date and time.',
      );
    }

    final prompt = _buildChatPrompt(
      userMessage: trimmed,
      reminders: contextReminders,
      recentHistory: history,
      isRetry: isRetry,
    );

    try {
      final session = await _model!.createSession(temperature: 0.3, topK: 32);
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      final response = await session.getResponse().timeout(
        const Duration(seconds: 45),
      );

      if (response.trim().isEmpty) {
        await _recordModelFailure();
        return _fallbackChat();
      }

      _recordModelSuccess();

      final cleaned = _extractJson(response);
      if (!_looksLikeJson(cleaned)) {
        return {
          'type': 'chat',
          'message': _stripMarkdownFences(response).trim(),
          'shouldSave': false,
        };
      }

      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) {
        return {
          'type': 'chat',
          'message': decoded['message']?.toString() ??
              _fallbackChat()['message'],
          'shouldSave': false,
        };
      }
    } catch (_) {
      await _recordModelFailure();
      return _fallbackChat();
    }

    return _fallbackChat();
  }

  Future<Map<String, dynamic>> _processGeneralQuestion(String question) async {
    if (_status != GemmaStatus.ready || _model == null) {
      return {
        'type': 'chat',
        'message': 'The AI model is not ready yet for general questions.',
        'shouldSave': false,
      };
    }

    final prompt = 'Answer this question briefly and helpfully: $question';

    try {
      final session = await _model!.createSession(temperature: 0.3, topK: 32);
      await session.addQueryChunk(Message(text: prompt, isUser: true));
      final response = await session.getResponse().timeout(
        const Duration(seconds: 45),
      );

      final reply = _stripMarkdownFences(response).trim();
      if (reply.isEmpty) {
        await _recordModelFailure();
        return {
          'type': 'chat',
          'message': 'I could not generate an answer for that question.',
          'shouldSave': false,
        };
      }

      _recordModelSuccess();
      return {
        'type': 'chat',
        'message': reply,
        'shouldSave': false,
      };
    } catch (_) {
      await _recordModelFailure();
      return {
        'type': 'chat',
        'message': 'I could not answer that question right now.',
        'shouldSave': false,
      };
    }
  }

  Map<String, dynamic>? _handleLocally(
    String message,
    List<Reminder> reminders,
  ) {
    if (_isDirectScheduleQuestion(message)) {
      return _buildScheduleSummary(message, reminders);
    }

    if (_isScheduleQuery(message)) {
      return _buildScheduleSummary(message, reminders);
    }

    if (_isUpdateIntent(message)) {
      final updates = _parseUpdates(message, reminders);
      if (updates.isNotEmpty) {
        final count = updates.length;
        return {
          'type': 'update',
          'message': count == 1
              ? 'I updated that schedule.'
              : 'I updated $count schedules.',
          'updates': updates,
          'shouldSave': true,
        };
      }

      return {
        'type': 'chat',
        'message':
            'I could not match that schedule to update. Mention the existing title and the new date or time, for example: move dentist appointment to tomorrow 4pm.',
        'shouldSave': false,
      };
    }

    if (_isCreateIntent(message)) {
      final remindersToCreate = _parseCreations(message);
      if (remindersToCreate.isNotEmpty) {
        final count = remindersToCreate.length;
        return {
          'type': 'reminders',
          'message': count == 1
              ? 'I added that schedule.'
              : 'I added $count schedules.',
          'reminders': remindersToCreate,
          'shouldSave': true,
        };
      }

      return {
        'type': 'chat',
        'message':
            'I need a task title plus a date or time. Example: add team meeting tomorrow 3pm and buy groceries Friday 6pm.',
        'shouldSave': false,
      };
    }

    return null;
  }

  bool _isCreateIntent(String text) {
    final lower = text.toLowerCase();
    const keywords = [
      'add ',
      'create ',
      'set ',
      'schedule ',
      'remind me',
      'make a reminder',
      'new reminder',
    ];
    if (keywords.any(lower.contains)) {
      return true;
    }

    final hasDate = RegExp(
      r'\b\d{1,2}(?:st|nd|rd|th)?\s+'
      r'(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec|'
      r'january|february|march|april|june|july|august|september|october|november|december)\b',
      caseSensitive: false,
    ).hasMatch(text);
    final hasTime = _hasLikelyClockTime(text);
    final asksQuestion = lower.contains('?') ||
        lower.startsWith('what ') ||
        lower.startsWith('when ') ||
        lower.startsWith('can you ') ||
        lower.contains('do i have') ||
        lower.contains('check if') ||
        lower.contains('check whether') ||
        lower.contains('any schedule') ||
        lower.contains('have any') ||
        lower.contains('have schedule') ||
        lower.startsWith('do i ') ||
        lower.startsWith('did i ') ||
        lower.startsWith('is there ') ||
        lower.startsWith('are there ') ||
        lower.startsWith('check if ') ||
        lower.startsWith('check whether ') ||
        lower.startsWith('am i ');

    return hasDate && hasTime && !asksQuestion;
  }

  String? _extractGeneralQuestion(String text) {
    final match = RegExp(r'^\s*q\/\s*(.+)$', caseSensitive: false).firstMatch(text);
    final question = match?.group(1)?.trim();
    if (question == null || question.isEmpty) {
      return null;
    }
    return question;
  }

  bool _isUpdateIntent(String text) {
    final lower = text.toLowerCase();
    const keywords = [
      'move ',
      'reschedule ',
      'change ',
      'update ',
      'edit ',
      'postpone ',
      'rename ',
    ];
    return keywords.any(lower.contains);
  }

  bool _isScheduleQuery(String text) {
    if (_isDirectScheduleQuestion(text)) {
      return true;
    }

    if (_isCreateIntent(text) || _isUpdateIntent(text)) {
      return false;
    }

    final lower = text.toLowerCase();
    final parsed = _parser.parse(text);
    final asksToday = lower.contains('today');
    final asksTomorrow = lower.contains('tomorrow');
    const queryKeywords = [
      'how many',
      'what do i have',
      'what do i have on',
      'what is on my schedule',
      'what do i have for',
      'what is scheduled',
      'do i have anything',
      'do i have any',
      'any other',
      'anything else',
      'show me',
      'schedule',
      'reminder',
      'reminders',
      'task',
      'tasks',
      'calendar',
      'free time',
      'busy',
      'available',
    ];
    return asksToday ||
        asksTomorrow ||
        parsed.didParseDate ||
        queryKeywords.any(lower.contains);
  }

  bool _isDirectScheduleQuestion(String text) {
    final lower = text.toLowerCase().trim();
    const questionPatterns = [
      'do i have',
      'did i have',
      'check if i have',
      'check whether i have',
      'check if',
      'check whether',
      'any schedule',
      'have any',
      'have schedule',
      'what do i have',
      'what is on my schedule',
      'what is scheduled',
      'show me',
      'am i free',
      'am i busy',
      'is there any',
      'are there any',
      'how many',
      'anything else',
      'any other',
    ];
    return questionPatterns.any(lower.contains);
  }

  bool _hasLikelyClockTime(String text) {
    if (RegExp(r'\b\d{1,2}\s+hours?\b', caseSensitive: false).hasMatch(text)) {
      return false;
    }

    if (RegExp(
      r'\b\d{1,2}(?:[:.]\d{2})\s*(?:am|pm)?\b|\b\d{1,2}\s*(?:am|pm)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return true;
    }

    return RegExp(r'\bat\s+\d{1,2}\b', caseSensitive: false).hasMatch(text);
  }

  bool _shouldUseModel(String text) {
    final lower = text.toLowerCase();
    const conversationalKeywords = [
      'why',
      'how',
      'help',
      'conflict',
      'available',
      'free time',
      'busy',
      'today',
      'tomorrow',
      'schedule',
      'reminder',
      'calendar',
      'task',
      'tasks',
      'change',
      'update',
      'move',
      'reschedule',
      'when',
      'what time',
      'what do i have',
      'how many',
      'anything else',
      'any other',
    ];
    return conversationalKeywords.any(lower.contains);
  }

  Map<String, dynamic> _buildScheduleSummary(
    String message,
    List<Reminder> reminders,
  ) {
    final lower = message.toLowerCase();
    final now = DateTime.now();
    final parsed = _parser.parse(message);
    final targetDate = lower.contains('tomorrow')
        ? now.add(const Duration(days: 1))
        : parsed.didParseDate
            ? parsed.dateTime
            : now;
    final label = lower.contains('today')
        ? 'today'
        : lower.contains('tomorrow')
            ? 'tomorrow'
            : AppDateUtils.formatHeaderDate(targetDate);
    final start = AppDateUtils.startOfDay(targetDate);
    final items = reminders
        .where((reminder) =>
            !reminder.isCompleted &&
            AppDateUtils.isSameDay(reminder.dateTime, start))
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    if (items.isEmpty) {
      return {
        'type': 'chat',
        'message': 'You have no schedules for $label.',
        'shouldSave': false,
      };
    }

    final lines = items
        .map((item) => '${AppDateUtils.formatTime(item.dateTime)} - ${item.title}')
        .join('\n');

    return {
      'type': 'chat',
      'message': 'Here is your schedule for $label:\n$lines',
      'shouldSave': false,
    };
  }

  List<Map<String, dynamic>> _parseCreations(String message) {
    final segments = _splitIntoSegments(_stripCreatePrefix(message));
    final results = <Map<String, dynamic>>[];

    for (final segment in segments) {
      final normalizedSegment = segment.trim();
      if (normalizedSegment.isEmpty) {
        continue;
      }

      final parsed = _parser.parse(normalizedSegment);
      var title = _extractCreationTitle(normalizedSegment, parsed.title);
      if (title.isEmpty || (!parsed.didParseDate && !parsed.didParseTime)) {
        continue;
      }

      results.add({
        'title': title,
        'date_time': parsed.dateTime.toIso8601String(),
        'priority': 'medium',
      });
    }

    return results;
  }

  List<Map<String, dynamic>> _parseUpdates(
    String message,
    List<Reminder> reminders,
  ) {
    final segments = _splitIntoSegments(message);
    final results = <Map<String, dynamic>>[];

    for (final rawSegment in segments) {
      final segment = rawSegment.trim();
      if (segment.isEmpty) {
        continue;
      }

      final update = _parseSingleUpdate(segment, reminders);
      if (update != null) {
        results.add(update);
      }
    }

    return results;
  }

  Map<String, dynamic>? _parseSingleUpdate(
    String segment,
    List<Reminder> reminders,
  ) {
    final command = segment.replaceFirst(
      RegExp(
        r'^(?:please\s+)?(?:move|reschedule|change|update|edit|postpone|rename)\s+',
        caseSensitive: false,
      ),
      '',
    ).trim();
    final separator = RegExp(r'\s+(?:to|for)\s+', caseSensitive: false)
        .firstMatch(command);
    if (separator == null) {
      return null;
    }

    final referencePhrase =
        command.substring(0, separator.start).replaceFirst(
              RegExp(r'^(?:the\s+)', caseSensitive: false),
              '',
            ).trim();
    final schedulePhrase = command.substring(separator.end).trim();
    if (referencePhrase.isEmpty || schedulePhrase.isEmpty) {
      return null;
    }

    final existing = _findReminderByReference(referencePhrase, reminders);
    if (existing == null) {
      return null;
    }

    final parsed = _parser.parse(schedulePhrase);
    final hasNewDateOrTime = parsed.didParseDate || parsed.didParseTime;
    if (!hasNewDateOrTime) {
      return null;
    }

    final newDateTime = DateTime(
      parsed.dateTime.year,
      parsed.dateTime.month,
      parsed.dateTime.day,
      parsed.dateTime.hour,
      parsed.dateTime.minute,
    );

    return {
      'id': existing.id,
      'title': existing.title,
      'date_time': newDateTime.toIso8601String(),
      'priority': existing.priority,
    };
  }

  Reminder? _findReminderByReference(String reference, List<Reminder> reminders) {
    final trimmed = reference.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final globallyOrdered = reminders.toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final ordinalIndex = _extractRequestedIndex(trimmed);
    if (ordinalIndex != null &&
        RegExp(r'^(?:#)?\d+$').hasMatch(trimmed) &&
        ordinalIndex > 0 &&
        ordinalIndex <= globallyOrdered.length) {
      return globallyOrdered[ordinalIndex - 1];
    }

    final cleanedReference = trimmed
        .replaceAll(RegExp(r'#\d+\b'), '')
        .replaceAll(
          RegExp(r'\b(?:item|number|no\.?)\s+\d+\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\b\d+(?:st|nd|rd|th)\s+(?:one|item|reminder)\b', caseSensitive: false),
          '',
        )
        .trim();

    final parsedReference = _parser.parse(cleanedReference);
    final referenceTitle = _normalizeTitle(parsedReference.title);
    final hasReferenceDateOrTime =
        parsedReference.didParseDate || parsedReference.didParseTime;

    final candidates = reminders
        .where(
          (item) =>
              referenceTitle.isEmpty ||
              item.title.toLowerCase() == referenceTitle.toLowerCase() ||
              item.title.toLowerCase().contains(referenceTitle.toLowerCase()),
        )
        .toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    if (candidates.isEmpty) {
      if (ordinalIndex != null &&
          ordinalIndex > 0 &&
          ordinalIndex <= globallyOrdered.length) {
        return globallyOrdered[ordinalIndex - 1];
      }
      return null;
    }

    if (hasReferenceDateOrTime) {
      final matchedByDateTime = candidates.where((item) {
        final sameDate = !parsedReference.didParseDate ||
            AppDateUtils.isSameDay(item.dateTime, parsedReference.dateTime);
        final sameTime = !parsedReference.didParseTime ||
            (item.dateTime.hour == parsedReference.dateTime.hour &&
                item.dateTime.minute == parsedReference.dateTime.minute);
        return sameDate && sameTime;
      }).toList();

      if (matchedByDateTime.isNotEmpty) {
        if (ordinalIndex != null &&
            ordinalIndex > 0 &&
            ordinalIndex <= matchedByDateTime.length) {
          return matchedByDateTime[ordinalIndex - 1];
        }
        return matchedByDateTime.first;
      }
    }

    if (ordinalIndex != null && ordinalIndex > 0 && ordinalIndex <= candidates.length) {
      return candidates[ordinalIndex - 1];
    }

    return candidates.first;
  }

  int? _extractRequestedIndex(String text) {
    final hashMatch = RegExp(r'#(\d+)\b').firstMatch(text);
    if (hashMatch != null) {
      return int.tryParse(hashMatch.group(1) ?? '');
    }

    final labeledMatch = RegExp(
      r'\b(?:item|number|no\.?)\s+(\d+)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (labeledMatch != null) {
      return int.tryParse(labeledMatch.group(1) ?? '');
    }

    final ordinalMatch = RegExp(
      r'\b(\d+)(?:st|nd|rd|th)\s+(?:one|item|reminder)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (ordinalMatch != null) {
      return int.tryParse(ordinalMatch.group(1) ?? '');
    }

    final plainMatch = RegExp(r'^(?:#)?(\d+)$').firstMatch(text.trim());
    if (plainMatch != null) {
      return int.tryParse(plainMatch.group(1) ?? '');
    }

    return null;
  }

  List<String> _splitIntoSegments(String text) {
    return text
        .split(RegExp(r'\s*(?:,|\band\b|\bthen\b)\s*', caseSensitive: false))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
  }

  String _stripCreatePrefix(String text) {
    return text.replaceFirst(
      RegExp(
        r'^(?:please\s+)?(?:add|create|set|schedule|remind me(?: to)?)\s+(?:a\s+)?(?:new\s+)?(?:reminder|task|schedule)?\s*',
        caseSensitive: false,
      ),
      '',
    ).trim();
  }

  String _normalizeTitle(String title) {
    return title
        .replaceAll(
          RegExp(r'^(?:i have to|i need to|to)\s+', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'^(?:so\s+)?(?:i\s+need\s+you\s+to\s+)?(?:please\s+)?(?:add|create|set|schedule|remind me(?: to)?)\s+',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'^(?:a|an|the)\s+schedule\s+', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\s+at\s*$', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'^(?:a|an|the)\s+', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'\b\d{1,2}(?:st|nd|rd|th)?\s+'
            r'(?:january|february|march|april|may|june|july|august|september|october|november|december|'
            r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(r'\b(?:today|tomorrow|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\b\d{1,2}(?:[:.]\d{2})?\s*(?:am|pm)?\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\bat\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _extractCreationTitle(String originalSegment, String parsedTitle) {
    final parenthetical = RegExp(r'\(([^()]+)\)').firstMatch(originalSegment);
    if (parenthetical != null) {
      return _normalizeTitle(parenthetical.group(1) ?? '');
    }

    return _normalizeTitle(parsedTitle);
  }

  String _buildChatPrompt({
    required String userMessage,
    required List<Reminder> reminders,
    required List<Map<String, String>> recentHistory,
    required bool isRetry,
  }) {
    final historyText = recentHistory.isEmpty
        ? 'No recent conversation.'
        : recentHistory.map((item) => '${item['role']}: ${item['text']}').join('\n');
    final reminderText = reminders.isEmpty
        ? 'No reminders saved.'
        : reminders
            .map(
              (item) =>
                  '- ${item.title} at ${item.dateTime.toIso8601String()}',
            )
            .join('\n');
    final retryLine =
        isRetry ? 'Return exactly one JSON object.\n' : '';

    return '''$retryLine
You are a local AI scheduling assistant inside a reminder app.
Only help with schedules, reminders, dates, times, conflicts, and availability.
If the user asks for unrelated general knowledge or chit-chat, reply briefly that you only handle scheduling tasks.
Never invent reminders, counts, dates, or schedule changes. If the available reminders or history are insufficient, ask a short clarifying question.
Do not claim that you created, updated, or deleted anything in chat. The app handles those actions separately.

Recent conversation:
$historyText

Current reminders:
$reminderText

User:
$userMessage

Return exactly one JSON object:
{"type":"chat","message":"<your reply>"}
''';
  }

  Map<String, dynamic> _fallbackChat() {
    return {
      'type': 'chat',
      'message':
          'I can help with schedules and reminders. Ask me to add something, move it, or check what you have planned.',
      'shouldSave': false,
    };
  }

  Map<String, dynamic> _nonSchedulingReply({String suffix = ''}) {
    return {
      'type': 'chat',
      'message': 'I only handle scheduling and reminders here.$suffix',
      'shouldSave': false,
    };
  }

  void _recordModelSuccess() {
    _consecutiveModelFailures = 0;
  }

  Future<void> _recordModelFailure() async {
    _consecutiveModelFailures++;
    if (_consecutiveModelFailures < 2) {
      return;
    }

    _consecutiveModelFailures = 0;
    await unloadModel();
    await loadModel();
  }

  void _updateStatus(GemmaStatus newStatus) {
    _status = newStatus;
    _statusController.add(_status);
  }

  bool _looksLikeJson(String text) {
    final trimmed = text.trim();
    return trimmed.startsWith('{') && trimmed.endsWith('}');
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) {
      return text.trim();
    }
    return text.substring(start, end + 1);
  }

  String _stripMarkdownFences(String text) {
    return text
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
        .replaceAll(RegExp(r'```$', multiLine: true), '');
  }
}
