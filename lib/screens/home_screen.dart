import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../state/app_state.dart';
import '../utils/constants.dart';
import '../widgets/clock_widget.dart';
import '../widgets/countdown_widget.dart';
import '../widgets/multi_countdown_widget.dart';
import '../widgets/reminder_card.dart';
import 'add_edit_reminder.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: state.refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                children: [
                  const ClockWidget(),
                  const SizedBox(height: 16),
                  CountdownWidget(
                    reminder: state.nextUpcomingReminder,
                    onTap: () {
                      final next = state.nextUpcomingReminder;
                      if (next != null) {
                        AddEditReminderSheet.show(context, reminder: next);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  const MultiCountdownWidget(),
                  const SizedBox(height: 24),
                  const Text(
                    "Today's reminders",
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (state.todayReminders.isEmpty)
                    const _EmptyMessage(message: 'No reminders scheduled for today.')
                  else
                    ...state.todayReminders.map(
                      (reminder) => _buildCard(context, state, reminder),
                    ),
                ],
              ),
            ),
          ),
          floatingActionButton: null,
        );
      },
    );
  }

  Widget _buildCard(BuildContext context, AppState state, Reminder reminder) {
    final indexLabel = _globalIndexLabelForReminder(state.reminders, reminder);
    return ReminderCard(
      reminder: reminder,
      indexLabel: indexLabel,
      onToggle: (value) => state.toggleComplete(reminder, value),
      onEdit: () => AddEditReminderSheet.show(context, reminder: reminder),
      onDelete: () => state.deleteReminder(reminder),
    );
  }

  String? _globalIndexLabelForReminder(List<Reminder> reminders, Reminder reminder) {
    final ordered = reminders.toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final index = ordered.indexWhere((item) => item.id == reminder.id);
    if (index == -1) {
      return null;
    }
    return '#${index + 1}';
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
