import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/reminder.dart';
import '../services/api_inference_service.dart';
import '../services/gemma_service.dart';
import '../state/app_state.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';
import 'settings_screen.dart';

class ApiChatScreen extends StatefulWidget {
  const ApiChatScreen({super.key});

  @override
  State<ApiChatScreen> createState() => _ApiChatScreenState();
}

class _ApiChatScreenState extends State<ApiChatScreen> {
  static const int _maxContextMessages = 14;

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  List<Map<String, dynamic>>? _pendingImport;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    final history = await context.read<AppState>().getChatHistory(room: 'api');
    if (!mounted) {
      return;
    }
    setState(() {
      _messages
        ..clear()
        ..addAll(history);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _clearChat() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear API Chat?'),
        content: const Text('This resets the API chat context and history.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }
    if (!mounted) {
      return;
    }

    final appState = context.read<AppState>();
    await appState.clearChatHistory(room: 'api');
    if (!mounted) {
      return;
    }
    setState(_messages.clear);
    _pendingImport = null;
  }

  Future<void> _sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final appState = context.read<AppState>();
    if (_pendingImport != null && _isConfirmImportCommand(trimmed)) {
      await _confirmPendingImport(appState, trimmed);
      return;
    }
    if (_pendingImport != null && _isCancelImportCommand(trimmed)) {
      await _cancelPendingImport(appState, trimmed);
      return;
    }
    if (_messages.length >= _maxContextMessages) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'API chat context is full. Clear the API chat to refresh it.',
          ),
        ),
      );
      return;
    }

    final userMsg = ChatMessage(
      text: trimmed,
      isUser: true,
      timestamp: DateTime.now(),
      room: 'api',
    );

    setState(() {
      _messages.add(userMsg);
      _isProcessing = true;
    });
    _controller.clear();
    _scrollToBottom();
    await appState.saveChatMessage(userMsg);

    try {
      final history = _messages.length > 1
          ? _messages.reversed
              .skip(1)
              .take(6)
              .toList()
              .reversed
              .map((m) => {
                    'role': m.isUser ? 'user' : 'assistant',
                    'text': m.text,
                  })
              .toList()
          : <Map<String, String>>[];

      final localResult = GemmaService.instance.processLocalRulesOnly(
        trimmed,
        contextReminders: appState.reminders,
        history: history,
      );

      final responseMap = localResult ??
          await ApiInferenceService.instance.processMessage(
            message: trimmed,
            history: history,
            reminders: appState.reminders,
          );

      await _applyResponse(appState, responseMap);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isProcessing = false);
      final errorMsg = ChatMessage(
        text: 'API chat ran into an error.',
        isUser: false,
        timestamp: DateTime.now(),
        room: 'api',
      );
      setState(() => _messages.add(errorMsg));
      await appState.saveChatMessage(errorMsg);
      _scrollToBottom();
    }
  }

  KeyEventResult _handleComposerKey(KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    _sendMessage(_controller.text);
    return KeyEventResult.handled;
  }

  Future<void> _applyResponse(
    AppState appState,
    Map<String, dynamic> responseMap,
  ) async {
    final aiText = responseMap['message'] as String? ?? '';
    final shouldSave = responseMap['shouldSave'] == true;
    String? metadata;
    final warnings = <String>[];
    final simulatedReminders = List<Reminder>.from(appState.reminders);

    if (responseMap['type'] == 'bulk_preview' && responseMap['reminders'] != null) {
      final previewData = (responseMap['reminders'] as List<dynamic>)
          .whereType<Map>()
          .map((item) => item.map((key, value) => MapEntry('$key', value)))
          .toList();
      _pendingImport = previewData;
      metadata = jsonEncode(
        previewData.map((item) => {'type': 'preview', ...item}).toList(),
      );
    }

    if (shouldSave) {
      final processedActions = <Map<String, dynamic>>[];

      if (responseMap['reminders'] != null) {
        final reminderData = responseMap['reminders'] as List<dynamic>;
        for (final res in reminderData) {
          final dateTime =
              DateTime.tryParse(res['date_time']?.toString() ?? '') ??
                  DateTime.now();
          _checkConflicts(
            dateTime,
            res['title']?.toString(),
            warnings,
            simulatedReminders,
          );
          final reminder = Reminder(
            title: res['title']?.toString() ?? 'Untitled',
            dateTime: dateTime,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            priority: res['priority']?.toString() ?? 'medium',
          );
          await appState.saveReminder(reminder);
          simulatedReminders.add(reminder);
          processedActions.add({'type': 'create', ...res});
        }
      }

      if (responseMap['updates'] != null) {
        final updateData = responseMap['updates'] as List<dynamic>;
        for (final update in updateData) {
          final id = update['id'] is int
              ? update['id'] as int
              : int.tryParse(update['id']?.toString() ?? '');
          if (id == null) {
            continue;
          }
          final existing =
              appState.reminders.where((r) => r.id == id).firstOrNull;
          if (existing == null) {
            continue;
          }
          final newDateTime =
              DateTime.tryParse(update['date_time']?.toString() ?? '') ??
                  existing.dateTime;
          _checkConflicts(
            newDateTime,
            update['title']?.toString() ?? existing.title,
            warnings,
            simulatedReminders,
            excludeId: id,
          );
          final updated = existing.copyWith(
            title: update['title']?.toString(),
            dateTime: newDateTime,
            priority: update['priority']?.toString(),
            updatedAt: DateTime.now(),
          );
          await appState.saveReminder(updated);
          final simulatedIndex =
              simulatedReminders.indexWhere((r) => r.id == id);
          if (simulatedIndex != -1) {
            simulatedReminders[simulatedIndex] = updated;
          }
          processedActions.add({'type': 'update', ...update});
        }
      }

      if (processedActions.isNotEmpty) {
        metadata = jsonEncode(processedActions);
      }
    }

    final aiMsg = ChatMessage(
      text: warnings.isEmpty ? aiText : '${warnings.join('\n')}\n\n$aiText',
      isUser: false,
      timestamp: DateTime.now(),
      metadata: metadata,
      room: 'api',
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _messages.add(aiMsg);
      _isProcessing = false;
    });
    await appState.saveChatMessage(aiMsg);
    _scrollToBottom();
  }

  void _checkConflicts(
    DateTime dateTime,
    String? title,
    List<String> warnings,
    List<Reminder> reminders, {
    int? excludeId,
  }) {
    final conflicts = reminders.where(
      (r) =>
          r.id != excludeId &&
          r.dateTime.isAfter(dateTime.subtract(const Duration(minutes: 30))) &&
          r.dateTime.isBefore(dateTime.add(const Duration(minutes: 30))) &&
          !r.isCompleted,
    );
    if (conflicts.isNotEmpty) {
      final conflict = conflicts.first;
      warnings.add(
        "Warning: '$title' conflicts with '${conflict.title}' at ${AppDateUtils.formatTime(conflict.dateTime)}.",
      );
    }
  }

  bool _isConfirmImportCommand(String text) {
    final lower = text.toLowerCase().trim();
    return lower == 'confirm import' ||
        lower == 'confirm' ||
        lower == 'create all' ||
        lower == 'save import';
  }

  bool _isCancelImportCommand(String text) {
    final lower = text.toLowerCase().trim();
    return lower == 'cancel import' || lower == 'cancel' || lower == 'discard import';
  }

  Future<void> _confirmPendingImport(AppState appState, String text) async {
    final preview = _pendingImport;
    if (preview == null || preview.isEmpty) {
      return;
    }

    final userMsg = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      room: 'api',
    );
    setState(() {
      _messages.add(userMsg);
      _isProcessing = true;
    });
    _controller.clear();
    _scrollToBottom();
    await appState.saveChatMessage(userMsg);

    final importPlan = _buildImportPlan(preview, appState.reminders);
    final reminders = importPlan.$1;
    final duplicateCount = importPlan.$2;
    final conflictCount = importPlan.$3;
    for (final reminder in reminders) {
      await appState.saveReminder(reminder);
    }

    final aiMsg = ChatMessage(
      text: _buildImportResultMessage(
        reminders.length,
        duplicateCount,
        conflictCount,
      ),
      isUser: false,
      timestamp: DateTime.now(),
      metadata: jsonEncode(
        reminders
            .map(
              (item) => {
                'type': 'create',
                'title': item.title,
                'date_time': item.dateTime.toIso8601String(),
                'priority': item.priority,
              },
            )
            .toList(),
      ),
      room: 'api',
    );
    if (!mounted) return;
    setState(() {
      _pendingImport = null;
      _messages.add(aiMsg);
      _isProcessing = false;
    });
    await appState.saveChatMessage(aiMsg);
    _scrollToBottom();
  }

  Future<void> _cancelPendingImport(AppState appState, String text) async {
    final userMsg = ChatMessage(
      text: text,
      isUser: true,
      timestamp: DateTime.now(),
      room: 'api',
    );
    setState(() {
      _messages.add(userMsg);
      _isProcessing = false;
      _pendingImport = null;
    });
    _controller.clear();
    _scrollToBottom();
    await appState.saveChatMessage(userMsg);

    final aiMsg = ChatMessage(
      text: 'I discarded that bulk import preview.',
      isUser: false,
      timestamp: DateTime.now(),
      room: 'api',
    );
    if (!mounted) return;
    setState(() => _messages.add(aiMsg));
    await appState.saveChatMessage(aiMsg);
    _scrollToBottom();
  }

  (List<Reminder>, int, int) _buildImportPlan(
    List<Map<String, dynamic>> preview,
    List<Reminder> existingReminders,
  ) {
    final seenKeys = <String>{};
    final existingKeys = existingReminders
        .map((item) => _importKey(item.title, item.dateTime))
        .toSet();
    final accepted = <Reminder>[];
    final reminders = <Reminder>[];
    var duplicateCount = 0;
    var conflictCount = 0;

    for (final res in preview) {
      final title = res['title']?.toString() ?? 'Untitled';
      final dateTime =
          DateTime.tryParse(res['date_time']?.toString() ?? '') ?? DateTime.now();
      final key = _importKey(title, dateTime);
      if (seenKeys.contains(key) || existingKeys.contains(key)) {
        duplicateCount++;
        continue;
      }
      final hasConflict = existingReminders.any(
            (item) =>
                !item.isCompleted &&
                _isImportConflict(dateTime, item.dateTime),
          ) ||
          accepted.any((item) => _isImportConflict(dateTime, item.dateTime));
      if (hasConflict) {
        conflictCount++;
        continue;
      }
      seenKeys.add(key);
      final reminder = Reminder(
        title: title,
        dateTime: dateTime,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        priority: res['priority']?.toString() ?? 'medium',
      );
      reminders.add(reminder);
      accepted.add(reminder);
    }

    return (reminders, duplicateCount, conflictCount);
  }

  String _importKey(String title, DateTime dateTime) {
    return '${title.trim().toLowerCase()}|${dateTime.toIso8601String()}';
  }

  bool _isImportConflict(DateTime a, DateTime b) {
    return a.isAfter(b.subtract(const Duration(minutes: 30))) &&
        a.isBefore(b.add(const Duration(minutes: 30)));
  }

  String _buildImportResultMessage(
    int importedCount,
    int duplicateCount,
    int conflictCount,
  ) {
    final importedText = importedCount == 1
        ? 'I imported 1 reminder.'
        : 'I imported $importedCount reminders.';
    final notes = <String>[];
    if (duplicateCount > 0) {
      notes.add(
        'Skipped $duplicateCount duplicate reminder${duplicateCount == 1 ? '' : 's'}.',
      );
    }
    if (conflictCount > 0) {
      notes.add(
        'Blocked $conflictCount conflicting reminder${conflictCount == 1 ? '' : 's'}.',
      );
    }
    if (notes.isEmpty) {
      return importedText;
    }
    return '$importedText ${notes.join(' ')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = ApiInferenceService.instance.settings;
    final providerLabel =
        settings.provider == ApiProvider.gemini ? 'Gemini' : 'OpenRouter';
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('API Chat'),
        backgroundColor: AppColors.surface,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: AppColors.textPrimary),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _clearChat,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: Text(
              'Provider: $providerLabel. API chat keeps a short rolling context for smoother use.',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: _messages.isEmpty ? _buildEmptyState() : _buildMessageList(),
          ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(color: AppColors.accent),
            ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_outlined, size: 60, color: AppColors.accent),
            const SizedBox(height: 16),
            const Text(
              'API Chat',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Separate room for Gemini or OpenRouter. Reminder actions still stay local.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _exampleChip('What do I have next Friday?'),
                _exampleChip('Schedule one named random for tomorrow 8am'),
                _exampleChip('Move football matches to Sunday 6pm'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _exampleChip(String text) {
    return ActionChip(
      label: Text(text),
      onPressed: () => _sendMessage(text),
      backgroundColor: AppColors.surface,
      labelStyle: const TextStyle(color: AppColors.accent),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            decoration: BoxDecoration(
              color: isUser ? AppColors.accent : AppColors.card,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 0),
                bottomRight: Radius.circular(isUser ? 0 : 16),
              ),
            ),
            child: SelectionArea(
              child: SelectableText(
                msg.text,
                style: TextStyle(
                  color: isUser ? Colors.black : AppColors.textPrimary,
                ),
              ),
            ),
          ),
          if (msg.metadata != null) _buildSummaryCard(msg.metadata!),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String metadata) {
    final data = jsonDecode(metadata) as List<dynamic>;
    return Container(
      width: 250,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.event_available, size: 16, color: AppColors.accent),
              SizedBox(width: 8),
              Text('Schedule Changes', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const Divider(),
          ...data.map((item) {
            final type = item['type']?.toString() ?? 'create';
            final dateTime = DateTime.parse(item['date_time'].toString());
            final label = switch (type) {
              'update' => '[Updated]',
              'preview' => '[Preview]',
              _ => '[Created]',
            };
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '$label ${item['title']} (${AppDateUtils.formatShortDate(dateTime)}, ${AppDateUtils.formatTime(dateTime)})',
                style: TextStyle(
                  fontSize: 12,
                  color: type == 'update' || type == 'preview'
                      ? AppColors.accent
                      : AppColors.textPrimary,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 4),
              child: Text(
                'Short rolling context only. Clear chat when it fills up.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Focus(
                    onKeyEvent: (_, event) => _handleComposerKey(event),
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Message API Chat...',
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: AppColors.accent),
                  onPressed: () => _sendMessage(_controller.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
