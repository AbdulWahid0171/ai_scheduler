import 'package:shared_preferences/shared_preferences.dart';

import '../models/persistent_countdown.dart';
import 'home_widget_service.dart';
import 'notification_service.dart';

class PersistentCountdownService {
  PersistentCountdownService._();

  static final PersistentCountdownService instance = PersistentCountdownService._();
  static const String _storageKey = 'persistent_countdowns_v1';

  Future<List<PersistentCountdown>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey) ?? const <String>[];
    final now = DateTime.now();
    final parsed = stored
        .map(PersistentCountdown.tryParseJson)
        .whereType<PersistentCountdown>()
        .toList();
    final items = parsed
        .map((item) => _normalize(item, now))
        .toList()
      ..sort(_compareCountdowns);
    final changed = parsed.length != items.length ||
        parsed.asMap().entries.any((entry) => entry.value.toJson() != items[entry.key].toJson());
    if (changed) {
      await _saveAll(items);
    } else {
      await _syncWidget(items);
    }
    return items;
  }

  Future<List<PersistentCountdown>> create({
    required String label,
    required Duration duration,
  }) async {
    final items = await loadAll();
    final nextId = items.isEmpty
        ? 1
        : items.map((entry) => entry.id).reduce((a, b) => a > b ? a : b) + 1;
    final countdown = PersistentCountdown(
      id: nextId,
      notificationId: NotificationService.instance.generateNotificationId(),
      label: label,
      totalDurationMillis: duration.inMilliseconds,
      remainingMillis: duration.inMilliseconds,
      status: PersistentCountdownStatus.idle,
    );
    final updated = [...items, countdown]..sort(_compareCountdowns);
    await _saveAll(updated);
    return updated;
  }

  Future<List<PersistentCountdown>> start(int id) async {
    final now = DateTime.now();
    final items = await loadAll();
    final updated = <PersistentCountdown>[];
    for (final item in items) {
      if (item.id != id) {
        updated.add(item);
        continue;
      }
      final remaining = item.remainingMillisAt(now);
      final running = item.copyWith(
        remainingMillis: remaining,
        status: PersistentCountdownStatus.running,
        targetEpochMillis: now.millisecondsSinceEpoch + remaining,
      );
      await NotificationService.instance.scheduleCountdownAlarm(
        id: running.notificationId,
        title: running.label,
        dateTime: DateTime.fromMillisecondsSinceEpoch(running.targetEpochMillis!),
      );
      updated.add(running);
    }
    updated.sort(_compareCountdowns);
    await _saveAll(updated);
    return updated;
  }

  Future<List<PersistentCountdown>> pause(int id) async {
    final now = DateTime.now();
    final items = await loadAll();
    final updated = <PersistentCountdown>[];
    for (final item in items) {
      if (item.id != id) {
        updated.add(item);
        continue;
      }
      final paused = item.copyWith(
        remainingMillis: item.remainingMillisAt(now),
        status: PersistentCountdownStatus.paused,
        clearTargetEpochMillis: true,
      );
      await NotificationService.instance.cancelReminder(item.notificationId);
      updated.add(paused);
    }
    updated.sort(_compareCountdowns);
    await _saveAll(updated);
    return updated;
  }

  Future<List<PersistentCountdown>> reset(int id) async {
    final items = await loadAll();
    final updated = <PersistentCountdown>[];
    for (final item in items) {
      if (item.id != id) {
        updated.add(item);
        continue;
      }
      final reset = item.copyWith(
        remainingMillis: item.totalDurationMillis,
        status: PersistentCountdownStatus.idle,
        clearTargetEpochMillis: true,
      );
      await NotificationService.instance.cancelReminder(item.notificationId);
      updated.add(reset);
    }
    updated.sort(_compareCountdowns);
    await _saveAll(updated);
    return updated;
  }

  Future<List<PersistentCountdown>> delete(int id) async {
    final items = await loadAll();
    final deleting = items.where((item) => item.id == id).toList();
    for (final item in deleting) {
      await NotificationService.instance.cancelReminder(item.notificationId);
    }
    final updated = items.where((item) => item.id != id).toList()
      ..sort(_compareCountdowns);
    await _saveAll(updated);
    return updated;
  }

  Future<List<PersistentCountdown>> sync() async {
    return loadAll();
  }

  Future<void> _saveAll(List<PersistentCountdown> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      items.map((item) => item.toJson()).toList(),
    );
    await _syncWidget(items);
  }

  Future<void> _syncWidget(List<PersistentCountdown> items) async {
    final now = DateTime.now();
    final active = items.map((item) => _normalize(item, now)).toList();
    if (active.isEmpty) {
      await HomeWidgetService.clearPersistentCountdownWidget();
      return;
    }

    final primary = active.first;
    final remainingMillis = primary.remainingMillisAt(now);
    await HomeWidgetService.updatePersistentCountdownWidget(
      title: primary.label,
      status: primary.status.name,
      remainingMillis: remainingMillis,
      targetMillis: primary.targetEpochMillis ?? 0,
    );
  }

  PersistentCountdown _normalize(PersistentCountdown item, DateTime now) {
    if (item.status != PersistentCountdownStatus.running || item.targetEpochMillis == null) {
      return item;
    }

    if (item.targetEpochMillis! > now.millisecondsSinceEpoch) {
      return item;
    }

    return item.copyWith(
      remainingMillis: 0,
      status: PersistentCountdownStatus.finished,
      clearTargetEpochMillis: true,
    );
  }

  int _compareCountdowns(PersistentCountdown a, PersistentCountdown b) {
    final rankA = _statusRank(a.status);
    final rankB = _statusRank(b.status);
    if (rankA != rankB) {
      return rankA.compareTo(rankB);
    }
    final targetA = a.targetEpochMillis ?? (1 << 62);
    final targetB = b.targetEpochMillis ?? (1 << 62);
    if (targetA != targetB) {
      return targetA.compareTo(targetB);
    }
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  }

  int _statusRank(PersistentCountdownStatus status) {
    switch (status) {
      case PersistentCountdownStatus.running:
        return 0;
      case PersistentCountdownStatus.paused:
        return 1;
      case PersistentCountdownStatus.idle:
        return 2;
      case PersistentCountdownStatus.finished:
        return 3;
    }
  }
}
