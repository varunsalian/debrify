import 'dart:io';

import 'package:flutter/services.dart';

/// Announces the phone player's audio session to system audio-effect apps
/// (Wavelet, OEM equalizers, Dolby/DTS) so they can attach to our playback.
///
/// Android only — no other platform has this concept. Every call fails soft:
/// audio effects are a nice-to-have and must never block or break playback.
///
/// Pairing matters. An OPEN without a matching CLOSE leaves effect apps
/// attached to a session that no longer plays anything, which degrades *other*
/// apps' equalizers — worse than the problem this fixes. The native side keeps
/// a single open session and closes the previous one on each open, but callers
/// should still close explicitly when playback ends.
class AudioEffectSessionService {
  AudioEffectSessionService._();

  static const MethodChannel _channel = MethodChannel(
    'com.debrify.app/audio_effects',
  );

  static bool get isSupported => Platform.isAndroid;

  /// Reserve a session id from the framework, or null if unavailable. The
  /// caller pins this into the player so the announced id is the one audio
  /// actually comes out on.
  static Future<int?> generateSessionId() async {
    if (!isSupported) return null;
    try {
      final id = await _channel.invokeMethod<int>('generateSessionId');
      return (id == null || id == 0) ? null : id;
    } catch (_) {
      return null;
    }
  }

  /// Announce [sessionId] as active so effect apps attach to it.
  static Future<void> open(int sessionId) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('open', {'sessionId': sessionId});
    } catch (_) {
      // Ignored — playback is unaffected.
    }
  }

  /// Release [sessionId] so effect apps detach.
  static Future<void> close(int sessionId) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('close', {'sessionId': sessionId});
    } catch (_) {
      // Ignored — playback is unaffected.
    }
  }
}
