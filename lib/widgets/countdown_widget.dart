import 'dart:async';

import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';

class CountdownWidget extends StatefulWidget {
  const CountdownWidget({
    super.key,
    required this.reminder,
    this.onTap,
    this.onCreateCountdown,
  });

  final Reminder? reminder;
  final VoidCallback? onTap;
  final VoidCallback? onCreateCountdown;

  @override
  State<CountdownWidget> createState() => _CountdownWidgetState();
}

class _CountdownWidgetState extends State<CountdownWidget> {
  Timer? _timer;
  DateTime _now = DateTime.now();

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
      setState(() => _now = DateTime.now());
      _scheduleNextTick();
    });
  }

  @override
  Widget build(BuildContext context) {
    final reminder = widget.reminder;
    final remaining = reminder == null ? Duration.zero : reminder.dateTime.difference(_now);
    final hasActiveCountdown = reminder != null && !remaining.isNegative;
    final accent = hasActiveCountdown ? AppColors.accent : AppColors.textSecondary;

    return InkWell(
      onTap: hasActiveCountdown ? widget.onTap : widget.onCreateCountdown,
      borderRadius: BorderRadius.circular(24),
      child: Container(
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
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(30),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    hasActiveCountdown ? Icons.hourglass_bottom : Icons.task_alt,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasActiveCountdown ? 'Day Countdown' : 'No upcoming reminders',
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        hasActiveCountdown
                            ? reminder.title
                            : 'Everything is clear for now.',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (hasActiveCountdown) ...[
              Text(
                _formatRemaining(remaining),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Counting down to ${AppDateUtils.formatHeaderDate(reminder.dateTime)} at ${AppDateUtils.formatTime(reminder.dateTime)}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ] else
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add a reminder with a future date and time to start the backward countdown here.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: widget.onCreateCountdown,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.add_alarm),
                    label: const Text('Set Day Countdown'),
                  ),
                ],
              ),
            if (hasActiveCountdown) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: widget.onTap,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Edit Countdown'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.onCreateCountdown,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('New Countdown'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatRemaining(Duration duration) {
    final safe = duration.isNegative ? Duration.zero : duration;
    final days = safe.inDays;
    final hours = safe.inHours.remainder(24);
    final minutes = safe.inMinutes.remainder(60);
    final seconds = safe.inSeconds.remainder(60);
    return '${days.toString().padLeft(2, '0')}d '
        '${hours.toString().padLeft(2, '0')}h '
        '${minutes.toString().padLeft(2, '0')}m '
        '${seconds.toString().padLeft(2, '0')}s';
  }
}
