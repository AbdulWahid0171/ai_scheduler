import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/reminder.dart';

typedef NotificationTapCallback = Future<void> Function(String? payload);

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const MethodChannel _alarmChannel = MethodChannel('ai_scheduler/alarm');
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  NotificationTapCallback? _onTap;

  Future<void> initialize(NotificationTapCallback onTap) async {
    _onTap = onTap;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: (details) async {
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

  Future<void> scheduleReminder(Reminder reminder) async {
    if (reminder.notificationId == null || reminder.dateTime.isBefore(DateTime.now())) {
      return;
    }
    await _alarmChannel.invokeMethod<void>(
      'scheduleAlarm',
      {
        'id': reminder.notificationId,
        'title': reminder.title,
        'body': reminder.description ?? 'Alarm is ringing',
        'triggerAtMillis': reminder.dateTime.millisecondsSinceEpoch,
        'mode': 'alarm',
      },
    );
  }

  Future<void> cancelReminder(int? notificationId) async {
    if (notificationId == null) {
      return;
    }
    await _alarmChannel.invokeMethod<void>(
      'cancelAlarm',
      {'id': notificationId},
    );
  }

  Future<void> showCountdownFinished({
    required int id,
    required String title,
  }) async {
    await _alarmChannel.invokeMethod<void>(
      'scheduleAlarm',
      {
        'id': id,
        'title': title,
        'body': 'Timer finished',
        'triggerAtMillis': DateTime.now().millisecondsSinceEpoch,
        'mode': 'timer',
      },
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

    await _alarmChannel.invokeMethod<void>(
      'scheduleAlarm',
      {
        'id': id,
        'title': title,
        'body': 'Timer finished',
        'triggerAtMillis': dateTime.millisecondsSinceEpoch,
        'mode': 'timer',
      },
    );
  }
}

@pragma('vm:entry-point')
void _backgroundNotificationTapHandler(NotificationResponse details) {
  // Native alarm actions are handled on Android.
}
