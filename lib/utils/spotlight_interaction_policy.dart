import 'package:flutter/widgets.dart';

/// A landscape phone is still a phone; a narrow desktop window stays compact.
bool spotlightUsesRichCards({
  required Size viewport,
  required TargetPlatform platform,
  double? availableWidth,
  bool dpad = false,
}) {
  if (dpad) return true;
  if ((availableWidth ?? viewport.width) < 600) return false;
  final desktop =
      platform == TargetPlatform.macOS ||
      platform == TargetPlatform.windows ||
      platform == TargetPlatform.linux;
  return desktop || viewport.shortestSide >= 600;
}
