import 'dart:ui' show Size;
import 'package:flutter/foundation.dart' show TargetPlatform;

class IptvLayoutPolicy {
  static const double tabletTwoPaneMinWidth = 900;

  static const double tabletTwoPaneMinHeight = 500;

  static bool shouldUseTouchTabletTwoPane({
    required bool isTelevision,
    required bool isWeb,
    required TargetPlatform platform,
    required Size availableSize,
  }) {
    final touchPlatform =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    return !isTelevision &&
        !isWeb &&
        touchPlatform &&
        availableSize.width >= tabletTwoPaneMinWidth &&
        availableSize.height >= tabletTwoPaneMinHeight;
  }
}
