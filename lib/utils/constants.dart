import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF0D47A1);
  static const secondary = Color(0xFF00695C);
  static const accent = Color(0xFFFFB300);
  static const background = Color(0xFF0B1020);
  static const surface = Color(0xFF151B2D);
  static const card = Color(0xFF1B2238);
  static const textPrimary = Colors.white;
  static const textSecondary = Color(0xFF9AA4BF);
  static const success = Color(0xFF43A047);
  static const warning = Color(0xFFFBC02D);
  static const danger = Color(0xFFE53935);
}

class ReminderPriority {
  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';

  static const values = [low, medium, high];

  static Color colorOf(String priority) {
    switch (priority) {
      case low:
        return AppColors.success;
      case high:
        return AppColors.danger;
      case medium:
      default:
        return AppColors.warning;
    }
  }
}

class ReminderRepeatRule {
  static const none = 'none';
  static const daily = 'daily';
  static const weekly = 'weekly';
  static const monthly = 'monthly';

  static const values = [none, daily, weekly, monthly];
}

class ReminderFilter {
  static const all = 'all';
  static const today = 'today';
  static const thisWeek = 'thisWeek';
  static const completed = 'completed';
}

class ReminderSort {
  static const date = 'date';
  static const priority = 'priority';
}
