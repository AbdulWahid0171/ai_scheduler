import 'dart:math';
import 'dart:convert';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../models/reminder.dart';

typedef NotificationTapCallback = Future<void> Function(String? payload);

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  NotificationTapCallback? _onTap;

  Future<void> initialize(NotificationTapCallback onTap) async {
    _onTap = onTap;
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (details) async {
        await _handleNotificationResponse(details);
        await _onTap?.call(details.payload);
      },
      onDidReceiveBackgroundNotificationResponse:
          _backgroundNotificationTapHandler,
    );

    // Create a high-priority 'alarms' channel
    const alarmsChannel = AndroidNotificationChannel(
      'alarms',
      'Alarms',
      description: 'High priority alarm notifications',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    // Create a separate 'reminders' channel for normal notifications
    const remindersChannel = AndroidNotificationChannel(
      'reminders',
      'Reminders',
      description: 'Regular reminder notifications',
      importance: Importance.defaultImportance,
    );

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    
    await androidPlugin?.createNotificationChannel(alarmsChannel);
    await androidPlugin?.createNotificationChannel(remindersChannel);
  }

  Future<void> requestPermissions() async {
    await Permission.notification.request();
    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  int generateNotificationId() => Random().nextInt(1 << 31);

  NotificationDetails _getAlarmNotificationDetails() {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'alarms',
        'Alarms',
        channelDescription: 'Alarm style reminder notifications',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        fullScreenIntent: true,
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
        actions: _alarmActions(),
      ),
    );
  }

  Future<void> scheduleReminder(Reminder reminder) async {
    if (reminder.notificationId == null || reminder.dateTime.isBefore(DateTime.now())) {
      return;
    }

    await _plugin.zonedSchedule(
      id: reminder.notificationId!,
      title: reminder.title,
      body: reminder.description ?? 'Reminder is ringing',
      scheduledDate: tz.TZDateTime.from(reminder.dateTime, tz.local),
      notificationDetails: _getAlarmNotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: jsonEncode({
        'id': reminder.notificationId,
        'title': reminder.title,
        'body': reminder.description ?? 'Reminder is ringing',
      }),
    );
  }

  Future<void> cancelReminder(int? notificationId) async {
    if (notificationId == null) {
      return;
    }
    await _plugin.cancel(id: notificationId);
  }

  Future<void> showCountdownFinished({
    required int id,
    required String title,
  }) async {
    await _plugin.show(
      id: id,
      title: 'Countdown finished',
      body: title,
      notificationDetails: _getAlarmNotificationDetails(),
    );
  }

  Future<void> scheduleCountdownAlarm({
    required int id,
    required String title,
    required DateTime dateTime,
  }) async {
    if (dateTime.isBefore(DateTime.now())) {
      return;
    }

    await _plugin.zonedSchedule(
      id: id,
      title: 'Countdown finished',
      body: title,
      scheduledDate: tz.TZDateTime.from(dateTime, tz.local),
      notificationDetails: _getAlarmNotificationDetails(),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: jsonEncode({
        'id': id,
        'title': 'Countdown finished',
        'body': title,
      }),
    );
  }

  List<AndroidNotificationAction> _alarmActions() {
    return [
      const AndroidNotificationAction(
        'dismiss',
        'Dismiss',
        cancelNotification: true,
      ),
      const AndroidNotificationAction(
        'snooze',
        'Snooze (5 min)',
        cancelNotification: true,
      ),
    ];
  }

  Future<void> _handleNotificationResponse(NotificationResponse details) async {
    if (details.actionId != 'snooze') {
      return;
    }

    final payload = details.payload;
    if (payload == null || payload.isEmpty) {
      return;
    }

    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final id = data['id'] as int?;
      final title = data['title'] as String? ?? 'Alarm';
      final body = data['body'] as String? ?? '';
      if (id == null) {
        return;
      }

      // Reschedule for 5 minutes later
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(
          DateTime.now().add(const Duration(minutes: 5)),
          tz.local,
        ),
        notificationDetails: _getAlarmNotificationDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    } catch (_) {}
  }
}

@pragma('vm:entry-point')
void _backgroundNotificationTapHandler(NotificationResponse details) {
  // Note: For background execution to work for snooze, 
  // we would need to initialize tz and the plugin inside this isolate.
}
