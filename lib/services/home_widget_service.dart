import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CountdownWidgetEntry {
  const CountdownWidgetEntry({
    required this.title,
    required this.targetMillis,
  });

  final String title;
  final int targetMillis;
}

class HomeWidgetService {
  HomeWidgetService._();

  static const MethodChannel _channel = MethodChannel('ai_scheduler/widget');

  static Future<void> updateCountdownWidget({
    required List<CountdownWidgetEntry> entries,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('updateHomeWidget', {
        'entries': entries
            .take(3)
            .map(
              (entry) => {
                'title': entry.title,
                'targetMillis': entry.targetMillis,
              },
            )
            .toList(),
      });
    } catch (_) {
      // Ignore platform channel failures outside Android widget support.
    }
  }

  static Future<void> clearCountdownWidget() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('updateHomeWidget', {
        'entries': const <Map<String, Object>>[],
      });
    } catch (_) {
      // Ignore platform channel failures outside Android widget support.
    }
  }
}
