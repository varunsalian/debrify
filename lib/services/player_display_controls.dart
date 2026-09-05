import 'package:flutter/foundation.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../utils/platform_util.dart';

/// Optional native display controls must not interrupt playback or teardown.
class PlayerDisplayControls {
  PlayerDisplayControls({
    Future<double> Function()? readBrightness,
    Future<void> Function(double)? writeBrightness,
    Future<void> Function()? resetBrightness,
    Future<void> Function(bool)? toggleWakelock,
  }) : _readBrightness =
           readBrightness ?? (() => ScreenBrightness().application),
       _writeBrightness =
           writeBrightness ??
           ((value) =>
               ScreenBrightness().setApplicationScreenBrightness(value)),
       _resetBrightness =
           resetBrightness ??
           (() => ScreenBrightness().resetApplicationScreenBrightness()),
       _toggleWakelock =
           toggleWakelock ??
           ((enabled) => WakelockPlus.toggle(enable: enabled));

  static final instance = PlayerDisplayControls();
  final Future<double> Function() _readBrightness;
  final Future<void> Function(double) _writeBrightness;
  final Future<void> Function() _resetBrightness;
  final Future<void> Function(bool) _toggleWakelock;

  static bool get supportsBrightness =>
      !kIsWeb &&
      !PlatformUtil.isTvOS &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
      }.contains(defaultTargetPlatform);

  Future<double> brightness() async {
    if (!supportsBrightness) return 0.5;
    try {
      return await _readBrightness();
    } catch (_) {
      return 0.5;
    }
  }

  Future<void> setBrightness(double value) async {
    if (!supportsBrightness) return;
    try {
      await _writeBrightness(value);
    } catch (_) {
      // Optional control: the display or plugin may reject the operation.
    }
  }

  Future<void> resetBrightness() async {
    if (!supportsBrightness) return;
    try {
      await _resetBrightness();
    } catch (_) {
      // Teardown must also handle asynchronously reported native failures.
    }
  }

  final Set<Object> _wakeOwners = <Object>{};
  bool _playbackWantsWake = false;
  Future<void> _wakeWrites = Future<void>.value();

  Future<void> setWakelock(bool enabled) {
    _playbackWantsWake = enabled;
    return _updateWakelock();
  }

  /// Independent foreground operations must not release playback's wake lock.
  Future<void> setWakelockOwner(Object owner, bool enabled) {
    if (enabled) {
      _wakeOwners.add(owner);
    } else {
      _wakeOwners.remove(owner);
    }
    return _updateWakelock();
  }

  Future<void> _updateWakelock() {
    _wakeWrites = _wakeWrites.then((_) async {
      try {
        await _toggleWakelock(_playbackWantsWake || _wakeOwners.isNotEmpty);
      } catch (_) {
        // Native display controls are optional; never fail the operation.
      }
    });
    return _wakeWrites;
  }
}
