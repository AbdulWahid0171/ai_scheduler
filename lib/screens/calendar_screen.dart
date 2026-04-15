import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/reminder.dart';
import '../state/app_state.dart';
import '../utils/constants.dart';
import '../widgets/reminder_card.dart';
import 'add_edit_reminder.dart';

class CalendarScreen extends StatelessWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TableCalendar<Reminder>(
                    firstDay: DateTime.utc(2020),
                    lastDay: DateTime.utc(2100),
                    focusedDay: state.selectedDay,
                    selectedDayPredicate: (day) =>
                        isSameDay(day, state.selectedDay),
                    eventLoader: (day) =>
                        state.reminderEvents[DateTime(day.year, day.month, day.day)] ??
                        const [],
                    onDaySelected: (selectedDay, focusedDay) {
                      state.setSelectedDay(selectedDay);
                    },
                    headerStyle: const HeaderStyle(
                      titleTextStyle: TextStyle(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                      formatButtonVisible: false,
                      leftChevronIcon:
                          Icon(Icons.chevron_left, color: AppColors.textPrimary),
                      rightChevronIcon:
                          Icon(Icons.chevron_right, color: AppColors.textPrimary),
                    ),
                    calendarStyle: CalendarStyle(
                      defaultTextStyle:
                          const TextStyle(color: AppColors.textPrimary),
                      weekendTextStyle:
                          const TextStyle(color: AppColors.textPrimary),
                      outsideTextStyle:
                          const TextStyle(color: AppColors.textSecondary),
                      todayDecoration: BoxDecoration(
                        color: AppColors.secondary.withAlpha(180),
                        shape: BoxShape.circle,
                      ),
                      selectedDecoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Selected day',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (state.selectedDayReminders.isEmpty)
                  const _CalendarEmpty()
                else
                  ...state.selectedDayReminders.map(
                    (reminder) => ReminderCard(
                      reminder: reminder,
                      onToggle: (value) => state.toggleComplete(reminder, value),
                      onEdit: () => AddEditReminderSheet.show(
                        context,
                        reminder: reminder,
                      ),
                      onDelete: () => state.deleteReminder(reminder),
                    ),
                  ),
              ],
            ),
          ),
          floatingActionButton: null,
        );
      },
    );
  }
}

class _CalendarEmpty extends StatelessWidget {
  const _CalendarEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Text(
        'No reminders on this day yet.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
