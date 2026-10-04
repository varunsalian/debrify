import 'package:flutter/material.dart';

class SpotlightBoardNavigationState {
  int row = -1; // -1 = the hero owns the cursor

  final Map<int, int> col = {};

  /// A DOWN at the last loaded shelf owns the catalog fetch until it settles.
  /// While true, repeated key events cannot start duplicate loads and the
  /// board paints a visible acknowledgement instead of looking exhausted.
  bool loadingMoreShelves = false;

  ({FocusNode origin, DateTime at})? pendingProgressiveDown;
}
