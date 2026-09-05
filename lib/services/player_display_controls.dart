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

  Future<void> setWakelock(bool enabled) async {
    try {
      await _toggleWakelock(enabled);
    } catch (_) {
      // Keep playback usable when the OS cannot provide a wake lock.
    }
  }
}
