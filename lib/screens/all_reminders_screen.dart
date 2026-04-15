import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../state/app_state.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';
import '../widgets/reminder_card.dart';
import 'add_edit_reminder.dart';

class AllRemindersScreen extends StatefulWidget {
  const AllRemindersScreen({super.key});

  @override
  State<AllRemindersScreen> createState() => _AllRemindersScreenState();
}

class _AllRemindersScreenState extends State<AllRemindersScreen> {
  final Set<int> _selectedReminderIds = <int>{};
  bool _selectionMode = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        final grouped = <String, List<Reminder>>{};
        for (final reminder in state.filteredReminders) {
          final key = AppDateUtils.formatGroupDate(reminder.dateTime);
          grouped.putIfAbsent(key, () => []).add(reminder);
        }

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: state.setSearchQuery,
                        style: const TextStyle(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Search reminders',
                          hintStyle:
                              const TextStyle(color: AppColors.textSecondary),
                          prefixIcon: const Icon(
                            Icons.search,
                            color: AppColors.textSecondary,
                          ),
                          filled: true,
                          fillColor: AppColors.card,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: () => _toggleSelectionMode(),
                      child: Text(_selectionMode ? 'Cancel' : 'Select'),
                    ),
                  ],
                ),
                if (_selectionMode) ...[
                  const SizedBox(height: 12),
                  _SelectionToolbar(
                    selectedCount: _selectedReminderIds.length,
                    onSelectAll: () => _selectAll(state.filteredReminders),
                    onClear: _clearSelection,
                    onDelete: _selectedReminderIds.isEmpty
                        ? null
                        : () => _deleteSelected(context, state),
                  ),
                ],
                const SizedBox(height: 16),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(state, 'All', ReminderFilter.all),
                      _filterChip(state, 'Today', ReminderFilter.today),
                      _filterChip(state, 'This Week', ReminderFilter.thisWeek),
                      _filterChip(state, 'Completed', ReminderFilter.completed),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: ReminderSort.date, label: Text('Date')),
                    ButtonSegment(
                      value: ReminderSort.priority,
                      label: Text('Priority'),
                    ),
                  ],
                  selected: {state.sort},
                  onSelectionChanged: (value) => state.setSort(value.first),
                ),
                const SizedBox(height: 20),
                if (grouped.isEmpty)
                  const _AllEmpty()
                else
                  ...grouped.entries.expand(
                    (entry) => [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          entry.key,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      ...entry.value.map((reminder) {
                        final indexLabel = _globalIndexLabelForReminder(
                          state.reminders,
                          reminder,
                        );
                        final isSelected = reminder.id != null &&
                            _selectedReminderIds.contains(reminder.id);
                        return ReminderCard(
                          reminder: reminder,
                          indexLabel: indexLabel,
                          selectionMode: _selectionMode,
                          selected: isSelected,
                          onSelectToggle: reminder.id == null
                              ? null
                              : (value) => _setSelected(reminder.id!, value),
                          onToggle: (value) =>
                              state.toggleComplete(reminder, value),
                          onEdit: () =>
                              AddEditReminderSheet.show(context, reminder: reminder),
                          onDelete: () => state.deleteReminder(reminder),
                        );
                      }),
                    ],
                  ),
              ],
            ),
          ),
          floatingActionButton: null,
        );
      },
    );
  }

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) {
        _selectedReminderIds.clear();
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedReminderIds.clear();
    });
  }

  void _selectAll(List<Reminder> reminders) {
    setState(() {
      _selectedReminderIds
        ..clear()
        ..addAll(reminders.where((item) => item.id != null).map((item) => item.id!));
    });
  }

  void _setSelected(int id, bool value) {
    setState(() {
      if (value) {
        _selectedReminderIds.add(id);
      } else {
        _selectedReminderIds.remove(id);
      }
    });
  }

  Future<void> _deleteSelected(BuildContext context, AppState state) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Selected?'),
        content: Text(
          'Delete ${_selectedReminderIds.length} selected reminder(s)?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'DELETE',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      return;
    }

    final remindersToDelete = state.reminders
        .where((reminder) => reminder.id != null)
        .where((reminder) => _selectedReminderIds.contains(reminder.id))
        .toList();

    await state.deleteReminders(remindersToDelete);
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedReminderIds.clear();
      _selectionMode = false;
    });
  }

  Widget _filterChip(AppState state, String label, String filter) {
    final selected = state.filter == filter;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: selected,
        label: Text(label),
        onSelected: (_) => state.setFilter(filter),
        selectedColor: AppColors.accent.withAlpha(50),
        labelStyle: TextStyle(
          color: selected ? AppColors.accent : AppColors.textSecondary,
        ),
        backgroundColor: AppColors.card,
      ),
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

class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.selectedCount,
    required this.onSelectAll,
    required this.onClear,
    required this.onDelete,
  });

  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$selectedCount selected',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onSelectAll,
            child: const Text('Select All'),
          ),
          TextButton(
            onPressed: onClear,
            child: const Text('Clear'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

class _AllEmpty extends StatelessWidget {
  const _AllEmpty();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Text(
        'No reminders match the current filters.',
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}
