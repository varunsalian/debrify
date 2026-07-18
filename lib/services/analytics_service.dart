import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:pug_flutter/pug_flutter.dart';

/// Thin static wrapper around the Pug analytics SDK.
///
/// Replaces the previous hand-rolled Aptabase client. Pug auto-attaches
/// system properties ($platform, $osVersion, $locale, $appVersion,
/// $deviceModel, etc.), so callers only need to pass event-specific props.
class AnalyticsService {
  static const String _projectId = 'd9dnkkaoe77s73bokkkg';
  static const String _apiKey = 'pub_75be5eff13f63f9c7c81';

  static bool _initialized = false;

  static Future<void> init() async {
    if (_initialized) return;

    try {
      await Pug.init(
        _projectId,
        PugOptions(
          apiKey: _apiKey,
          // Generous idle window: a paused movie / native-player watch should
          // not split the session. Heartbeats (see [playbackHeartbeat]) keep it
          // alive during long uninterrupted playback.
          session: const SessionConfig(idleTimeout: Duration(minutes: 45)),
          logger: kDebugMode
              ? const DebugPrintPugLogger()
              : const NoopPugLogger(),
        ),
      );
      _initialized = true;
    } catch (error, stackTrace) {
      debugPrint('AnalyticsService: Pug init failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> track(
    String eventName, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) async {
    if (!_initialized) return;

    final normalizedProps = <String, Object?>{};
    for (final entry in properties.entries) {
      final value = _normalizeValue(entry.value);
      if (value != null) {
        normalizedProps[entry.key] = value;
      }
    }

    try {
      Pug.track(eventName, props: normalizedProps);
    } catch (error, stackTrace) {
      debugPrint('AnalyticsService: track exception for "$eventName": $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static void trackInBackground(
    String eventName, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) {
    unawaited(track(eventName, properties));
  }

  /// Records that the user opened a screen/page. [screen] is a stable,
  /// human-readable identifier (e.g. 'settings', 'cloud_files'); never pass
  /// content titles, search terms, or IDs.
  static void screenView(
    String screen, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) {
    trackInBackground('screen_view', <String, Object?>{
      'screen': screen,
      ...properties,
    });
  }

  /// Records a discrete user action (e.g. 'download_started'). Keep [action]
  /// and [properties] free of anything that identifies specific content.
  static void action(
    String action, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) {
    trackInBackground(action, properties);
  }

  /// Throttled interval used to gate playback heartbeats fed from high-frequency
  /// native progress pings (see the Android TV player bridge).
  static const Duration heartbeatInterval = Duration(minutes: 4);

  /// Emitted periodically while a video is playing so the analytics session is
  /// not cut off during long, interaction-free watches (especially the native
  /// TV players, where the Flutter UI is backgrounded). [player] is one of
  /// 'dart', 'android_tv', 'torbox_tv'.
  static void playbackHeartbeat(String player) {
    trackInBackground('playback_heartbeat', <String, Object?>{
      'player': player,
    });
  }

  static String currentPlatformLabel() {
    if (kIsWeb) return 'web';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static Object? _normalizeValue(Object? value) {
    if (value == null) return null;
    if (value is String || value is num || value is bool) return value;
    return value.toString();
  }
}
