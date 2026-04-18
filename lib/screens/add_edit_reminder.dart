import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/reminder.dart';
import '../services/nl_parser.dart';
import '../state/app_state.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';
import '../widgets/nl_input_bar.dart';

class AddEditReminderSheet extends StatefulWidget {
  const AddEditReminderSheet({
    super.key,
    this.reminder,
    this.initialDate,
    this.countdownMode = false,
  });

  final Reminder? reminder;
  final DateTime? initialDate;
  final bool countdownMode;

  static Future<void> show(
    BuildContext context, {
    Reminder? reminder,
    DateTime? initialDate,
    bool countdownMode = false,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEditReminderSheet(
        reminder: reminder,
        initialDate: initialDate,
        countdownMode: countdownMode,
      ),
    );
  }

  @override
  State<AddEditReminderSheet> createState() => _AddEditReminderSheetState();
}

class _AddEditReminderSheetState extends State<AddEditReminderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _parser = NaturalLanguageParser();
  late final TextEditingController _nlController;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;

  late DateTime _selectedDateTime;
  late String _priority;
  late String _repeatRule;
  ParsedReminderInput _preview = ParsedReminderInput(
    title: '',
    dateTime: DateTime.now().add(const Duration(hours: 1)),
  );

  @override
  void initState() {
    super.initState();
    final baseDate = widget.reminder?.dateTime ??
        widget.initialDate ??
        DateTime.now().add(const Duration(hours: 1));
    _selectedDateTime = baseDate;
    _priority = widget.reminder?.priority ?? ReminderPriority.medium;
    _repeatRule = widget.reminder?.repeatRule ?? ReminderRepeatRule.none;
    _titleController = TextEditingController(text: widget.reminder?.title ?? '');
    _descriptionController =
        TextEditingController(text: widget.reminder?.description ?? '');
    _nlController = TextEditingController();
    _preview = ParsedReminderInput(
      title: _titleController.text,
      dateTime: _selectedDateTime,
    );
  }

  @override
  void dispose() {
    _nlController.dispose();
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _selectedDateTime.hour,
          _selectedDateTime.minute,
        );
        _preview = ParsedReminderInput(
          title: _titleController.text,
          dateTime: _selectedDateTime,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selectedDateTime),
    );
    if (picked != null) {
      setState(() {
        _selectedDateTime = DateTime(
          _selectedDateTime.year,
          _selectedDateTime.month,
          _selectedDateTime.day,
          picked.hour,
          picked.minute,
        );
        _preview = ParsedReminderInput(
          title: _titleController.text,
          dateTime: _selectedDateTime,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reminder time must be in the future.')),
      );
      return;
    }

    final appState = context.read<AppState>();
    final conflict = appState.reminders.where((reminder) {
      if (reminder.isCompleted) {
        return false;
      }
      if (widget.reminder?.id != null && reminder.id == widget.reminder!.id) {
        return false;
      }
      return reminder.dateTime == _selectedDateTime;
    }).firstOrNull;
    if (conflict != null) {
      final conflictTime = AppDateUtils.formatTime(conflict.dateTime);
      final conflictDate = AppDateUtils.formatShortDate(conflict.dateTime);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'That time is already used by "${conflict.title}" on $conflictDate at $conflictTime.',
          ),
        ),
      );
      return;
    }

    final title = _titleController.text.trim().isEmpty && widget.countdownMode
        ? 'Countdown'
        : _titleController.text.trim();

    final now = DateTime.now();
    final reminder = Reminder(
      id: widget.reminder?.id,
      title: title,
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      dateTime: _selectedDateTime,
      isCompleted: widget.reminder?.isCompleted ?? false,
      priority: _priority,
      repeatRule: _repeatRule == ReminderRepeatRule.none ? null : _repeatRule,
      notificationId: widget.reminder?.notificationId,
      createdAt: widget.reminder?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      await appState.saveReminder(reminder);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to save reminder right now.')),
        );
      }
    }
  }

  Future<void> _delete() async {
    final reminder = widget.reminder;
    if (reminder == null) {
      return;
    }
    final appState = context.read<AppState>();
    final navigator = Navigator.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete reminder?'),
        content: Text('Remove "${reminder.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await appState.deleteReminder(reminder);
      navigator.pop();
    }
  }

  void _applyNaturalLanguage(String value) {
    final parsed = _parser.parse(value);
    setState(() {
      _preview = parsed;
      if (parsed.title.isNotEmpty) {
        _titleController.text = parsed.title;
      }
      _selectedDateTime = parsed.dateTime;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.countdownMode
                      ? (widget.reminder == null
                          ? 'Set day countdown'
                          : 'Edit day countdown')
                      : (widget.reminder == null ? 'Add reminder' : 'Edit reminder'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 20),
                if (!widget.countdownMode) ...[
                  NaturalLanguageInputBar(
                    controller: _nlController,
                    preview: _preview,
                    onChanged: _applyNaturalLanguage,
                  ),
                  const SizedBox(height: 20),
                ],
                _buildTextField(
                  controller: _titleController,
                  label: widget.countdownMode ? 'Title (optional)' : 'Title',
                  validator: widget.countdownMode
                      ? null
                      : (value) => (value == null || value.trim().isEmpty)
                          ? 'Title is required'
                          : null,
                ),
                if (!widget.countdownMode) ...[
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _descriptionController,
                    label: 'Description',
                    maxLines: 3,
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _pickerButton(
                        label: AppDateUtils.formatShortDate(_selectedDateTime),
                        icon: Icons.calendar_month,
                        onTap: _pickDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _pickerButton(
                        label: AppDateUtils.formatTime(_selectedDateTime),
                        icon: Icons.schedule,
                        onTap: _pickTime,
                      ),
                    ),
                  ],
                ),
                if (!widget.countdownMode) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Priority',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    children: ReminderPriority.values.map((priority) {
                      final selected = _priority == priority;
                      return ChoiceChip(
                        label: Text(priority.toUpperCase()),
                        selected: selected,
                        selectedColor:
                            ReminderPriority.colorOf(priority).withAlpha(56),
                        labelStyle: TextStyle(
                          color: selected
                              ? ReminderPriority.colorOf(priority)
                              : AppColors.textSecondary,
                        ),
                        onSelected: (_) => setState(() => _priority = priority),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    initialValue: _repeatRule,
                    dropdownColor: AppColors.surface,
                    decoration: _inputDecoration('Repeat'),
                    items: ReminderRepeatRule.values
                        .map(
                          (rule) => DropdownMenuItem(
                            value: rule,
                            child: Text(
                              rule == ReminderRepeatRule.none
                                  ? 'None'
                                  : '${rule[0].toUpperCase()}${rule.substring(1)}',
                              style: const TextStyle(color: AppColors.textPrimary),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _repeatRule = value);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (widget.reminder != null)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _delete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Delete'),
                        ),
                      ),
                    if (widget.reminder != null) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: Text(
                          widget.countdownMode ? 'Start countdown' : 'Save reminder',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pickerButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: _inputDecoration(label),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    );
  }
}
