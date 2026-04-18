import 'dart:convert';

enum PersistentCountdownStatus {
  idle,
  running,
  paused,
  finished,
}

class PersistentCountdown {
  const PersistentCountdown({
    required this.id,
    required this.notificationId,
    required this.label,
    required this.totalDurationMillis,
    required this.remainingMillis,
    required this.status,
    this.targetEpochMillis,
  });

  final int id;
  final int notificationId;
  final String label;
  final int totalDurationMillis;
  final int remainingMillis;
  final PersistentCountdownStatus status;
  final int? targetEpochMillis;

  Duration get totalDuration => Duration(milliseconds: totalDurationMillis);

  int remainingMillisAt(DateTime now) {
    if (status != PersistentCountdownStatus.running || targetEpochMillis == null) {
      return remainingMillis.clamp(0, totalDurationMillis);
    }
    return (targetEpochMillis! - now.millisecondsSinceEpoch).clamp(0, totalDurationMillis);
  }

  Duration remainingAt(DateTime now) => Duration(milliseconds: remainingMillisAt(now));

  bool get isFinished => status == PersistentCountdownStatus.finished;

  PersistentCountdown copyWith({
    int? id,
    int? notificationId,
    String? label,
    int? totalDurationMillis,
    int? remainingMillis,
    PersistentCountdownStatus? status,
    int? targetEpochMillis,
    bool clearTargetEpochMillis = false,
  }) {
    return PersistentCountdown(
      id: id ?? this.id,
      notificationId: notificationId ?? this.notificationId,
      label: label ?? this.label,
      totalDurationMillis: totalDurationMillis ?? this.totalDurationMillis,
      remainingMillis: remainingMillis ?? this.remainingMillis,
      status: status ?? this.status,
      targetEpochMillis: clearTargetEpochMillis
          ? null
          : targetEpochMillis ?? this.targetEpochMillis,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'notificationId': notificationId,
      'label': label,
      'totalDurationMillis': totalDurationMillis,
      'remainingMillis': remainingMillis,
      'status': status.name,
      'targetEpochMillis': targetEpochMillis,
    };
  }

  String toJson() => jsonEncode(toMap());

  static PersistentCountdown fromMap(Map<String, dynamic> map) {
    final rawStatus = map['status'] as String? ?? PersistentCountdownStatus.idle.name;
    return PersistentCountdown(
      id: (map['id'] as num).toInt(),
      notificationId: (map['notificationId'] as num).toInt(),
      label: map['label'] as String? ?? 'Countdown',
      totalDurationMillis: (map['totalDurationMillis'] as num).toInt(),
      remainingMillis: (map['remainingMillis'] as num).toInt(),
      status: PersistentCountdownStatus.values.firstWhere(
        (value) => value.name == rawStatus,
        orElse: () => PersistentCountdownStatus.idle,
      ),
      targetEpochMillis: (map['targetEpochMillis'] as num?)?.toInt(),
    );
  }

  static PersistentCountdown? tryParseJson(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return fromMap(decoded);
      }
      if (decoded is Map) {
        return fromMap(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      return null;
    }
    return null;
  }
}
