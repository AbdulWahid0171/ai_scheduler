import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HomeWidgetService {
  HomeWidgetService._();

  static const MethodChannel _channel = MethodChannel('ai_scheduler/widget');

  static Future<void> updateCountdownWidget({
    required String title,
    required String subtitle,
    required int targetMillis,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }

    try {
      await _channel.invokeMethod<void>('updateHomeWidget', {
        'title': title,
        'subtitle': subtitle,
        'targetMillis': targetMillis,
      });
    } catch (_) {
      // Ignore platform channel failures outside Android widget support.
    }
  }
}
