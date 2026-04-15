import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/chat_message.dart';
import '../models/reminder.dart';
import '../services/home_widget_service.dart';
import '../services/notification_service.dart';
import '../utils/constants.dart';
import '../utils/date_utils.dart';

class AppState extends ChangeNotifier {
  static const Set<String> _junkReminderTitles = {
    'do i have any schedule',
    'check if i have any schedule',
    'check if i have schedule',
  };

  AppState({
    required DatabaseHelper databaseHelper,
    required NotificationService notificationService,
  })  : _databaseHelper = databaseHelper,
        _notificationService = notificationService;

  final DatabaseHelper _databaseHelper;
  final NotificationService _notificationService;

  List<Reminder> _reminders = [];
  DateTime _selectedDay = DateTime.now();
  String _filter = ReminderFilter.all;
  String _sort = ReminderSort.date;
  String _searchQuery = '';
  bool _isLoading = true;

  bool get isLoading => _isLoading;
  DateTime get selectedDay => _selectedDay;
  String get filter => _filter;
  String get sort => _sort;
  String get searchQuery => _searchQuery;
  List<Reminder> get reminders => List.unmodifiable(_reminders);

  Future<void> initialize() async {
    _isLoading = true;
    notifyListeners();
    await _notificationService.requestPermissions();
    await refresh();
    await _cleanupJunkReminders();
    await _rescheduleFutureReminders();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() async {
    _reminders = await _databaseHelper.getAllReminders();
    _reminders.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    await HomeWidgetService.updateDayCountdownWidget(
      reminder: nextUpcomingReminder,
    );
    notifyListeners();
  }

  Reminder? get nextUpcomingReminder {
    for (final reminder in _reminders) {
      if (!reminder.isCompleted && reminder.dateTime.isAfter(DateTime.now())) {
        return reminder;
      }
    }
    return null;
  }

  List<Reminder> get todayReminders => _reminders
      .where((reminder) => AppDateUtils.isToday(reminder.dateTime))
      .toList();

  List<Reminder> get selectedDayReminders => _reminders
      .where((reminder) => AppDateUtils.isSameDay(reminder.dateTime, _selectedDay))
      .toList();

  Map<DateTime, List<Reminder>> get reminderEvents {
    final map = <DateTime, List<Reminder>>{};
    for (final reminder in _reminders) {
      final date = AppDateUtils.startOfDay(reminder.dateTime);
      map.putIfAbsent(date, () => []).add(reminder);
    }
    return map;
  }

  List<Reminder> get filteredReminders {
    Iterable<Reminder> items = _reminders;

    if (_searchQuery.isNotEmpty) {
      items = items.where(
        (reminder) =>
            reminder.title.toLowerCase().contains(_searchQuery.toLowerCase()),
      );
    }

    switch (_filter) {
      case ReminderFilter.today:
        items = items.where((reminder) => AppDateUtils.isToday(reminder.dateTime));
        break;
      case ReminderFilter.thisWeek:
        items = items.where((reminder) => AppDateUtils.isThisWeek(reminder.dateTime));
        break;
      case ReminderFilter.completed:
        items = items.where((reminder) => reminder.isCompleted);
        break;
      case ReminderFilter.all:
        break;
    }

    final list = items.toList();
    if (_sort == ReminderSort.priority) {
      list.sort((a, b) => _priorityRank(b.priority).compareTo(_priorityRank(a.priority)));
    } else {
      list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    }
    return list;
  }

  void setSelectedDay(DateTime date) {
    _selectedDay = AppDateUtils.startOfDay(date);
    notifyListeners();
  }

  void setFilter(String filter) {
    _filter = filter;
    notifyListeners();
  }

  void setSort(String sort) {
    _sort = sort;
    notifyListeners();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> saveReminder(Reminder reminder) async {
    if (reminder.id == null) {
      final notificationId =
          reminder.notificationId ?? _notificationService.generateNotificationId();
      final created = reminder.copyWith(notificationId: notificationId);
      final id = await _databaseHelper.insertReminder(created);
      final saved = created.copyWith(id: id);
      await _notificationService.scheduleReminder(saved);
    } else {
      await _notificationService.cancelReminder(reminder.notificationId);
      await _databaseHelper.updateReminder(reminder);
      await _notificationService.scheduleReminder(reminder);
    }
    await refresh();
  }

  Future<void> deleteReminder(Reminder reminder) async {
    if (reminder.id == null) {
      return;
    }
    await _notificationService.cancelReminder(reminder.notificationId);
    await _databaseHelper.deleteReminder(reminder.id!);
    await refresh();
  }

  Future<void> deleteReminders(Iterable<Reminder> reminders) async {
    final items = reminders.where((reminder) => reminder.id != null).toList();
    for (final reminder in items) {
      await _notificationService.cancelReminder(reminder.notificationId);
      await _databaseHelper.deleteReminder(reminder.id!);
    }
    await refresh();
  }

  Future<void> toggleComplete(Reminder reminder, bool value) async {
    if (reminder.id == null) {
      return;
    }
    if (value) {
      await _notificationService.cancelReminder(reminder.notificationId);
    } else if (reminder.dateTime.isAfter(DateTime.now())) {
      await _notificationService.scheduleReminder(reminder);
    }
    await _databaseHelper.toggleComplete(reminder.id!, value);
    await refresh();
  }

  Future<List<ChatMessage>> getChatHistory() async {
    final maps = await _databaseHelper.getChatHistory();
    return maps.map(ChatMessage.fromMap).toList();
  }

  Future<void> saveChatMessage(ChatMessage message) async {
    await _databaseHelper.insertChatMessage(message.toMap());
  }

  Future<void> clearChatHistory() async {
    await _databaseHelper.clearChatHistory();
    notifyListeners();
  }

  Future<void> _rescheduleFutureReminders() async {
    for (final reminder in _reminders) {
      if (!reminder.isCompleted && reminder.dateTime.isAfter(DateTime.now())) {
        await _notificationService.scheduleReminder(reminder);
      }
    }
  }

  Future<void> _cleanupJunkReminders() async {
    final junkReminders = _reminders.where((reminder) {
      return _junkReminderTitles.contains(reminder.title.toLowerCase().trim());
    }).toList();

    if (junkReminders.isEmpty) {
      return;
    }

    for (final reminder in junkReminders) {
      await _notificationService.cancelReminder(reminder.notificationId);
      if (reminder.id != null) {
        await _databaseHelper.deleteReminder(reminder.id!);
      }
    }

    await refresh();
  }

  int _priorityRank(String priority) {
    switch (priority) {
      case 'high':
        return 3;
      case 'medium':
        return 2;
      case 'low':
      default:
        return 1;
    }
  }
}
