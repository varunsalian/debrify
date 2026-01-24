import 'package:flutter/foundation.dart';

/// Utility to prevent DPAD "ghost taps" after dialog key actions.
/// On Android TV, DPAD "Select" generates both a KeyDownEvent AND a tap event.
/// When a dialog closes in response to the KeyDownEvent, the tap event can
/// propagate to the underlying widget and trigger unwanted actions.
class DialogTapGuard {
  static DateTime? _lastKeyActionTime;
  static const int _cooldownMs = 300;

  /// Mark that a dialog action was triggered via keyboard
  static void markKeyAction() {
    _lastKeyActionTime = DateTime.now();
    debugPrint('[DialogTapGuard] Key action marked');
  }

  /// Check if we should ignore a tap event (within cooldown after key action)
  static bool shouldIgnoreTap() {
    if (_lastKeyActionTime == null) return false;
    final elapsed = DateTime.now().difference(_lastKeyActionTime!).inMilliseconds;
    final shouldIgnore = elapsed < _cooldownMs;
    if (shouldIgnore) {
      debugPrint('[DialogTapGuard] Ignoring tap - within ${elapsed}ms of key action');
    }
    return shouldIgnore;
  }
}
