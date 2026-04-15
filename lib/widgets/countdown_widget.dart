import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';

class CountdownWidget extends StatelessWidget {
  const CountdownWidget({
    super.key,
    required this.reminder,
    this.onTap,
  });

  final Reminder? reminder;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final title = reminder == null
        ? 'No upcoming reminders'
        : AppDateUtils.isToday(reminder!.dateTime)
            ? reminder!.title
            : '${AppDateUtils.daysUntil(reminder!.dateTime)} days until ${reminder!.title}';
    final subtitle = reminder == null
        ? 'Everything is clear for now.'
        : AppDateUtils.isToday(reminder!.dateTime)
            ? '${AppDateUtils.formatTime(reminder!.dateTime)} - TODAY'
            : AppDateUtils.formatShortDate(reminder!.dateTime);
    final icon = reminder == null
        ? Icons.task_alt
        : AppDateUtils.isToday(reminder!.dateTime)
            ? Icons.push_pin
            : Icons.hourglass_top;

    return InkWell(
      onTap: reminder == null ? null : onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.accent.withAlpha(30),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: AppColors.accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
