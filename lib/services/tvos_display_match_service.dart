import 'package:flutter/services.dart';

import '../models/content_display_match_mode.dart';

/// Publishes MediaKit's decoded source format to tvOS Match Content.
///
/// AVDisplayManager remains the authority: calls can succeed while the user
/// has Match Content disabled, and tvOS may keep its configured resolution.
abstract final class TvosDisplayMatchService {
  static const MethodChannel _channel = MethodChannel(
    'debrify/tvos_display_match',
  );

  static Future<Map<Object?, Object?>> apply({
    required ContentDisplayMatchMode mode,
    required int width,
    required int height,
    required double refreshRate,
    String? codec,
  }) async {
    if (!mode.requestsMatching) {
      await clear();
      return const <Object?, Object?>{};
    }
    final result = await _channel.invokeMapMethod<Object?, Object?>('apply', {
      'width': width,
      'height': height,
      'refreshRate': refreshRate,
      'matchResolution': mode.matchesResolution,
      if (codec != null && codec.isNotEmpty) 'codec': codec,
    });
    return result ?? const <Object?, Object?>{};
  }

  static Future<void> clear() => _channel.invokeMethod<void>('clear');
}
