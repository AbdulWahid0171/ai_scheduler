import 'dart:async';
import 'dart:collection';
import 'package:path/path.dart' as p;
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/local_ai_model.dart';
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
  static const String _selectedModelPrefKey = 'selected_local_ai_model';
  static const List<LocalAiModel> _availableModels = [
    LocalAiModel(
      id: 'gemma_1b',
      label: 'Gemma 1B',
      assetPath: 'assets/models/gemma3-1b-it-int4.task',
      modelType: ModelType.gemmaIt,
      note: 'Fastest and most stable fallback.',
    ),
    LocalAiModel(
      id: 'gemma_2b',
      label: 'Gemma 2B',
      assetPath: 'assets/models/Gemma2-2B-IT_multi-prefill-seq_q8_ekv1280.task',
      modelType: ModelType.gemmaIt,
      note: 'Heavier, but usually stronger on scheduling phrasing.',
    ),
    LocalAiModel(
      id: 'deepseek_1_5b',
      label: 'DeepSeek 1.5B',
      assetPath:
          'assets/models/DeepSeek-R1-Distill-Qwen-1.5B_multi-prefill-seq_q8_ekv1280.task',
      modelType: ModelType.deepSeek,
      note: 'Reasoning-focused model. Heavier than Gemma 1B.',
    ),
  ];

  final FlutterGemmaPlugin _gemma = FlutterGemmaPlugin.instance;
  final NaturalLanguageParser _parser = NaturalLanguageParser();
  final StreamController<GemmaStatus> _statusController =
      StreamController<GemmaStatus>.broadcast();
  final StreamController<LocalAiModel> _modelController =
      StreamController<LocalAiModel>.broadcast();

  InferenceModel? _model;
  GemmaStatus _status = GemmaStatus.uninitialized;
  int _consecutiveModelFailures = 0;
  List<LocalAiModel> _runtimeAvailableModels = List<LocalAiModel>.from(
    _availableModels,
  );
  LocalAiModel _selectedModel = _availableModels.first;
  String? _lastErrorMessage;
  String? _loadedModelId;

  GemmaStatus get status => _status;
  Stream<GemmaStatus> get statusStream => _statusController.stream;
  Stream<LocalAiModel> get selectedModelStream => _modelController.stream;
  List<LocalAiModel> get availableModels =>
      UnmodifiableListView(_runtimeAvailableModels);
  LocalAiModel get selectedModel => _selectedModel;
  String? get lastErrorMessage => _lastErrorMessage;

  Future<void> initialize() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final bundledAssets = manifest.listAssets().toSet();
    _runtimeAvailableModels = _availableModels
        .where((item) => bundledAssets.contains(item.assetPath))
        .toList();

    final prefs = await SharedPreferences.getInstance();
    if (_runtimeAvailableModels.isEmpty) {
      _lastErrorMessage = 'No supported local model was bundled in this build.';
      _selectedModel = _availableModels.first;
      _modelController.add(_selectedModel);
      _updateStatus(GemmaStatus.unavailable);
      return;
    }

    final savedId = prefs.getString(_selectedModelPrefKey);
    final selected =
        _runtimeAvailableModels.where((item) => item.id == savedId);
    if (selected.isNotEmpty) {
      _selectedModel = selected.first;
    } else {
      _selectedModel = _runtimeAvailableModels.first;
      await prefs.setString(_selectedModelPrefKey, _selectedModel.id);
    }
    _modelController.add(_selectedModel);
  }

  Future<void> loadModel({bool forceReload = false}) async {
    if (!forceReload &&
        (_status == GemmaStatus.loading ||
            (_status == GemmaStatus.ready &&
                _model != null &&
                _loadedModelId == _selectedModel.id))) {
      return;
    }

    _lastErrorMessage = null;
    _updateStatus(GemmaStatus.loading);
    try {
      await FlutterGemma.installModel(
        modelType: _selectedModel.modelType,
        fileType: ModelFileType.task,
      )
          .fromAsset(_selectedModel.assetPath)
          .install();
      await _deleteUnselectedInstalledModels();

      _model = await _gemma.createModel(
        modelType: _selectedModel.modelType,
        fileType: ModelFileType.task,
        maxTokens: 1024,
      );
      _loadedModelId = _selectedModel.id;

      _updateStatus(_model != null ? GemmaStatus.ready : GemmaStatus.unavailable);
    } catch (error) {
      _model = null;
      _loadedModelId = null;
      _lastErrorMessage = 'Failed to load ${_selectedModel.label}.';
      _updateStatus(GemmaStatus.error);
    }
  }

  Future<void> unloadModel({bool updateStatus = true}) async {
    try {
      await _model?.close();
    } catch (_) {}
    _model = null;
    _loadedModelId = null;
    if (updateStatus) {
      _updateStatus(GemmaStatus.uninitialized);
    }
  }

  Future<void> selectModel(String modelId) async {
    final nextModel = _runtimeAvailableModels.where((item) => item.id == modelId);
    if (nextModel.isEmpty) {
      return;
    }

    final selected = nextModel.first;
    if (selected.id == _selectedModel.id) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await unloadModel(updateStatus: false);
    _selectedModel = selected;
    _lastErrorMessage = null;
    _modelController.add(_selectedModel);
    await prefs.setString(_selectedModelPrefKey, _selectedModel.id);
    await loadModel(forceReload: true);
  }

  Future<void> _deleteUnselectedInstalledModels() async {
    final manager = _gemma.modelManager;
    final selectedSpec = _modelSpecFor(_selectedModel);

    for (final model in _runtimeAvailableModels) {
      if (model.id == _selectedModel.id) {
        continue;
      }

      final spec = _modelSpecFor(model);
      try {
        final isInstalled = await manager.isModelInstalled(spec);
        if (isInstalled) {
          await manager.deleteModel(spec);
        }
      } catch (_) {}
    }

    manager.setActiveModel(selectedSpec);
  }

  InferenceModelSpec _modelSpecFor(LocalAiModel model) {
    return InferenceModelSpec.fromLegacyUrl(
      name: p.basenameWithoutExtension(model.assetPath),
      modelUrl: 'asset://${model.assetPath}',
      replacePolicy: ModelReplacePolicy.keep,
      modelType: model.modelType,
      fileType: ModelFileType.task,
    );
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

    final localResult = _handleLocally(
      trimmed,
      contextReminders,
      recentHistory: history,
    );
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
      final reply = _stripMarkdownFences(response).trim();
      if (reply.isNotEmpty) {
        return {
          'type': 'chat',
          'message': reply,
          'shouldSave': false,
        };
      }
    } catch (_) {
      await _recordModelFailure();
      return _fallbackChat();
    }

    return _fallbackChat();
  }

  Map<String, dynamic>? processLocalRulesOnly(
    String message, {
    List<Reminder> contextReminders = const [],
    List<Map<String, String>> history = const [],
  }) {
    return _handleLocally(
      message.trim(),
      contextReminders,
      recentHistory: history,
    );
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
    List<Reminder> reminders, {
    List<Map<String, String>> recentHistory = const [],
  }) {
    if (_isDirectScheduleQuestion(message)) {
      return _buildScheduleSummary(message, reminders);
    }

    if (_isScheduleQuery(message)) {
      return _buildScheduleSummary(message, reminders);
    }

    if (_isUpdateIntent(message)) {
      final updates = _parseUpdates(
        message,
        reminders,
        recentHistory: recentHistory,
      );
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
      if (_looksLikeBulkAcademicInput(message)) {
        final academicBulk = _parseAcademicBulkCreations(message);
        if (academicBulk.isNotEmpty) {
          final count = academicBulk.length;
          return {
            'type': 'bulk_preview',
            'message': count == 1
                ? 'I parsed 1 reminder. Say "confirm import" to save it or "cancel import" to discard it.'
                : 'I parsed $count reminders. Say "confirm import" to save them or "cancel import" to discard them.',
            'reminders': academicBulk,
            'shouldSave': false,
          };
        }

        return {
          'type': 'chat',
          'message':
              'I detected a bulk academic calendar import, but I could not parse it safely. Reformat it into one event per line or a cleaner title-date list so I do not create wrong reminders.',
          'shouldSave': false,
        };
      }

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

  bool _looksLikeBulkAcademicInput(String message) {
    final monthMatches = RegExp(
      r'\b(?:january|february|march|april|may|june|july|august|september|october|november|december|'
      r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b',
      caseSensitive: false,
    ).allMatches(message).length;
    final yearMatches = RegExp(r'\b20\d{2}\b').allMatches(message).length;
    return monthMatches >= 2 && yearMatches >= 1;
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
      'when is',
      'when\'s',
      'what time is',
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
    final eventLookups = _extractEventLookups(message, reminders);
    if (eventLookups.isNotEmpty) {
      if (eventLookups.length == 1) {
        final eventLookup = eventLookups.first;
        return {
          'type': 'chat',
          'message':
              '${eventLookup.title} is on ${AppDateUtils.formatHeaderDate(eventLookup.dateTime)} at ${AppDateUtils.formatTime(eventLookup.dateTime)}.',
          'shouldSave': false,
        };
      }

      final lines = eventLookups
          .map(
            (item) =>
                '${AppDateUtils.formatHeaderDate(item.dateTime)} ${AppDateUtils.formatTime(item.dateTime)} - ${item.title}',
          )
          .join('\n');
      return {
        'type': 'chat',
        'message': 'I found multiple matching events:\n$lines',
        'shouldSave': false,
      };
    }

    final monthQuery = _extractMonthQueryDate(message);
    if (monthQuery != null) {
      var resolvedMonth = monthQuery;
      var monthStart = DateTime(resolvedMonth.year, resolvedMonth.month);
      var monthEnd = DateTime(resolvedMonth.year, resolvedMonth.month + 1);
      var items = reminders
          .where((reminder) =>
              !reminder.isCompleted &&
              !reminder.dateTime.isBefore(monthStart) &&
              reminder.dateTime.isBefore(monthEnd))
          .toList()
        ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

      if (items.isEmpty && !_hasExplicitYearInMonthQuery(message)) {
        final fallback = reminders
            .where((reminder) =>
                !reminder.isCompleted &&
                reminder.dateTime.month == monthQuery.month &&
                !reminder.dateTime.isBefore(monthStart))
            .toList()
          ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
        if (fallback.isNotEmpty) {
          resolvedMonth = DateTime(
            fallback.first.dateTime.year,
            fallback.first.dateTime.month,
          );
          monthStart = DateTime(resolvedMonth.year, resolvedMonth.month);
          monthEnd = DateTime(resolvedMonth.year, resolvedMonth.month + 1);
          items = reminders
              .where((reminder) =>
                  !reminder.isCompleted &&
                  !reminder.dateTime.isBefore(monthStart) &&
                  reminder.dateTime.isBefore(monthEnd))
              .toList()
            ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
        }
      }

      final label = AppDateUtils.formatMonthYear(monthStart);

      if (items.isEmpty) {
        return {
          'type': 'chat',
          'message': 'You have no schedules in $label.',
          'shouldSave': false,
        };
      }

      final lines = items
          .map(
            (item) =>
                '${AppDateUtils.formatShortDate(item.dateTime)} ${AppDateUtils.formatTime(item.dateTime)} - ${item.title}',
          )
          .join('\n');

      return {
        'type': 'chat',
        'message': 'Here is your schedule for $label:\n$lines',
        'shouldSave': false,
      };
    }

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

  DateTime? _extractMonthQueryDate(String text) {
    final match = RegExp(
      r'\b(?:in\s+)?'
      r'(january|february|march|april|may|june|july|august|september|october|november|december|'
      r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)'
      r'(?:\s+(\d{4}))?\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final month = _monthNumberFromText(match.group(1));
    if (month == null) {
      return null;
    }

    final now = DateTime.now();
    final explicitYear = int.tryParse(match.group(2) ?? '');
    final year = explicitYear ??
        (month < now.month ? now.year + 1 : now.year);
    return DateTime(year, month);
  }

  bool _hasExplicitYearInMonthQuery(String text) {
    return RegExp(
      r'\b(?:in\s+)?'
      r'(?:january|february|march|april|may|june|july|august|september|october|november|december|'
      r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)'
      r'\s+\d{4}\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  int? _monthNumberFromText(String? value) {
    switch (value?.toLowerCase()) {
      case 'january':
      case 'jan':
        return 1;
      case 'february':
      case 'feb':
        return 2;
      case 'march':
      case 'mar':
        return 3;
      case 'april':
      case 'apr':
        return 4;
      case 'may':
        return 5;
      case 'june':
      case 'jun':
        return 6;
      case 'july':
      case 'jul':
        return 7;
      case 'august':
      case 'aug':
        return 8;
      case 'september':
      case 'sep':
      case 'sept':
        return 9;
      case 'october':
      case 'oct':
        return 10;
      case 'november':
      case 'nov':
        return 11;
      case 'december':
      case 'dec':
        return 12;
      default:
        return null;
    }
  }

  List<Map<String, dynamic>> _parseCreations(String message) {
    final academicBulk = _parseAcademicBulkCreations(message);
    if (academicBulk.isNotEmpty) {
      return academicBulk;
    }

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

  List<Map<String, dynamic>> _parseAcademicBulkCreations(String message) {
    final offset = _extractReminderOffset(message);
    final reminderTime = _extractReminderTime(message);
    final normalized = message.replaceAll('\r', ' ').replaceAll('\n', ' ');
    final results = <Map<String, dynamic>>[];
    final datePattern = RegExp(
      r'(January|February|March|April|May|June|July|August|September|October|November|December|'
      r'Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)'
      r'\s+(\d{1,2}),\s*(\d{4})'
      r'(?:\s*\(?((?:\d{1,2}:\d{2}\s*(?:AM|PM))|(?:All day))\)?)?',
      caseSensitive: false,
    );

    final matches = datePattern.allMatches(normalized).toList();
    if (matches.length < 2) {
      return const [];
    }

    var previousEnd = 0;
    for (final match in matches) {
      final rawTitle = normalized.substring(previousEnd, match.start);
      final item = _academicReminderFromMatch(
        rawTitle: rawTitle,
        monthText: match.group(1),
        dayText: match.group(2),
        yearText: match.group(3),
        eventTimeText: match.group(4),
        offset: offset,
        reminderTime: reminderTime,
      );
      if (item != null) {
        results.add(item);
      }
      previousEnd = match.end;
    }

    return results.length >= 2 ? results : const [];
  }

  Map<String, dynamic>? _academicReminderFromMatch({
    required String rawTitle,
    required String? monthText,
    required String? dayText,
    required String? yearText,
    required String? eventTimeText,
    required Duration offset,
    required DateTime? reminderTime,
  }) {
    final month = _monthNumberFromText(monthText);
    final day = int.tryParse(dayText ?? '');
    final year = int.tryParse(yearText ?? '');
    if (rawTitle.trim().isEmpty || month == null || day == null || year == null) {
      return null;
    }

    var eventDateTime = DateTime(year, month, day);
    final parsedEventTime = eventTimeText == null
        ? null
        : eventTimeText.toLowerCase() == 'all day'
            ? DateTime(
                eventDateTime.year,
                eventDateTime.month,
                eventDateTime.day,
                12,
                0,
              )
            : _parseClockText(eventTimeText, baseDate: eventDateTime);
    if (parsedEventTime != null) {
      eventDateTime = parsedEventTime;
    }

    var reminderDateTime = eventDateTime.subtract(offset);
    if (reminderTime != null) {
      reminderDateTime = DateTime(
        reminderDateTime.year,
        reminderDateTime.month,
        reminderDateTime.day,
        reminderTime.hour,
        reminderTime.minute,
      );
    }

    final title = _sanitizeAcademicEventTitle(rawTitle);
    if (title.isEmpty) {
      return null;
    }

    return {
      'title': title,
      'date_time': reminderDateTime.toIso8601String(),
      'priority': 'medium',
    };
  }

  Duration _extractReminderOffset(String message) {
    final dayMatch = RegExp(
      r'(\d+)\s+days?\s+before',
      caseSensitive: false,
    ).firstMatch(message);
    if (dayMatch != null) {
      final days = int.tryParse(dayMatch.group(1) ?? '');
      if (days != null && days >= 0) {
        return Duration(days: days);
      }
    }

    final weekMatch = RegExp(
      r'(\d+)\s+weeks?\s+before',
      caseSensitive: false,
    ).firstMatch(message);
    if (weekMatch != null) {
      final weeks = int.tryParse(weekMatch.group(1) ?? '');
      if (weeks != null && weeks >= 0) {
        return Duration(days: weeks * 7);
      }
    }

    return Duration.zero;
  }

  DateTime? _extractReminderTime(String message) {
    final timeMatches = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
      caseSensitive: false,
    ).allMatches(message).toList();
    if (timeMatches.isEmpty) {
      return null;
    }

    final last = timeMatches.last;
    final raw = last.group(0);
    if (raw == null) {
      return null;
    }

    return _parseClockText(raw, baseDate: DateTime.now());
  }

  DateTime? _parseClockText(String text, {required DateTime baseDate}) {
    final match = RegExp(
      r'^\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*$',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) {
      return null;
    }

    final hourRaw = int.tryParse(match.group(1) ?? '');
    final minute = int.tryParse(match.group(2) ?? '0') ?? 0;
    final meridiem = (match.group(3) ?? '').toLowerCase();
    if (hourRaw == null) {
      return null;
    }

    var hour = hourRaw;
    if (meridiem == 'pm' && hour < 12) {
      hour += 12;
    } else if (meridiem == 'am' && hour == 12) {
      hour = 0;
    }

    return DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      hour,
      minute,
    );
  }

  String _sanitizeAcademicEventTitle(String rawTitle) {
    final cleaned = rawTitle
        .replaceAll(RegExp(r'^(?:create|add|set|schedule)\s+', caseSensitive: false), '')
        .replaceAll(RegExp(r'^(?:reminders?\s+)?', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'\b(?:\d+\s+days?\s+before|\d+\s+weeks?\s+before)\b', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'\b\d{1,2}:\d{2}\s*(?:am|pm)\b', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[,:;.\- ]+$'), '');
    final splitChunks = cleaned
        .split(RegExp(r'(?:\)\s*|[.;]\s+|\n+)'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    return splitChunks.isEmpty ? cleaned : splitChunks.last;
  }

  List<Reminder> _extractEventLookups(String message, List<Reminder> reminders) {
    final match = RegExp(
      r"^\s*(?:when\s+is|what\s+time\s+is|when'?s|when\s+do\s+i\s+have|do\s+i\s+have)\s+(.+?)\??\s*$",
      caseSensitive: false,
    ).firstMatch(message);
    if (match == null) {
      return const [];
    }

    var query = (match.group(1) ?? '').trim().toLowerCase();
    query = query
        .replaceAll(RegExp(r'^(?:the|my)\s+', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'\b(?:event|events|schedule|reminder|task|have)\b', caseSensitive: false),
          '',
        )
        .trim();
    if (query.isEmpty) {
      return const [];
    }

    final active = reminders.where((item) => !item.isCompleted).toList();
    if (active.isEmpty) {
      return const [];
    }

    final queryTokens = _keywordTokens(query);
    final scored = <MapEntry<Reminder, int>>[];
    for (final reminder in active) {
      final title = reminder.title.toLowerCase();
      var score = 0;
      if (title == query) {
        score += 100;
      }
      if (title.contains(query)) {
        score += 50;
      }
      for (final token in queryTokens) {
        if (token.isNotEmpty && title.contains(token)) {
          score += 10;
        }
      }
      if (score > 0) {
        scored.add(MapEntry(reminder, score));
      }
    }

    if (scored.isEmpty) {
      return const [];
    }

    scored.sort((a, b) {
      final scoreCompare = b.value.compareTo(a.value);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      return a.key.dateTime.compareTo(b.key.dateTime);
    });

    final topScore = scored.first.value;
    return scored
        .where((entry) => entry.value == topScore || entry.value >= topScore - 10)
        .map((entry) => entry.key)
        .toList();
  }

  List<Map<String, dynamic>> _parseUpdates(
    String message,
    List<Reminder> reminders, {
    List<Map<String, String>> recentHistory = const [],
  }) {
    final segments = _splitIntoSegments(message);
    final results = <Map<String, dynamic>>[];

    for (final rawSegment in segments) {
      final segment = rawSegment.trim();
      if (segment.isEmpty) {
        continue;
      }

      final updates = _parseSingleUpdate(
        segment,
        reminders,
        recentHistory: recentHistory,
      );
      if (updates.isNotEmpty) {
        results.addAll(updates);
      }
    }

    return results;
  }

  List<Map<String, dynamic>> _parseSingleUpdate(
    String segment,
    List<Reminder> reminders, {
    List<Map<String, String>> recentHistory = const [],
  }) {
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
      return const [];
    }

    final referencePhrase =
        command.substring(0, separator.start).replaceFirst(
              RegExp(r'^(?:the\s+)', caseSensitive: false),
              '',
            ).trim();
    final schedulePhrase = command.substring(separator.end).trim();
    if (referencePhrase.isEmpty || schedulePhrase.isEmpty) {
      return const [];
    }

    final existingMatches = _findRemindersByScopeOrReference(
      referencePhrase,
      reminders,
      recentHistory: recentHistory,
    );
    if (existingMatches.isEmpty) {
      return const [];
    }

    final parsed = _parser.parse(schedulePhrase);
    final monthTarget = _extractMonthQueryDate(schedulePhrase);
    final keepSameTime = RegExp(
      r'\bsame(?:\s+time)?\b',
      caseSensitive: false,
    ).hasMatch(schedulePhrase);
    final hasNewDateOrTime =
        parsed.didParseDate || parsed.didParseTime || monthTarget != null;
    if (!hasNewDateOrTime && !keepSameTime) {
      return const [];
    }

    return existingMatches.map((existing) {
      final targetDate = monthTarget != null && !parsed.didParseDate
          ? _safeDateInMonth(
              existing.dateTime,
              year: monthTarget.year,
              month: monthTarget.month,
            )
          : parsed.dateTime;
      final newDateTime = DateTime(
        (parsed.didParseDate || monthTarget != null)
            ? targetDate.year
            : existing.dateTime.year,
        (parsed.didParseDate || monthTarget != null)
            ? targetDate.month
            : existing.dateTime.month,
        (parsed.didParseDate || monthTarget != null)
            ? targetDate.day
            : existing.dateTime.day,
        parsed.didParseTime ? parsed.dateTime.hour : existing.dateTime.hour,
        parsed.didParseTime
            ? parsed.dateTime.minute
            : existing.dateTime.minute,
      );

      return {
        'id': existing.id,
        'title': existing.title,
        'date_time': newDateTime.toIso8601String(),
        'priority': existing.priority,
      };
    }).toList();
  }

  List<Reminder> _findRemindersByReference(
    String reference,
    List<Reminder> reminders, {
    List<Map<String, String>> recentHistory = const [],
  }) {
    final trimmed = reference.trim();
    if (trimmed.isEmpty) {
      return const [];
    }

    final globallyOrdered = reminders.toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final contextualOrdered = _extractRecentContextReminders(
      recentHistory: recentHistory,
      reminders: reminders,
    );
    final ordinalIndex = _extractRequestedIndex(trimmed);
    if (ordinalIndex != null && ordinalIndex > 0) {
      if (ordinalIndex <= contextualOrdered.length) {
        return [contextualOrdered[ordinalIndex - 1]];
      }
      if (RegExp(r'^(?:#)?\d+$').hasMatch(trimmed) &&
          ordinalIndex <= globallyOrdered.length) {
        return [globallyOrdered[ordinalIndex - 1]];
      }
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
    final lowerCleaned = cleanedReference.toLowerCase();
    final wantsMultiple = _referenceImpliesMultiple(lowerCleaned);

    if (_isPronounReference(lowerCleaned)) {
      if (contextualOrdered.isEmpty) {
        return const [];
      }
      return wantsMultiple
          ? contextualOrdered
          : [contextualOrdered.first];
    }

    final parsedReference = _parser.parse(cleanedReference);
    final normalizedReferenceTitle = _normalizeTitle(parsedReference.title);
    final referenceTitle = _isGenericReferenceTitle(normalizedReferenceTitle)
        ? ''
        : normalizedReferenceTitle;
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

    if (hasReferenceDateOrTime) {
      final dateScope = candidates.isEmpty ? globallyOrdered : candidates;
      final matchedByDateTime = dateScope.where((item) {
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
          return [matchedByDateTime[ordinalIndex - 1]];
        }
        return wantsMultiple ? matchedByDateTime : [matchedByDateTime.first];
      }
    }

    if (candidates.isNotEmpty) {
      if (ordinalIndex != null &&
          ordinalIndex > 0 &&
          ordinalIndex <= candidates.length) {
        return [candidates[ordinalIndex - 1]];
      }
      return wantsMultiple ? candidates : [candidates.first];
    }

    if (contextualOrdered.isNotEmpty) {
      return wantsMultiple ? contextualOrdered : [contextualOrdered.first];
    }

    return const [];
  }

  List<Reminder> _findRemindersByScopeOrReference(
    String reference,
    List<Reminder> reminders, {
    List<Map<String, String>> recentHistory = const [],
  }) {
    final scoped = _findRemindersByScope(reference, reminders);
    if (scoped.isNotEmpty) {
      return scoped;
    }
    return _findRemindersByReference(
      reference,
      reminders,
      recentHistory: recentHistory,
    );
  }

  List<Reminder> _findRemindersByScope(String reference, List<Reminder> reminders) {
    final lower = reference.toLowerCase().trim();
    final active = reminders.where((item) => !item.isCompleted).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (active.isEmpty) {
      return const [];
    }

    final monthQuery = _extractMonthQueryDate(reference);
    if (monthQuery != null) {
      return active
          .where((item) =>
              item.dateTime.year == monthQuery.year &&
              item.dateTime.month == monthQuery.month)
          .toList();
    }

    if (lower.contains('today')) {
      return active
          .where((item) => AppDateUtils.isSameDay(item.dateTime, DateTime.now()))
          .toList();
    }
    if (lower.contains('tomorrow')) {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      return active
          .where((item) => AppDateUtils.isSameDay(item.dateTime, tomorrow))
          .toList();
    }

    final parsed = _parser.parse(reference);
    if (parsed.didParseDate) {
      final sameDay = active
          .where((item) => AppDateUtils.isSameDay(item.dateTime, parsed.dateTime))
          .toList();
      if (sameDay.isNotEmpty) {
        return sameDay;
      }
    }

    const weekdays = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    for (var i = 0; i < weekdays.length; i++) {
      if (lower.contains(weekdays[i])) {
        return active.where((item) => item.dateTime.weekday == i + 1).toList();
      }
    }

    return const [];
  }

  DateTime _safeDateInMonth(
    DateTime original, {
    required int year,
    required int month,
  }) {
    final lastDay = DateTime(year, month + 1, 0).day;
    final safeDay = original.day > lastDay ? lastDay : original.day;
    return DateTime(year, month, safeDay);
  }

  List<Reminder> _extractRecentContextReminders({
    required List<Map<String, String>> recentHistory,
    required List<Reminder> reminders,
  }) {
    final activeReminders = reminders.where((item) => !item.isCompleted).toList();
    for (final item in recentHistory.reversed) {
      final text = (item['text'] ?? '').toLowerCase();
      if (text.isEmpty) {
        continue;
      }

      final matches = activeReminders
          .where((reminder) => text.contains(reminder.title.toLowerCase()))
          .map((reminder) => MapEntry(reminder, text.indexOf(reminder.title.toLowerCase())))
          .where((entry) => entry.value >= 0)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));

      if (matches.isNotEmpty) {
        return matches.map((entry) => entry.key).toList();
      }
    }

    return const [];
  }

  bool _referenceImpliesMultiple(String text) {
    return RegExp(
      r'\b(?:plans|schedules|reminders|tasks|all|them|those)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  bool _isPronounReference(String text) {
    final normalized = text.trim();
    return RegExp(
      r'^(?:that|it|this|those|them|that one|this one|same one)$',
      caseSensitive: false,
    ).hasMatch(normalized);
  }

  bool _isGenericReferenceTitle(String text) {
    if (text.trim().isEmpty) {
      return true;
    }

    return RegExp(
      r'^(?:plan|plans|schedule|schedules|reminder|reminders|task|tasks|that|it|this|those|them|same)$',
      caseSensitive: false,
    ).hasMatch(text.trim());
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
          RegExp(
            r'\b(?:january|february|march|april|may|june|july|august|september|october|november|december|'
            r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\s+'
            r'\d{1,2}(?:st|nd|rd|th)?\b',
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
    final scopedHistory = _selectRelevantHistory(
      recentHistory: recentHistory,
      userMessage: userMessage,
    );
    final scopedReminders = _selectRelevantReminders(
      userMessage: userMessage,
      reminders: reminders,
    );
    final historyText = scopedHistory.isEmpty
        ? 'No relevant recent conversation.'
        : scopedHistory
            .map((item) => '[${item['role']}] ${item['text']}')
            .join('\n');
    final reminderText = scopedReminders.isEmpty
        ? 'No directly relevant saved reminders were found.'
        : scopedReminders
            .map(
              (item) =>
                  '- ${item.title} | ${item.dateTime.toIso8601String()} | ${item.isCompleted ? 'completed' : 'active'}',
            )
            .join('\n');
    final retryLine = isRetry
        ? 'Your previous answer failed. Keep this answer short and plain text.\n\n'
        : '';

    return '''${retryLine}You are a local scheduling assistant inside a reminder app.
You only answer questions about reminders, schedules, dates, times, conflicts, and availability.
The app itself creates, updates, deletes, and looks up reminders. You only help interpret natural language and explain schedule information.

Rules:
- Reply in plain text only.
- Accept messy or natural phrasing and answer based on the available reminders.
- Never invent reminders, dates, counts, or schedule changes.
- If the user asks something unrelated to schedules or reminders, say briefly that you only handle scheduling here.
- If the request is ambiguous, ask one short clarifying question.
- If there is not enough matching schedule data, say that briefly instead of guessing.

Relevant recent conversation:
$historyText

Relevant reminders:
$reminderText

Current user request:
$userMessage
''';
  }

  List<Map<String, String>> _selectRelevantHistory({
    required List<Map<String, String>> recentHistory,
    required String userMessage,
  }) {
    final queryTokens = _keywordTokens(userMessage);
    final selected = recentHistory
        .where((item) {
          final text = item['text']?.trim() ?? '';
          if (text.isEmpty) {
            return false;
          }

          final lower = text.toLowerCase();
          if (_containsScheduleSignal(lower)) {
            return true;
          }

          return queryTokens.any(lower.contains);
        })
        .toList();

    final trimmed = selected.length > 4
        ? selected.sublist(selected.length - 4)
        : selected;
    return trimmed
        .map(
          (item) => {
            'role': item['role'] ?? 'user',
            'text': item['text'] ?? '',
          },
        )
        .toList();
  }

  List<Reminder> _selectRelevantReminders({
    required String userMessage,
    required List<Reminder> reminders,
  }) {
    if (reminders.isEmpty) {
      return const [];
    }

    final lower = userMessage.toLowerCase();
    final tokens = _keywordTokens(userMessage);
    final monthQuery = _extractMonthQueryDate(userMessage);
    final parsed = _parser.parse(userMessage);
    final now = DateTime.now();

    bool matches(Reminder reminder) {
      if (reminder.isCompleted) {
        return false;
      }

      if (monthQuery != null) {
        return reminder.dateTime.year == monthQuery.year &&
            reminder.dateTime.month == monthQuery.month;
      }

      if (lower.contains('today')) {
        return AppDateUtils.isSameDay(reminder.dateTime, now);
      }

      if (lower.contains('tomorrow')) {
        return AppDateUtils.isSameDay(
          reminder.dateTime,
          now.add(const Duration(days: 1)),
        );
      }

      if (parsed.didParseDate &&
          AppDateUtils.isSameDay(reminder.dateTime, parsed.dateTime)) {
        return true;
      }

      final title = reminder.title.toLowerCase();
      return tokens.any(title.contains);
    }

    final scoped = reminders.where(matches).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    if (scoped.isNotEmpty) {
      return scoped.take(8).toList();
    }

    final active = reminders.where((item) => !item.isCompleted).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return active.take(5).toList();
  }

  List<String> _keywordTokens(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((token) => token.length >= 3)
        .where((token) => !_ignoredQueryTokens.contains(token))
        .toSet()
        .toList();
  }

  bool _containsScheduleSignal(String text) {
    return _isScheduleQuery(text) ||
        _isDirectScheduleQuestion(text) ||
        _isCreateIntent(text) ||
        _isUpdateIntent(text) ||
        text.contains('today') ||
        text.contains('tomorrow');
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
    await unloadModel(updateStatus: false);
    await loadModel(forceReload: true);
  }

  void _updateStatus(GemmaStatus newStatus) {
    _status = newStatus;
    _statusController.add(_status);
  }

  String _stripMarkdownFences(String text) {
    return text
        .replaceAll(RegExp(r'^```(?:json)?\s*', multiLine: true), '')
        .replaceAll(RegExp(r'```$', multiLine: true), '');
  }
}

const Set<String> _ignoredQueryTokens = {
  'what',
  'when',
  'where',
  'which',
  'have',
  'with',
  'that',
  'this',
  'there',
  'about',
  'show',
  'tell',
  'need',
  'want',
  'reminder',
  'reminders',
  'schedule',
  'schedules',
  'task',
  'tasks',
  'calendar',
  'plan',
  'plans',
  'please',
  'check',
  'would',
  'could',
  'should',
  'into',
  'from',
};
