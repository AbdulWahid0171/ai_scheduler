import 'package:intl/intl.dart';

class AppDateUtils {
  static final DateFormat _clockFormat = DateFormat('HH:mm:ss');
  static final DateFormat _headerDateFormat = DateFormat('EEEE, MMMM d, y');
  static final DateFormat _monthYearFormat = DateFormat('MMMM y');
  static final DateFormat _timeFormat = DateFormat('h:mm a');
  static final DateFormat _shortDateFormat = DateFormat('EEE, MMM d');
  static final DateFormat _groupDateFormat = DateFormat('EEEE, MMM d');

  static String formatClock(DateTime dateTime) => _clockFormat.format(dateTime);

  static String formatHeaderDate(DateTime dateTime) =>
      _headerDateFormat.format(dateTime);

  static String formatMonthYear(DateTime dateTime) =>
      _monthYearFormat.format(dateTime);

  static String formatTime(DateTime dateTime) => _timeFormat.format(dateTime);

  static String formatShortDate(DateTime dateTime) =>
      _shortDateFormat.format(dateTime);

  static String formatGroupDate(DateTime dateTime) =>
      _groupDateFormat.format(dateTime);

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime startOfDay(DateTime dateTime) =>
      DateTime(dateTime.year, dateTime.month, dateTime.day);

  static bool isToday(DateTime dateTime) => isSameDay(dateTime, DateTime.now());

  static bool isThisWeek(DateTime dateTime) {
    final now = DateTime.now();
    final start = startOfDay(now.subtract(Duration(days: now.weekday - 1)));
    final end = start.add(const Duration(days: 7));
    return !dateTime.isBefore(start) && dateTime.isBefore(end);
  }

  static int daysUntil(DateTime dateTime) {
    final now = startOfDay(DateTime.now());
    final target = startOfDay(dateTime);
    return target.difference(now).inDays;
  }
}
