import 'dart:async';

import 'package:flutter/services.dart';

import '../utils/platform_util.dart';

/// What the recognizer is doing right now, as far as the UI cares.
enum TvVoicePhase {
  /// Session opened, engine not listening yet (service bind, model warm-up).
  starting,

  /// Microphone is live and waiting for words.
  listening,

  /// Words are actually arriving.
  hearing,

  /// User stopped talking; the engine is turning audio into text.
  processing,
}

/// One event from the native recognizer.
class TvVoiceEvent {
  const TvVoiceEvent._(this.type, {this.text, this.level, this.code, this.message});

  factory TvVoiceEvent._from(dynamic raw) {
    final map = (raw as Map?) ?? const {};
    return TvVoiceEvent._(
      map['type'] as String? ?? 'unknown',
      text: map['text'] as String?,
      level: (map['db'] as num?)?.toDouble(),
      code: (map['code'] as num?)?.toInt(),
      message: map['message'] as String?,
    );
  }

  /// One of: ready, speech, level, partial, processing, result, error, aborted.
  final String type;

  /// Transcript so far (`partial`) or final (`result`).
  final String? text;

  /// Microphone loudness in dB, roughly -2..10 in practice (`level`).
  final double? level;

  /// Platform [SpeechRecognizer] error constant (`error`), or -1 for ours.
  final int? code;
  final String? message;
}

/// Voice dictation for the in-app TV keyboard.
///
/// Records IN-APP via the platform `SpeechRecognizer` service rather than
/// launching `ACTION_RECOGNIZE_SPEECH`. The intent route was tried first and
/// dropped: it throws a full-screen system voice UI (its own text box) over the
/// Debrify keyboard, pauses our activity — firing every lifecycle handler,
/// trailer and playback included — and returns nothing until it's over. Binding
/// the recognition service keeps the whole interaction inside our own keyboard
/// panel: live partial words, a level meter, and no foreign UI at all.
///
/// The cost is a `RECORD_AUDIO` grant (asked on the first mic press, never at
/// start-up) and the fact that on some TV hardware the *remote's* mic is wired
/// only to the system voice service — where that's true, in-app capture hears
/// the panel mic or nothing. Availability is still probed, and the mic key
/// stays hidden when the device has no recognizer at all.
class TvVoiceInput {
  TvVoiceInput._();

  static const MethodChannel _channel = MethodChannel('debrify/tv_voice');
  static const EventChannel _eventChannel = EventChannel(
    'debrify/tv_voice_events',
  );

  static bool? _available;
  static Stream<dynamic>? _rawEvents;

  /// Recognizer output: partials, levels, the final transcript, errors.
  ///
  /// The channel stream is built once and re-listened per dictation: the
  /// native side arms its sink on the first listener and drops it on the last,
  /// and callers subscribe BEFORE [start] so the sink is always live while a
  /// session runs. (A fresh `receiveBroadcastStream()` per call would leave
  /// two stream instances fighting over that one sink.)
  static Stream<TvVoiceEvent> get events =>
      (_rawEvents ??= _eventChannel.receiveBroadcastStream())
          .map(TvVoiceEvent._from);

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

  /// Ensures the microphone grant, showing the system dialog if needed. False
  /// means the user declined (or the platform refused) — the caller should
  /// leave the keyboard exactly as it was and say why.
  static Future<bool> ensurePermission() async {
    try {
      return await _channel.invokeMethod<bool>('ensurePermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the microphone. Results arrive on [events], never here.
  /// [locale] is a BCP-47 tag; null uses the device's recognition default.
  static Future<bool> start({String? locale}) async {
    try {
      await _channel.invokeMethod('start', {'locale': locale});
      return true;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// "I'm done talking" — the engine transcribes what it already heard and a
  /// `result` event still follows.
  static Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } on PlatformException {
      // Nothing listening; nothing to do.
    } on MissingPluginException {
      // ditto
    }
  }

  /// Throw the session away. No `result` event follows a cancel.
  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod('cancel');
    } on PlatformException {
      // ditto
    } on MissingPluginException {
      // ditto
    }
  }

  /// Human-readable reason for an `error` event, for the keyboard's status
  /// line. Codes are `android.speech.SpeechRecognizer.ERROR_*`.
  static String describeError(int? code) => switch (code) {
    1 || 2 => 'Network problem — try again',
    3 => "Couldn't reach the microphone",
    4 => 'Speech service error',
    5 => 'Speech service error',
    6 => "Didn't hear anything",
    7 => "Didn't catch that",
    8 => 'Microphone busy — try again',
    9 => 'Microphone permission needed',
    _ => "Voice input isn't working here",
  };
}
