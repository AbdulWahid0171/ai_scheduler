class ParsedReminderInput {
  const ParsedReminderInput({
    required this.title,
    required this.dateTime,
    this.didParseDate = false,
    this.didParseTime = false,
  });

  final String title;
  final DateTime dateTime;
  final bool didParseDate;
  final bool didParseTime;
}

class NaturalLanguageParser {
  static final RegExp _inHoursPattern =
      RegExp(r'\bin\s+(\d+)\s+hours?\b', caseSensitive: false);
  static final RegExp _explicitDatePattern = RegExp(
    r'\b(\d{1,2})(?:st|nd|rd|th)?\s+'
    r'(january|february|march|april|may|june|july|august|september|october|november|december|'
    r'jan|feb|mar|apr|jun|jul|aug|sep|sept|oct|nov|dec)\b',
    caseSensitive: false,
  );
  static final RegExp _timePattern = RegExp(
    r'\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm)?\b',
    caseSensitive: false,
  );
  static final List<String> _weekdays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];

  ParsedReminderInput parse(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      return ParsedReminderInput(title: '', dateTime: _defaultDateTime());
    }

    final now = DateTime.now();
    var title = raw;
    var timeSearchText = raw;
    var parsedDate = DateTime(now.year, now.month, now.day);
    var parsedTime = DateTime(now.year, now.month, now.day, now.hour + 1);
    var didParseDate = false;
    var didParseTime = false;

    final inHoursMatch = _inHoursPattern.firstMatch(raw);
    if (inHoursMatch != null) {
      final hours = int.tryParse(inHoursMatch.group(1) ?? '');
      if (hours != null) {
        final future = now.add(Duration(hours: hours));
        parsedDate = DateTime(future.year, future.month, future.day);
        parsedTime = future;
        didParseDate = true;
        didParseTime = true;
        title = title.replaceFirst(inHoursMatch.group(0)!, '').trim();
        timeSearchText =
            timeSearchText.replaceFirst(inHoursMatch.group(0)!, '').trim();
      }
    }

    final lower = raw.toLowerCase();
    if (lower.contains('tomorrow')) {
      final tomorrow = now.add(const Duration(days: 1));
      parsedDate = DateTime(tomorrow.year, tomorrow.month, tomorrow.day);
      didParseDate = true;
      title = title.replaceAll(RegExp(r'\btomorrow\b', caseSensitive: false), '').trim();
      timeSearchText = timeSearchText
          .replaceAll(RegExp(r'\btomorrow\b', caseSensitive: false), '')
          .trim();
    } else if (lower.contains('today')) {
      parsedDate = DateTime(now.year, now.month, now.day);
      didParseDate = true;
      title = title.replaceAll(RegExp(r'\btoday\b', caseSensitive: false), '').trim();
      timeSearchText = timeSearchText
          .replaceAll(RegExp(r'\btoday\b', caseSensitive: false), '')
          .trim();
    }

    for (var i = 0; i < _weekdays.length; i++) {
      final weekdayName = _weekdays[i];
      final nextPattern =
          RegExp(r'\bnext\s+' + weekdayName + r'\b', caseSensitive: false);
      final dayPattern =
          RegExp(r'\b' + weekdayName + r'\b', caseSensitive: false);
      if (nextPattern.hasMatch(lower)) {
        parsedDate = _nextWeekday(now, i + 1, skipCurrentWeek: true);
        didParseDate = true;
        title = title.replaceAll(nextPattern, '').trim();
        timeSearchText = timeSearchText.replaceAll(nextPattern, '').trim();
        break;
      }
      if (dayPattern.hasMatch(lower)) {
        parsedDate = _nextWeekday(now, i + 1);
        didParseDate = true;
        title = title.replaceAll(dayPattern, '').trim();
        timeSearchText = timeSearchText.replaceAll(dayPattern, '').trim();
        break;
      }
    }

    final explicitDateMatch = _explicitDatePattern.firstMatch(raw);
    if (explicitDateMatch != null) {
      final day = int.tryParse(explicitDateMatch.group(1) ?? '');
      final month = _parseMonth(explicitDateMatch.group(2) ?? '');
      if (day != null && month != null) {
        var year = now.year;
        var candidate = DateTime(year, month, day);
        if (candidate.isBefore(DateTime(now.year, now.month, now.day))) {
          year += 1;
          candidate = DateTime(year, month, day);
        }
        parsedDate = DateTime(candidate.year, candidate.month, candidate.day);
        didParseDate = true;
        title = title.replaceFirst(explicitDateMatch.group(0)!, '').trim();
        timeSearchText =
            timeSearchText.replaceFirst(explicitDateMatch.group(0)!, '').trim();
      }
    }

    if (!didParseTime) {
      final timeMatch = _timePattern.firstMatch(timeSearchText);
      if (timeMatch != null) {
        final hourRaw = int.tryParse(timeMatch.group(1) ?? '');
        final minute = int.tryParse(timeMatch.group(2) ?? '0') ?? 0;
        final meridiem = timeMatch.group(3)?.toLowerCase();
        if (hourRaw != null) {
          var hour = hourRaw;
          if (meridiem == 'pm' && hour < 12) {
            hour += 12;
          }
          if (meridiem == 'am' && hour == 12) {
            hour = 0;
          }
          if (hour >= 0 && hour < 24 && minute >= 0 && minute < 60) {
            parsedTime = DateTime(
              parsedDate.year,
              parsedDate.month,
              parsedDate.day,
              hour,
              minute,
            );
            didParseTime = true;
            title = title.replaceFirst(timeMatch.group(0)!, '').trim();
          }
        }
      }
    } else {
      parsedTime = DateTime(
        parsedTime.year,
        parsedTime.month,
        parsedTime.day,
        parsedTime.hour,
        parsedTime.minute,
      );
    }

    final resolvedDateTime = DateTime(
      parsedDate.year,
      parsedDate.month,
      parsedDate.day,
      parsedTime.hour,
      parsedTime.minute,
    );

    return ParsedReminderInput(
      title: title.replaceAll(RegExp(r'\s+'), ' ').trim(),
      dateTime: resolvedDateTime,
      didParseDate: didParseDate,
      didParseTime: didParseTime,
    );
  }

  DateTime _defaultDateTime() => DateTime.now().add(const Duration(hours: 1));

  int? _parseMonth(String value) {
    switch (value.toLowerCase()) {
      case 'january':
      case 'jan':
        return 1;
      case 'february':
      case 'feb':
        return 2;
      case 'march':
      case 'mar':
        return 3;
      case 'april':
      case 'apr':
        return 4;
      case 'may':
        return 5;
      case 'june':
      case 'jun':
        return 6;
      case 'july':
      case 'jul':
        return 7;
      case 'august':
      case 'aug':
        return 8;
      case 'september':
      case 'sep':
      case 'sept':
        return 9;
      case 'october':
      case 'oct':
        return 10;
      case 'november':
      case 'nov':
        return 11;
      case 'december':
      case 'dec':
        return 12;
      default:
        return null;
    }
  }

  DateTime _nextWeekday(DateTime now, int weekday, {bool skipCurrentWeek = false}) {
    var daysAhead = (weekday - now.weekday) % 7;
    if (daysAhead <= 0 || skipCurrentWeek) {
      daysAhead += 7;
    }
    final date = now.add(Duration(days: daysAhead));
    return DateTime(date.year, date.month, date.day);
  }
}
