import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/chat_message.dart';
import '../models/reminder.dart';
import '../services/gemma_service.dart';
import '../state/app_state.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _loadChatHistory();
    GemmaService.instance.loadModel();
  }

  @override
  void dispose() {
    GemmaService.instance.unloadModel();
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadChatHistory() async {
    final history = await context.read<AppState>().getChatHistory();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _messages.addAll(history);
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _clearChat() async {
    final appState = context.read<AppState>();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat?'),
        content: const Text('This will delete all messages in this conversation.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('CLEAR', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await appState.clearChatHistory();
      if (!mounted) return;
      setState(() {
        _messages.clear();
      });
    }
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    final appState = context.read<AppState>();

    final userMsg = ChatMessage(
      text: text.trim(),
      isUser: true,
      timestamp: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isProcessing = true;
    });
    _controller.clear();
    _scrollToBottom();

    await appState.saveChatMessage(userMsg);

    try {
      if (!mounted) return;

      // Assemble history (last 4 messages for context continuity)
      final history = _messages.length > 1 
          ? _messages.reversed.skip(1).take(4).toList().reversed.map((m) => {
              'role': m.isUser ? 'user' : 'model',
              'text': m.text,
            }).toList()
          : <Map<String, String>>[];

      final responseMap = await GemmaService.instance.processMessage(
        text,
        contextReminders: appState.reminders,
        history: history,
      );
      
      final aiText = responseMap['message'] as String? ?? '';
      final bool shouldSave = responseMap['shouldSave'] ?? false;
      
      String? metadata;
      List<String> warnings = [];
      
      if (shouldSave) {
        final List<Map<String, dynamic>> processedActions = [];

        // Handle Creations
        if (responseMap['reminders'] != null) {
          final List<dynamic> reminderData = responseMap['reminders'];
          for (final res in reminderData) {
            final dateTime = DateTime.tryParse(res['date_time'] ?? '') ?? DateTime.now();
            _checkConflicts(dateTime, res['title'], warnings, appState);

            final reminder = Reminder(
              title: res['title'] ?? 'Untitled',
              dateTime: dateTime,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
              priority: res['priority'] ?? 'medium',
            );
            await appState.saveReminder(reminder);
            processedActions.add({'type': 'create', ...res});
          }
        }

        // Handle Updates
        if (responseMap['updates'] != null) {
          final List<dynamic> updateData = responseMap['updates'];
          for (final update in updateData) {
            final int? id = update['id'] is int ? update['id'] : int.tryParse(update['id']?.toString() ?? '');
            if (id == null) continue;

            final existing = appState.reminders.where((r) => r.id == id).firstOrNull;
            if (existing != null) {
              final newDateTime = DateTime.tryParse(update['date_time'] ?? '') ?? existing.dateTime;
              _checkConflicts(newDateTime, update['title'] ?? existing.title, warnings, appState, excludeId: id);

              final updated = existing.copyWith(
                title: update['title'],
                dateTime: newDateTime,
                priority: update['priority'],
                updatedAt: DateTime.now(),
              );
              await appState.saveReminder(updated);
              processedActions.add({'type': 'update', ...update});
            }
          }
        }

        if (processedActions.isNotEmpty) {
          metadata = jsonEncode(processedActions);
        }
      }

      final warningText = warnings.isEmpty ? "" : "${warnings.join("\n")}\n\n";
      final aiMsg = ChatMessage(
        text: "$warningText$aiText",
        isUser: false,
        timestamp: DateTime.now(),
        metadata: metadata,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(aiMsg);
        _isProcessing = false;
      });
      await appState.saveChatMessage(aiMsg);
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      final errorMsg = ChatMessage(
        text: "Sorry, I ran into an error processing that.",
        isUser: false,
        timestamp: DateTime.now(),
      );
      setState(() => _messages.add(errorMsg));
      _scrollToBottom();
    }
  }

  void _checkConflicts(DateTime dateTime, String? title, List<String> warnings, AppState appState, {int? excludeId}) {
    final conflicts = appState.reminders.where((r) => 
      r.id != excludeId &&
      r.dateTime.isAfter(dateTime.subtract(const Duration(minutes: 30))) &&
      r.dateTime.isBefore(dateTime.add(const Duration(minutes: 30))) &&
      !r.isCompleted
    );

    if (conflicts.isNotEmpty) {
      final conflict = conflicts.first;
      final time = "${conflict.dateTime.hour}:${conflict.dateTime.minute.toString().padLeft(2, '0')}";
      warnings.add("Warning: '$title' conflicts with '${conflict.title}' at $time.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI Scheduler'),
        backgroundColor: AppColors.surface,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _clearChat,
          ),
        ],
      ),
      body: StreamBuilder<GemmaStatus>(
        stream: GemmaService.instance.statusStream,
        initialData: GemmaService.instance.status,
        builder: (context, snapshot) {
          final status = snapshot.data ?? GemmaStatus.uninitialized;

          return Column(
            children: [
              if (status != GemmaStatus.ready) _buildStatusBanner(status),
              Expanded(
                child: _messages.isEmpty ? _buildEmptyState() : _buildMessageList(),
              ),
              if (_isProcessing)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: LinearProgressIndicator(color: AppColors.accent),
                ),
              _buildInputBar(true),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatusBanner(GemmaStatus status) {
    final text = switch (status) {
      GemmaStatus.loading => 'AI chat model is loading. Scheduling still works.',
      GemmaStatus.downloading => 'AI chat model is downloading. Scheduling still works.',
      GemmaStatus.unavailable => 'AI chat model is unavailable. Scheduling still works locally.',
      GemmaStatus.uninitialized => 'AI chat model is starting. Scheduling still works.',
      GemmaStatus.error => 'AI chat model hit an error. Scheduling still works locally.',
      _ => '',
    };

    if (text.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.surface,
      child: Text(
        text,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, size: 64, color: AppColors.accent),
                  const SizedBox(height: 16),
                  const Text(
                    'How can I help you today?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Use q/ for general questions.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      _exampleChip("Call Mom at 5pm"),
                      _exampleChip("Grocery shopping Friday at 6pm"),
                      _exampleChip("What do I have tomorrow?"),
                      _exampleChip("Move dentist appointment to Monday 4pm"),
                      _exampleChip("q/What is the capital of Bangladesh?"),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
      itemBuilder: (context, index) {
        final msg = _messages[index];
        return _buildMessageBubble(msg);
      },
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
            child: Text(
              msg.text,
              style: TextStyle(
                color: isUser ? Colors.black : AppColors.textPrimary,
              ),
            ),
          ),
          if (msg.metadata != null) _buildSummaryCard(msg.metadata!),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String metadata) {
    final List<dynamic> data = jsonDecode(metadata);
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
            final isUpdate = item['type'] == 'update';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${isUpdate ? '[Updated]' : '[Created]'} ${item['title']} (${AppDateUtils.formatShortDate(DateTime.parse(item['date_time']))}, ${AppDateUtils.formatTime(DateTime.parse(item['date_time']))})',
                style: TextStyle(fontSize: 12, color: isUpdate ? AppColors.accent : AppColors.textPrimary),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildInputBar(bool isEnabled) {
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
                'Tip: start with q/ for general questions.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    onSubmitted: isEnabled ? _sendMessage : null,
                    enabled: isEnabled,
                    decoration: InputDecoration(
                      hintText: isEnabled
                          ? 'Message AI Scheduler... or use q/...'
                          : 'AI is initializing...',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.send, color: isEnabled ? AppColors.accent : Colors.grey),
                  onPressed: isEnabled ? () => _sendMessage(_controller.text) : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
