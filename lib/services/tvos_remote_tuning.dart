import 'package:flutter_tvos/flutter_tvos.dart';

import '../utils/platform_util.dart';

/// Debrify's app-wide Siri Remote tuning.
///
/// The engine defaults enter continuous navigation after only three touchpad
/// move samples and then repeat every 80 ms. On a physical Siri Remote that
/// makes a short swipe overshoot several focus targets and lets small movement
/// during a click turn into navigation. These values require a more deliberate
/// gesture and keep held navigation useful without racing through the UI.
abstract final class TvosRemoteTuning {
  static const config = TvRemoteConfig(
    shortSwipeThreshold: 0.45,
    fastSwipeThreshold: 0.70,
    dpadDeadZone: 0.72,
    continuousSwipeMoveThreshold: 6,
    keyRepeatInitialDelay: Duration(milliseconds: 500),
    keyRepeatInterval: Duration(milliseconds: 140),
  );

  /// Installs the tuning once the Flutter binding exists. No-op off tvOS.
  static void install() {
    if (!PlatformUtil.isTvOS) return;
    final controller = TvRemoteController.instance;
    controller.config = config;
    controller.init();
  }
}
