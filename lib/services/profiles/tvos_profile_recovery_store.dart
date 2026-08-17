import 'package:flutter/services.dart';

import '../../utils/platform_util.dart';

/// Durable tvOS authority for bounded profile/security configuration.
/// SQLite and files under Library/Caches are projections of this envelope.
class TvOsProfileRecoveryStore {
  TvOsProfileRecoveryStore._();

  static const MethodChannel _channel = MethodChannel(
    'debrify/tvos_profile_recovery',
  );

  static bool get supported => PlatformUtil.isTvOS;

  static Future<void> Function()? checkpointCallback;

  static Future<void> checkpointPreferenceMutation() async {
    if (!supported) return;
    final callback = checkpointCallback;
    if (callback == null) {
      throw StateError('tvOS recovery checkpoint is unavailable');
    }
    await callback();
  }

  static Future<String?> read() async {
    if (!supported) return null;
    return _channel.invokeMethod<String>('read');
  }

  static Future<void> publish(String envelope) async {
    if (!supported) return;
    if (envelope.length > 768 * 1024) {
      throw StateError('tvOS recovery envelope exceeds the bounded limit');
    }
    final ok = await _channel.invokeMethod<bool>('publish', envelope);
    if (ok != true) throw StateError('tvOS recovery publication failed');
  }

  static Future<void> clear() async {
    if (supported) await _channel.invokeMethod<void>('clear');
  }
}
