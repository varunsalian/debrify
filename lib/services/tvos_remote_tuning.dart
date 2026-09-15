import 'package:flutter_tvos/flutter_tvos.dart';

import '../utils/platform_util.dart';

/// Debrify's app-wide Siri Remote tuning.
///
/// Uses the flutter_tvos publisher's tuning example:
/// https://pub.dev/packages/flutter_tvos#tuning
/// This is a starting point for physical-device validation, not an Apple
/// standard. The previous six-sample / 140 ms configuration felt sluggish.
abstract final class TvosRemoteTuning {
  static const config = TvRemoteConfig(
    shortSwipeThreshold: 0.4,
    fastSwipeThreshold: 0.6,
    dpadDeadZone: 0.6,
    continuousSwipeMoveThreshold: 4,
    keyRepeatInitialDelay: Duration(milliseconds: 450),
    keyRepeatInterval: Duration(milliseconds: 100),
  );

  /// Installs the tuning once the Flutter binding exists. No-op off tvOS.
  static void install() {
    if (!PlatformUtil.isTvOS) return;
    final controller = TvRemoteController.instance;
    controller.config = config;
    controller.init();
  }
}
