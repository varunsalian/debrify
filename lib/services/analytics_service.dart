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

  /// Emit a custom (non-well-known) event via the untyped escape hatch.
  static Future<void> track(
    String eventName, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) async {
    if (!_initialized) return;
    try {
      Pug.track(eventName, props: _normalize(properties));
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

  /// Records that the user opened a screen/page. Maps to Pug's well-known
  /// `screen_view` event (so it feeds the built-in Screen Views report).
  /// [screen] is a stable identifier (e.g. 'settings', 'cloud'); never pass
  /// content titles, search terms, or IDs.
  static void screenView(
    String screen, [
    Map<String, Object?> properties = const <String, Object?>{},
  ]) {
    _safe(
      () => Pug.track.screenView(
        screenName: screen,
        extras: _normalize(properties),
      ),
    );
  }

  /// A third-party account/provider was connected. Maps to Pug's well-known
  /// `integration_connected` event. [integrationType] is e.g. 'real_debrid',
  /// 'torbox', 'trakt'. [extras] carries only non-sensitive context.
  static void integrationConnected(
    String integrationType, [
    Map<String, Object?> extras = const <String, Object?>{},
  ]) {
    _safe(
      () => Pug.track.integrationConnected(
        integrationType: integrationType,
        extras: _normalize(extras),
      ),
    );
  }

  /// Guarded emit for the typed `Pug.track.*` well-known-event methods: no-ops
  /// until initialized and never lets an analytics failure surface to callers.
  static void _safe(void Function() emit) {
    if (!_initialized) return;
    try {
      emit();
    } catch (error, stackTrace) {
      debugPrint('AnalyticsService: emit exception: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Map<String, Object?> _normalize(Map<String, Object?> properties) {
    final normalized = <String, Object?>{};
    for (final entry in properties.entries) {
      final value = _normalizeValue(entry.value);
      if (value != null) {
        normalized[entry.key] = value;
      }
    }
    return normalized;
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
