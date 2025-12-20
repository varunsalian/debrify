import 'package:flutter/material.dart';

// Helpers for tap gating
bool isInTopArea(double dy) => dy < 72.0;

bool isInBottomArea(double dy, double height) => dy > height - 72.0;

bool isInCenterRegion(Offset pos, Size size) {
  final center = Offset(size.width / 2, size.height / 2);
  const radius = 120.0; // protect center play area
  return (pos - center).distance <= radius;
}

bool shouldToggleForTap(
  Offset pos,
  Size size, {
  required bool controlsVisible,
}) {
  // If controls are hidden, allow toggling from anywhere (including center)
  if (!controlsVisible) return true;
  // If controls are visible, avoid toggling when tapping on bars or center to not fight with buttons
  if (isInTopArea(pos.dy) || isInBottomArea(pos.dy, size.height))
    return false;
  if (isInCenterRegion(pos, size)) return false;
  return true;
}
