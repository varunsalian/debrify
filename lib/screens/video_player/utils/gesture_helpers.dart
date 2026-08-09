import 'package:flutter/material.dart';

// Helpers for tap gating
bool isInTopArea(double dy) => dy < 72.0;

/// [bottomBar] is the dock's occupied band. Defaults to the legacy 72lp, which
/// is what `classic` always passes; the styled dock's height is variable, so
/// it passes a measured value instead.
bool isInBottomArea(double dy, double height, [double bottomBar = 72.0]) =>
    dy > height - bottomBar;

bool isInCenterRegion(Offset pos, Size size) {
  final center = Offset(size.width / 2, size.height / 2);
  const radius = 120.0; // protect center play area
  return (pos - center).distance <= radius;
}

bool shouldToggleForTap(
  Offset pos,
  Size size, {
  required bool controlsVisible,
  double bottomBar = 72.0,
}) {
  // If controls are hidden, allow toggling from anywhere (including center)
  if (!controlsVisible) return true;
  // If controls are visible, avoid toggling when tapping on bars or center to not fight with buttons
  if (isInTopArea(pos.dy) || isInBottomArea(pos.dy, size.height, bottomBar)) {
    return false;
  }
  if (isInCenterRegion(pos, size)) return false;
  return true;
}
