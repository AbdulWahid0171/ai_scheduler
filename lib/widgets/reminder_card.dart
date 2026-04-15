import 'package:flutter/material.dart';

import '../models/reminder.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';

class ReminderCard extends StatelessWidget {
  const ReminderCard({
    super.key,
    required this.reminder,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.indexLabel,
    this.selectionMode = false,
    this.selected = false,
    this.onSelectToggle,
  });

  final Reminder reminder;
  final ValueChanged<bool> onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final String? indexLabel;
  final bool selectionMode;
  final bool selected;
  final ValueChanged<bool>? onSelectToggle;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: selectionMode && selected ? AppColors.accent : Colors.white10,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        onTap: selectionMode ? () => onSelectToggle?.call(!selected) : null,
        leading: Checkbox(
          value: selectionMode ? selected : reminder.isCompleted,
          activeColor: selectionMode
              ? AppColors.accent
              : ReminderPriority.colorOf(reminder.priority),
          onChanged: selectionMode
              ? (value) => onSelectToggle?.call(value ?? false)
              : (value) => onToggle(value ?? false),
        ),
        title: Text(
          indexLabel == null ? reminder.title : '$indexLabel ${reminder.title}',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            decoration:
                reminder.isCompleted && !selectionMode
                    ? TextDecoration.lineThrough
                    : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: ReminderPriority.colorOf(reminder.priority),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${AppDateUtils.formatShortDate(reminder.dateTime)} | ${AppDateUtils.formatTime(reminder.dateTime)}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            if ((reminder.description ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                reminder.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (selectionMode) {
      return content;
    }

    return Dismissible(
      key: ValueKey(reminder.id ?? reminder.createdAt.toIso8601String()),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: _swipeBackground(
          icon: Icons.edit,
          label: 'Edit',
          alignment: Alignment.centerLeft,
          color: AppColors.secondary,
        ),
      ),
      secondaryBackground: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: _swipeBackground(
          icon: Icons.delete_outline,
          label: 'Delete',
          alignment: Alignment.centerRight,
          color: AppColors.danger,
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onEdit();
          return false;
        } else if (direction == DismissDirection.endToStart) {
          onDelete();
          return false;
        }
        return false;
      },
      child: content,
    );
  }

  Widget _swipeBackground({
    required IconData icon,
    required String label,
    required Alignment alignment,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: alignment,
      child: Row(
        mainAxisAlignment: alignment == Alignment.centerLeft
            ? MainAxisAlignment.start
            : MainAxisAlignment.end,
        children: [
          if (alignment == Alignment.centerLeft) ...[
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ] else ...[
            Text(label, style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 8),
            Icon(icon, color: Colors.white),
          ],
        ],
      ),
    );
  }
}
