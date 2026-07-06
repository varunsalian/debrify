import 'package:flutter/material.dart';

/// Deterministic vivid accent colour derived from a string (channel/author
/// name). Gives every card a stable, distinct tint so a wall of mismatched
/// logos reads as curated rather than random — without decoding the image.
///
/// Same seed always yields the same colour; the hue is spread across the wheel
/// while saturation/lightness stay in a band that's legible on the dark ground.
Color brandAccentFor(String seed) {
  var hash = 0;
  for (final unit in seed.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(1.0, hue, 0.60, 0.64).toColor();
}
