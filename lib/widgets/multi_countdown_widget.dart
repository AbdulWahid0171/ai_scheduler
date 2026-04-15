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

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _countdowns.toList()
      ..sort((a, b) => a.target.compareTo(b.target));

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
                  'Countdown Timers',
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
                  'Add Timer',
                  style: TextStyle(color: AppColors.accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Set multiple countdowns for study, cooking, workouts, or anything else.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 16),
          if (items.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Text(
                'No countdowns yet. Tap Add Timer to create one.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...items.map(_buildCountdownTile),
        ],
      ),
    );
  }

  Widget _buildCountdownTile(_CountdownEntry countdown) {
    final remaining = countdown.target.difference(DateTime.now());
    final finished = remaining.isNegative || remaining == Duration.zero;
    final display = finished ? Duration.zero : remaining;

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
              finished ? Icons.notifications_active : Icons.timer_outlined,
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
                  finished ? 'Completed' : _formatDuration(display),
                  style: TextStyle(
                    color: finished ? AppColors.success : AppColors.textSecondary,
                    fontSize: 13,
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

    final id = _nextCountdownId++;
    final entry = _CountdownEntry(
      id: id,
      notificationId: 900000 + id,
      label: result.label,
      target: DateTime.now().add(result.duration),
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
      await HomeWidgetService.updateCountdownWidget(
        title: 'Countdown Timers',
        subtitle: 'No active countdowns',
        targetMillis: 0,
      );
      return;
    }

    final entry = next.first;
    await HomeWidgetService.updateCountdownWidget(
      title: entry.label,
      subtitle: 'Ends soon',
      targetMillis: entry.target.millisecondsSinceEpoch,
    );
  }
}

class _CountdownEntry {
  _CountdownEntry({
    required this.id,
    required this.notificationId,
    required this.label,
    required this.target,
  });

  final int id;
  final int notificationId;
  final String label;
  final DateTime target;
}

class _CountdownDraft {
  const _CountdownDraft({
    required this.label,
    required this.duration,
  });

  final String label;
  final Duration duration;
}
