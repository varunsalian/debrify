import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../utils/platform_util.dart';

/// Android Picture-in-Picture bridge for the phone media_kit player.
///
/// PiP works by shrinking the whole host Activity (MainActivity) into a
/// floating window; the media_kit Flutter texture keeps rendering as long as
/// the Activity/engine survives. Android phones only (API 26+) — Android TV
/// has its own native player and does not use phone-style PiP, and non-Android
/// platforms have no equivalent, so [isSupported] is false there.
///
/// A single active *owner* holds the PiP callbacks at any time (see [attach]):
/// PiP mode/action events only ever reach the top-most player screen, never a
/// background instance, and route replacement can't clobber the incoming
/// screen's registration.
class PipService {
  PipService._();

  static const MethodChannel _channel = MethodChannel('com.debrify.app/pip');

  static bool _handlerWired = false;
  static bool? _nativeSupported; // null until resolved from native
  static Object? _owner;
  static void Function(bool)? _onMode;
  static void Function(String)? _onAction;

  /// Cheap synchronous gate for UI: Android phone, not TV, and native has
  /// confirmed PiP capability (API >= 26 + FEATURE_PICTURE_IN_PICTURE). Returns
  /// false until [resolveSupport] has completed — callers should await that
  /// once first, then rely on this.
  static bool get isSupported =>
      Platform.isAndroid &&
      !PlatformUtil.isAndroidTvCached &&
      (_nativeSupported ?? false);

  /// Confirm PiP capability with the native side once, then cache it. Returns
  /// false immediately on non-Android / TV without a channel hop.
  static Future<bool> resolveSupport() async {
    if (!Platform.isAndroid || PlatformUtil.isAndroidTvCached) {
      _nativeSupported = false;
      return false;
    }
    if (_nativeSupported != null) return _nativeSupported!;
    try {
      _nativeSupported =
          await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      _nativeSupported = false;
    }
    return _nativeSupported!;
  }

  /// Register [owner] as the single active PiP client. A later attach replaces
  /// the previous owner, so mode/action callbacks only reach the top-most
  /// player screen. The outgoing owner (if a different, still-live screen) is
  /// told PiP is off first, so it can't be stranded with its chrome collapsed.
  static void attach(
    Object owner, {
    required void Function(bool) onMode,
    required void Function(String) onAction,
  }) {
    final previousOnMode = _onMode;
    if (previousOnMode != null && !identical(_owner, owner)) {
      previousOnMode(false);
    }
    _owner = owner;
    _onMode = onMode;
    _onAction = onAction;
    _ensureHandler();
  }

  /// Detach [owner]. Ignored when a newer owner has already taken over (so the
  /// initState-before-dispose ordering of a route replacement can't disarm the
  /// incoming screen). Disarms auto-enter when the active owner leaves.
  static void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _onMode = null;
    _onAction = null;
    unawaited(setAutoEnter(false));
  }

  /// Whether [owner] is currently the active PiP client.
  static bool isOwner(Object owner) => identical(_owner, owner);

  /// Request the activity to enter PiP now, sized to [aspectWidth]:[aspectHeight]
  /// when both are positive (native falls back to 16:9 and clamps out-of-range
  /// ratios). Returns whether the transition was accepted.
  static Future<bool> enterPip({int? aspectWidth, int? aspectHeight}) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('enterPip', {
        'aspectWidth': aspectWidth ?? 0,
        'aspectHeight': aspectHeight ?? 0,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Arm/disarm automatic PiP entry when the user leaves the app (Home button)
  /// while the player screen is on top. Native reads this on onUserLeaveHint.
  /// Optionally seeds the aspect ratio used for that automatic entry.
  static Future<void> setAutoEnter(
    bool enabled, {
    int? aspectWidth,
    int? aspectHeight,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('setAutoEnter', {
        'enabled': enabled,
        'aspectWidth': aspectWidth ?? 0,
        'aspectHeight': aspectHeight ?? 0,
      });
    } catch (_) {}
  }

  /// Tell native the current playback state (and current video aspect) so it
  /// can render the correct play/pause icon, a Next button when [hasNext], and
  /// — crucially for the Home-button auto-enter path — build the window at the
  /// right shape without waiting for a manual PiP entry to seed it.
  static Future<void> updatePlaybackState({
    required bool isPlaying,
    required bool hasNext,
    int? aspectWidth,
    int? aspectHeight,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('updatePlaybackState', {
        'isPlaying': isPlaying,
        'hasNext': hasNext,
        'aspectWidth': aspectWidth ?? 0,
        'aspectHeight': aspectHeight ?? 0,
      });
    } catch (_) {}
  }

  static void _ensureHandler() {
    if (_handlerWired) return;
    _handlerWired = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPipModeChanged':
          _onMode?.call(call.arguments as bool? ?? false);
          break;
        case 'onPipAction':
          final action = call.arguments as String? ?? '';
          if (action.isNotEmpty) _onAction?.call(action);
          break;
      }
      return null;
    });
  }
}
