import 'package:flutter/services.dart';

import '../utils/platform_util.dart';

/// Voice dictation for the in-app TV keyboard.
///
/// Uses the SYSTEM speech recognizer (`ACTION_RECOGNIZE_SPEECH`) rather than
/// recording in-app, deliberately: on most Android TV devices the remote's
/// microphone is owned by the system voice service, so an app doing its own
/// capture gets the panel's mic (if any) or nothing at all. Handing the intent
/// to the system also means no RECORD_AUDIO permission, no recording
/// lifecycle, and the overlay users already know from their TV.
///
/// The trade-off is that launching it PAUSES this activity — the caller must
/// expect the app's lifecycle handlers (trailer pause, playback pause) to fire
/// and focus to need restoring on return. [TvTextField] handles that.
///
/// Availability is NOT assumed: plenty of cheap AOSP boxes (and Fire TV) ship
/// no recognizer at all, so [isAvailable] is probed once and the mic key stays
/// hidden when it comes back false — a dead mic button is worse than none.
class TvVoiceInput {
  TvVoiceInput._();

  static const MethodChannel _channel = MethodChannel('debrify/tv_voice');

  static bool? _available;

  /// Whether this device can dictate. Probed once per process (the answer can
  /// only change with an app/package install, which restarts us anyway).
  /// Always false off Android TV — phones and desktops have real IMEs with
  /// their own voice keys, so the in-app keyboard's mic is TV-only.
  static Future<bool> isAvailable() async {
    if (_available != null) return _available!;
    if (!PlatformUtil.isAndroidTvCached) {
      _available = false;
      return false;
    }
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      _available = ok ?? false;
    } on PlatformException {
      _available = false;
    } on MissingPluginException {
      _available = false;
    }
    return _available!;
  }

  /// Synchronous mirror of the last [isAvailable] probe, for build methods.
  /// Null until the probe lands (callers should treat null as "not yet").
  static bool? get availableCached => _available;

  /// Launch the system recognizer and return what the user said, or null when
  /// they cancelled / nothing was recognised / the device refused. [prompt] is
  /// the hint the system overlay shows.
  static Future<String?> listen({String prompt = 'Speak to search'}) async {
    if (!await isAvailable()) return null;
    try {
      final text = await _channel.invokeMethod<String>('listen', {
        'prompt': prompt,
      });
      final trimmed = text?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
