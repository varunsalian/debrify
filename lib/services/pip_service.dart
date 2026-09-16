import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../utils/platform_util.dart';

/// Picture-in-Picture bridge for Android phones and the iOS media_kit player.
/// Android presents the activity; iOS presents frames through AVKit.
/// A single active *owner* holds the PiP callbacks at any time (see [attach]):
/// PiP mode/action events only ever reach the top-most player screen, never a
/// background instance, and route replacement can't clobber the incoming
/// screen's registration.
class PipService {
  PipService._();

  static const MethodChannel _channel = MethodChannel('com.debrify.app/pip');

  @visibleForTesting
  static TargetPlatform? debugPlatform;
  static bool get _isIOS => (debugPlatform == null
      ? Platform.isIOS
      : debugPlatform == TargetPlatform.iOS);
  static bool get _isAndroid => (debugPlatform == null
      ? Platform.isAndroid
      : debugPlatform == TargetPlatform.android);
  static bool get _eligible =>
      (_isIOS && !PlatformUtil.isTvOS) ||
      (_isAndroid && !PlatformUtil.isAndroidTvCached);

  static bool _handlerWired = false;
  static bool? _nativeSupported; // null until resolved from native
  static Object? _owner;
  static String? _iosPlayerHandle;
  static void Function(bool)? _onMode;
  static void Function(String)? _onAction;
  static Future<bool> Function()? _onRestore;

  /// Cheap synchronous gate for UI: Android phone, not TV, and native has
  /// confirmed PiP capability (API >= 26 + FEATURE_PICTURE_IN_PICTURE). Returns
  /// false until [resolveSupport] has completed — callers should await that
  /// once first, then rely on this.
  static bool get isSupported => _eligible && (_nativeSupported ?? false);

  /// Confirm PiP capability with the native side once, then cache it. Returns
  /// false immediately on non-Android / TV without a channel hop.
  static Future<bool> resolveSupport() async {
    if (!_eligible) {
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
    Future<bool> Function()? onRestore,
  }) {
    final previousOnMode = _onMode;
    final previousOwner = _owner;
    if (_isIOS && previousOwner != null && !identical(previousOwner, owner)) {
      detach(previousOwner);
    }
    if (previousOnMode != null && !identical(previousOwner, owner)) {
      previousOnMode(false);
    }
    _owner = owner;
    _onMode = onMode;
    _onAction = onAction;
    _onRestore = onRestore;
    _ensureHandler();
  }

  /// Detach [owner]. Ignored when a newer owner has already taken over (so the
  /// initState-before-dispose ordering of a route replacement can't disarm the
  /// incoming screen). Disarms auto-enter when the active owner leaves.
  static void detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _iosPlayerHandle = null;
    _onMode = null;
    _onAction = null;
    _onRestore = null;
    unawaited(setAutoEnter(false));
    if (_isIOS && isSupported) {
      unawaited(
        _channel.invokeMethod<void>('detach').catchError((Object _) {}),
      );
    }
  }

  /// Whether [owner] is currently the active PiP client.
  static bool isOwner(Object owner) => identical(_owner, owner);

  /// Request the activity to enter PiP now, sized to [aspectWidth]:[aspectHeight]
  /// when both are positive (native falls back to 16:9 and clamps out-of-range
  /// ratios). Returns whether the transition was accepted.
  static Future<bool> enterPip({
    int? aspectWidth,
    int? aspectHeight,
    int? playerHandle,
  }) async {
    if (!isSupported) return false;
    try {
      if (_isIOS) _iosPlayerHandle = playerHandle?.toString();
      final ok = await _channel.invokeMethod<bool>('enterPip', {
        if (_isIOS) 'playerHandle': playerHandle?.toString(),
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
    int? positionMs,
    int? durationMs,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod('updatePlaybackState', {
        'isPlaying': isPlaying,
        'hasNext': hasNext,
        if (_isIOS) 'positionMs': positionMs ?? 0,
        if (_isIOS) 'durationMs': durationMs ?? 0,
        'aspectWidth': aspectWidth ?? 0,
        'aspectHeight': aspectHeight ?? 0,
      });
    } catch (_) {}
  }

  @visibleForTesting
  static void resetForTesting() {
    _owner = null;
    _iosPlayerHandle = null;
    _onMode = null;
    _onAction = null;
    _onRestore = null;
    _nativeSupported = null;
    _handlerWired = false;
    debugPlatform = null;
    _channel.setMethodCallHandler(null);
  }

  static void _ensureHandler() {
    if (_handlerWired) return;
    _handlerWired = true;
    _channel.setMethodCallHandler((call) async {
      dynamic value = call.arguments;
      if (_isIOS) {
        if (value is! Map ||
            _iosPlayerHandle == null ||
            value['playerHandle'] != _iosPlayerHandle)
          return null;
        value = value['value'];
      }
      switch (call.method) {
        case 'onPipRestore':
          return await _onRestore?.call() ?? false;
        case 'onPipModeChanged':
          _onMode?.call(value as bool? ?? false);
          break;
        case 'onPipAction':
          final action = value as String? ?? '';
          if (action.isNotEmpty) _onAction?.call(action);
          break;
      }
      return null;
    });
  }
}
