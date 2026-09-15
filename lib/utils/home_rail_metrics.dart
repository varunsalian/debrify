import 'package:flutter/widgets.dart';

/// Poster width of a Home board rail card — the single source for every
/// surface that must look like a Home row (the board itself, collection
/// folder rails).
double homeRailPosterWidth(BuildContext context, {
  required bool isTelevision,
  bool searchResults = false,
}) {
  if (!isTelevision) {
    return MediaQuery.sizeOf(context).width >= 900 ? 162.0 : 118.0;
  }
  final height = MediaQuery.sizeOf(context).height;
  return searchResults
      ? (height * 0.225).clamp(120.0, 180.0)
      : (height * 0.17).clamp(92.0, 140.0);
}
