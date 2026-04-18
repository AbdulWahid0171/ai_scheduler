import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/persistent_countdown.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../services/persistent_countdown_service.dart';
import '../utils/constants.dart';

class MultiCountdownWidget extends StatefulWidget {
  const MultiCountdownWidget({super.key});

  @override
  State<MultiCountdownWidget> createState() => _MultiCountdownWidgetState();
}

class _MultiCountdownWidgetState extends State<MultiCountdownWidget> {
  static const String _storageKey = 'multi_countdown_entries_v1';
  static const List<_PresetDuration> _presets = [
    _PresetDuration(label: '1 min', duration: Duration(minutes: 1)),
    _PresetDuration(label: '5 min', duration: Duration(minutes: 5)),
    _PresetDuration(label: '10 min', duration: Duration(minutes: 10)),
    _PresetDuration(label: '25 min', duration: Duration(minutes: 25)),
  ];

  Timer? _timer;
  int _nextCountdownId = 1;
  final List<_CountdownEntry> _countdowns = [];
  List<PersistentCountdown> _persistentCountdowns = const [];

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
    unawaited(_loadData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleNextTick() {
    _timer?.cancel();
    final now = DateTime.now();
    final delay = Duration(milliseconds: 1000 - now.millisecond);
    _timer = Timer(delay, () {
      if (!mounted) {
        return;
      }
      _pruneFinishedQuickCountdowns();
      unawaited(_refreshPersistentCountdowns());
      setState(() {});
      _scheduleNextTick();
    });
  }

  Future<void> _loadData() async {
    await _loadQuickCountdowns();
    final persistent = await PersistentCountdownService.instance.loadAll();
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentCountdowns = persistent;
    });
  }

  Future<void> _loadQuickCountdowns() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey) ?? const <String>[];
    final loaded = stored
        .map(_CountdownEntry.tryParse)
        .whereType<_CountdownEntry>()
        .where((entry) => entry.target.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.target.compareTo(b.target));

    if (!mounted) {
      return;
    }

    setState(() {
      _countdowns
        ..clear()
        ..addAll(loaded);
      _nextCountdownId = loaded.isEmpty
          ? 1
          : loaded.map((entry) => entry.id).reduce((a, b) => a > b ? a : b) + 1;
    });

    await _persistQuickCountdowns();
    await _syncQuickHomeWidget();
  }

  Future<void> _refreshPersistentCountdowns() async {
    final synced = await PersistentCountdownService.instance.sync();
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentCountdowns = synced;
    });
  }

  Future<void> _persistQuickCountdowns() async {
    final prefs = await SharedPreferences.getInstance();
    final active = _countdowns.where((entry) => entry.target.isAfter(DateTime.now())).toList()
      ..sort((a, b) => a.target.compareTo(b.target));
    await prefs.setStringList(
      _storageKey,
      active.map((entry) => entry.serialize()).toList(),
    );
  }

  void _pruneFinishedQuickCountdowns() {
    final before = _countdowns.length;
    _countdowns.removeWhere((entry) => entry.isFinished);
    if (_countdowns.length == before) {
      return;
    }
    unawaited(_persistQuickCountdowns());
    unawaited(_syncQuickHomeWidget());
  }

  @override
  Widget build(BuildContext context) {
    final quickItems = _countdowns.toList()
      ..sort((a, b) => a.target.compareTo(b.target));
    final activeQuick = quickItems.where((item) => !item.isFinished).toList();
    final topThree = activeQuick.take(3).toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Timer Studio',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Run quick timers or saved countdown alarms with a real ringing finish screen.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionHeader(
            title: 'Quick timers',
            actionLabel: 'New',
            onPressed: _showAddCountdownDialog,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets
                .map(
                  (preset) => ActionChip(
                    backgroundColor: AppColors.surface,
                    label: Text(
                      preset.label,
                      style: const TextStyle(color: AppColors.textPrimary),
                    ),
                    onPressed: () => _addQuickCountdown(
                      label: preset.label,
                      duration: preset.duration,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (quickItems.isEmpty)
            _buildEmptyState(
              'No quick countdowns yet. Use a preset or tap New to create one.',
            )
          else ...[
            _buildCountdownShowcase(topThree),
            if (activeQuick.length > 3) ...[
              const SizedBox(height: 14),
              Text(
                '+${activeQuick.length - 3} more timer${activeQuick.length - 3 == 1 ? '' : 's'} running',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
          const SizedBox(height: 22),
          _buildSectionHeader(
            title: 'Persistent countdown alarms',
            actionLabel: 'New Alarm',
            onPressed: _showAddPersistentCountdownDialog,
          ),
          const SizedBox(height: 10),
          const Text(
            'Saved countdowns stay in the app, can be started or paused, and ring when they hit zero.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 14),
          if (_persistentCountdowns.isEmpty)
            _buildEmptyState(
              'No persistent countdown alarms yet. Create one to keep it around with controls.',
            )
          else
            ..._persistentCountdowns.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _buildPersistentCountdownCard(item),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String actionLabel,
    required VoidCallback onPressed,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: onPressed,
          child: Text(
            actionLabel,
            style: const TextStyle(
              color: AppColors.accent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCountdownShowcase(List<_CountdownEntry> topThree) {
    return Column(
      children: topThree
          .asMap()
          .entries
          .map(
            (entry) => Padding(
              padding: EdgeInsets.only(bottom: entry.key == topThree.length - 1 ? 0 : 10),
              child: _buildQuickCountdownCard(entry.value, featured: entry.key == 0),
            ),
          )
          .toList(),
    );
  }

  Widget _buildEmptyState(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildQuickCountdownCard(_CountdownEntry countdown, {required bool featured}) {
    final display = countdown.remaining;
    final total = countdown.totalDuration.inMilliseconds <= 0
        ? 1.0
        : countdown.totalDuration.inMilliseconds.toDouble();
    final progress = (display.inMilliseconds / total).clamp(0.0, 1.0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(featured ? 18 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(featured ? 22 : 18),
        gradient: featured
            ? const LinearGradient(
                colors: [AppColors.primary, AppColors.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: featured ? null : AppColors.surface,
        border: Border.all(color: featured ? Colors.white12 : Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: featured ? 52 : 44,
            height: featured ? 52 : 44,
            decoration: BoxDecoration(
              color: featured ? Colors.white24 : AppColors.accent.withAlpha(20),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.timer_outlined,
              color: featured ? AppColors.textPrimary : AppColors.accent,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  countdown.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: featured ? 16 : 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatDuration(display),
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: featured ? 32 : 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: featured ? 7 : 6,
                    backgroundColor: featured ? Colors.white24 : Colors.white10,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removeQuickCountdown(countdown.id),
            icon: Icon(
              Icons.close,
              color: featured ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersistentCountdownCard(PersistentCountdown countdown) {
    final now = DateTime.now();
    final remaining = countdown.remainingAt(now);
    final progressBase = countdown.totalDurationMillis <= 0
        ? 1.0
        : countdown.remainingMillisAt(now) / countdown.totalDurationMillis;
    final progress = progressBase.clamp(0.0, 1.0);
    final statusLabel = switch (countdown.status) {
      PersistentCountdownStatus.running => 'Running',
      PersistentCountdownStatus.paused => 'Paused',
      PersistentCountdownStatus.idle => 'Ready',
      PersistentCountdownStatus.finished => 'Finished',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  countdown.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _statusColor(countdown.status).withAlpha(30),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: _statusColor(countdown.status),
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _formatDuration(remaining),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 26,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white10,
              valueColor: AlwaysStoppedAnimation<Color>(_statusColor(countdown.status)),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (countdown.status == PersistentCountdownStatus.running)
                _buildPersistentActionChip(
                  label: 'Pause',
                  icon: Icons.pause_rounded,
                  onPressed: () => _pausePersistentCountdown(countdown.id),
                )
              else if (countdown.status != PersistentCountdownStatus.finished)
                _buildPersistentActionChip(
                  label: 'Start',
                  icon: Icons.play_arrow_rounded,
                  onPressed: () => _startPersistentCountdown(countdown.id),
                ),
              _buildPersistentActionChip(
                label: 'Reset',
                icon: Icons.replay_rounded,
                onPressed: () => _resetPersistentCountdown(countdown.id),
              ),
              _buildPersistentActionChip(
                label: 'Delete',
                icon: Icons.delete_outline,
                onPressed: () => _deletePersistentCountdown(countdown.id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPersistentActionChip({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return ActionChip(
      backgroundColor: AppColors.card,
      side: const BorderSide(color: Colors.white10),
      avatar: Icon(icon, size: 18, color: AppColors.textPrimary),
      label: Text(
        label,
        style: const TextStyle(color: AppColors.textPrimary),
      ),
      onPressed: onPressed,
    );
  }

  Color _statusColor(PersistentCountdownStatus status) {
    switch (status) {
      case PersistentCountdownStatus.running:
        return AppColors.accent;
      case PersistentCountdownStatus.paused:
        return Colors.orangeAccent;
      case PersistentCountdownStatus.idle:
        return AppColors.textSecondary;
      case PersistentCountdownStatus.finished:
        return AppColors.success;
    }
  }

  Future<void> _showAddCountdownDialog() async {
    final result = await _showCountdownDraftDialog(title: 'Add Countdown');
    if (!mounted || result == null || result.duration.inSeconds <= 0) {
      return;
    }
    await _addQuickCountdown(label: result.label, duration: result.duration);
  }

  Future<void> _showAddPersistentCountdownDialog() async {
    final result = await _showCountdownDraftDialog(title: 'New Persistent Countdown');
    if (!mounted || result == null || result.duration.inSeconds <= 0) {
      return;
    }
    final updated = await PersistentCountdownService.instance.create(
      label: result.label,
      duration: result.duration,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentCountdowns = updated;
    });
  }

  Future<_CountdownDraft?> _showCountdownDraftDialog({required String title}) async {
    final labelController = TextEditingController();
    var selectedHours = 0;
    var selectedMinutes = 5;
    var selectedSeconds = 0;

    return showDialog<_CountdownDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: labelController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'Workout, study, tea',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 180,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildWheelPicker(
                        label: 'Hours',
                        selectedValue: selectedHours,
                        maxValue: 23,
                        onChanged: (value) => setDialogState(() => selectedHours = value),
                      ),
                    ),
                    Expanded(
                      child: _buildWheelPicker(
                        label: 'Minutes',
                        selectedValue: selectedMinutes,
                        maxValue: 59,
                        onChanged: (value) => setDialogState(() => selectedMinutes = value),
                      ),
                    ),
                    Expanded(
                      child: _buildWheelPicker(
                        label: 'Seconds',
                        selectedValue: selectedSeconds,
                        maxValue: 59,
                        onChanged: (value) => setDialogState(() => selectedSeconds = value),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  _CountdownDraft(
                    label: labelController.text.trim().isEmpty
                        ? 'Timer $_nextCountdownId'
                        : labelController.text.trim(),
                    duration: Duration(
                      hours: selectedHours,
                      minutes: selectedMinutes,
                      seconds: selectedSeconds,
                    ),
                  ),
                );
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWheelPicker({
    required String label,
    required int selectedValue,
    required int maxValue,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: CupertinoPicker(
            itemExtent: 36,
            scrollController: FixedExtentScrollController(initialItem: selectedValue),
            onSelectedItemChanged: onChanged,
            children: List.generate(
              maxValue + 1,
              (index) => Center(
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _removeQuickCountdown(int id) async {
    final entry = _countdowns.where((item) => item.id == id).firstOrNull;
    if (entry != null) {
      await NotificationService.instance.cancelReminder(entry.notificationId);
    }
    setState(() {
      _countdowns.removeWhere((entry) => entry.id == id);
    });
    await _persistQuickCountdowns();
    await _syncQuickHomeWidget();
  }

  Future<void> _addQuickCountdown({
    required String label,
    required Duration duration,
  }) async {
    final id = _nextCountdownId++;
    final now = DateTime.now();
    final entry = _CountdownEntry(
      id: id,
      notificationId: 900000 + id,
      label: label,
      target: now.add(duration),
      totalDuration: duration,
    );
    setState(() {
      _countdowns.add(entry);
    });
    await NotificationService.instance.scheduleCountdownAlarm(
      id: entry.notificationId,
      title: entry.label,
      dateTime: entry.target,
    );
    await _persistQuickCountdowns();
    await _syncQuickHomeWidget();
  }

  Future<void> _startPersistentCountdown(int id) async {
    final updated = await PersistentCountdownService.instance.start(id);
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentCountdowns = updated;
    });
  }

  Future<void> _pausePersistentCountdown(int id) async {
    final updated = await PersistentCountdownService.instance.pause(id);
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentCountdowns = updated;
    });
  }

  Future<void> _resetPersistentCountdown(int id) async {
    final updated = await PersistentCountdownService.instance.reset(id);
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentCountdowns = updated;
    });
  }

  Future<void> _deletePersistentCountdown(int id) async {
    final updated = await PersistentCountdownService.instance.delete(id);
    if (!mounted) {
      return;
    }
    setState(() {
      _persistentCountdowns = updated;
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _syncQuickHomeWidget() async {
    final next = _countdowns.where((entry) => entry.target.isAfter(DateTime.now())).toList()
      ..sort((a, b) => a.target.compareTo(b.target));

    if (next.isEmpty) {
      await HomeWidgetService.clearCountdownWidget();
      return;
    }

    await HomeWidgetService.updateCountdownWidget(
      entries: next
          .take(3)
          .map(
            (entry) => CountdownWidgetEntry(
              title: entry.label,
              targetMillis: entry.target.millisecondsSinceEpoch,
            ),
          )
          .toList(),
    );
  }
}

class _CountdownEntry {
  _CountdownEntry({
    required this.id,
    required this.notificationId,
    required this.label,
    required this.target,
    required this.totalDuration,
  });

  final int id;
  final int notificationId;
  final String label;
  final DateTime target;
  final Duration totalDuration;

  bool get isFinished => !target.isAfter(DateTime.now());

  Duration get remaining {
    final diff = target.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String serialize() {
    return [
      id.toString(),
      notificationId.toString(),
      label.replaceAll('|', '/'),
      target.millisecondsSinceEpoch.toString(),
      totalDuration.inMilliseconds.toString(),
    ].join('|');
  }

  static _CountdownEntry? tryParse(String raw) {
    final parts = raw.split('|');
    if (parts.length != 5) {
      return null;
    }

    final id = int.tryParse(parts[0]);
    final notificationId = int.tryParse(parts[1]);
    final targetMillis = int.tryParse(parts[3]);
    final totalDurationMillis = int.tryParse(parts[4]);
    if (id == null ||
        notificationId == null ||
        targetMillis == null ||
        totalDurationMillis == null) {
      return null;
    }

    return _CountdownEntry(
      id: id,
      notificationId: notificationId,
      label: parts[2],
      target: DateTime.fromMillisecondsSinceEpoch(targetMillis),
      totalDuration: Duration(milliseconds: totalDurationMillis),
    );
  }
}

class _CountdownDraft {
  const _CountdownDraft({
    required this.label,
    required this.duration,
  });

  final String label;
  final Duration duration;
}

class _PresetDuration {
  const _PresetDuration({
    required this.label,
    required this.duration,
  });

  final String label;
  final Duration duration;
}
