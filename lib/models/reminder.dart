class Reminder {
  const Reminder({
    this.id,
    required this.title,
    this.description,
    required this.dateTime,
    this.isCompleted = false,
    this.priority = 'medium',
    this.repeatRule,
    this.notificationId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String? description;
  final DateTime dateTime;
  final bool isCompleted;
  final String priority;
  final String? repeatRule;
  final int? notificationId;
  final DateTime createdAt;
  final DateTime updatedAt;

  Reminder copyWith({
    int? id,
    String? title,
    String? description,
    DateTime? dateTime,
    bool? isCompleted,
    String? priority,
    String? repeatRule,
    int? notificationId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Reminder(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      dateTime: dateTime ?? this.dateTime,
      isCompleted: isCompleted ?? this.isCompleted,
      priority: priority ?? this.priority,
      repeatRule: repeatRule ?? this.repeatRule,
      notificationId: notificationId ?? this.notificationId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date_time': dateTime.toIso8601String(),
      'is_completed': isCompleted ? 1 : 0,
      'priority': priority,
      'repeat_rule': repeatRule == 'none' ? null : repeatRule,
      'notification_id': notificationId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Reminder.fromMap(Map<String, Object?> map) {
    return Reminder(
      id: map['id'] as int?,
      title: map['title'] as String,
      description: map['description'] as String?,
      dateTime: DateTime.parse(map['date_time'] as String),
      isCompleted: (map['is_completed'] as int? ?? 0) == 1,
      priority: map['priority'] as String? ?? 'medium',
      repeatRule: map['repeat_rule'] as String?,
      notificationId: map['notification_id'] as int?,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
