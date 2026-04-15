import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';

class MultiCountdownWidget extends StatefulWidget {
  const MultiCountdownWidget({super.key});

  @override
  State<MultiCountdownWidget> createState() => _MultiCountdownWidgetState();
}

class _MultiCountdownWidgetState extends State<MultiCountdownWidget> {
  Timer? _timer;
  int _nextCountdownId = 1;
  final List<_CountdownEntry> _countdowns = [];
  static const List<_PresetDuration> _presets = [
    _PresetDuration(label: '1 min', duration: Duration(minutes: 1)),
    _PresetDuration(label: '5 min', duration: Duration(minutes: 5)),
    _PresetDuration(label: '10 min', duration: Duration(minutes: 10)),
    _PresetDuration(label: '25 min', duration: Duration(minutes: 25)),
  ];

  @override
  void initState() {
    super.initState();
    _scheduleNextTick();
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
      setState(() {});
      _scheduleNextTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final items = _countdowns.toList()
      ..sort((a, b) => a.target.compareTo(b.target));
    final active = items.where((item) => !item.isFinished).toList();
    final topThree = active.take(3).toList();

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
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Timer Studio',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _showAddCountdownDialog,
                icon: const Icon(Icons.add, color: AppColors.accent),
                label: const Text(
                  'New',
                  style: TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Run focused timers with a real ringing finish screen.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
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
                    onPressed: () => _addCountdown(
                      label: preset.label,
                      duration: preset.duration,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            _buildEmptyState()
          else ...[
            _buildCountdownShowcase(topThree),
            if (active.length > 3) ...[
              const SizedBox(height: 14),
              Text(
                '+${active.length - 3} more timer${active.length - 3 == 1 ? '' : 's'} running',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (items.any((item) => item.isFinished)) ...[
              const SizedBox(height: 16),
              const Text(
                'Finished',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...items.where((item) => item.isFinished).map(_buildCountdownTile),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildCountdownShowcase(List<_CountdownEntry> topThree) {
    return Column(
      children: topThree
          .asMap()
          .entries
          .map((entry) => Padding(
                padding: EdgeInsets.only(bottom: entry.key == topThree.length - 1 ? 0 : 10),
                child: _buildActiveCountdownCard(entry.value, featured: entry.key == 0),
              ))
          .toList(),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: const Text(
        'No countdowns yet. Use a preset or tap New to create one.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }

  Widget _buildCountdownTile(_CountdownEntry countdown) {
    final finished = countdown.isFinished;
    final display = countdown.remaining;
    final total = countdown.totalDuration.inMilliseconds <= 0
        ? 1.0
        : countdown.totalDuration.inMilliseconds.toDouble();
    final progress = (display.inMilliseconds / total).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: finished ? AppColors.success.withAlpha(110) : Colors.white10,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: finished
                  ? AppColors.success.withAlpha(35)
                  : AppColors.accent.withAlpha(20),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              finished ? Icons.alarm_on : Icons.timer_outlined,
              color: finished ? AppColors.success : AppColors.accent,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  countdown.label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  finished ? 'Finished and ringing' : _formatDuration(display),
                  style: TextStyle(
                    color: finished ? AppColors.success : AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      finished ? AppColors.success : AppColors.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _removeCountdown(countdown.id),
            icon: const Icon(Icons.delete_outline, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveCountdownCard(_CountdownEntry countdown, {required bool featured}) {
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
            onPressed: () => _removeCountdown(countdown.id),
            icon: Icon(
              Icons.close,
              color: featured ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddCountdownDialog() async {
    final labelController = TextEditingController();
    var selectedHours = 0;
    var selectedMinutes = 5;
    var selectedSeconds = 0;

    final result = await showDialog<_CountdownDraft>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Countdown'),
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
                        onChanged: (value) =>
                            setDialogState(() => selectedHours = value),
                      ),
                    ),
                    Expanded(
                      child: _buildWheelPicker(
                        label: 'Minutes',
                        selectedValue: selectedMinutes,
                        maxValue: 59,
                        onChanged: (value) =>
                            setDialogState(() => selectedMinutes = value),
                      ),
                    ),
                    Expanded(
                      child: _buildWheelPicker(
                        label: 'Seconds',
                        selectedValue: selectedSeconds,
                        maxValue: 59,
                        onChanged: (value) =>
                            setDialogState(() => selectedSeconds = value),
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

    if (!mounted || result == null || result.duration.inSeconds <= 0) {
      return;
    }

    await _addCountdown(label: result.label, duration: result.duration);
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
            scrollController: FixedExtentScrollController(
              initialItem: selectedValue,
            ),
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

  Future<void> _removeCountdown(int id) async {
    final entry = _countdowns.where((item) => item.id == id).firstOrNull;
    if (entry != null) {
      await NotificationService.instance.cancelReminder(entry.notificationId);
    }
    setState(() {
      _countdowns.removeWhere((entry) => entry.id == id);
    });
    await _syncHomeWidget();
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _syncHomeWidget() async {
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

  Future<void> _addCountdown({
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
    await _syncHomeWidget();
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
