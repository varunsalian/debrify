// Device-wide persistence for [RecordingOutputSettings].
//
// Goes through DevicePreferences, the reviewed unscoped store: the key is
// registered in DevicePreferences.allowedKeys and both profile device-key
// lists. Native Kotlin reads the same value as `flutter.recording_output_v1`.

import 'package:debrify/services/profiles/profile_preferences.dart';

import '../models/recording_output_settings.dart';

/// Stores the one recording-output preference and mirrors it for synchronous
/// reads. [read] is primed once at scheduler init; widgets and schedulers
/// then read [cached] instead of awaiting storage during a build or a timer.
final class RecordingOutputStore {
  const RecordingOutputStore._();

  /// Device-wide key, read by Kotlin as `flutter.recording_output_v1`.
  static const String key = 'recording_output_v1';

  /// Updated by [read] and [write]; defaults before either has run.
  static RecordingOutputSettings cached = const RecordingOutputSettings();

  static Future<RecordingOutputSettings> read() async {
    final prefs = await DevicePreferences.instance();
    final settings = RecordingOutputSettings.decode(prefs.getString(key));
    cached = settings;
    return settings;
  }

  static Future<void> write(RecordingOutputSettings settings) async {
    cached = settings;
    final prefs = await DevicePreferences.instance();
    await prefs.setString(key, settings.encode());
  }
}
