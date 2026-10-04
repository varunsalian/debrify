import 'package:flutter/material.dart';

class CatalogDetailResources {
  final FocusNode playFocus = FocusNode(debugLabel: 'detail-play');

  final FocusNode browseFocus = FocusNode(debugLabel: 'detail-browse');

  final FocusNode watchlistFocus = FocusNode(debugLabel: 'detail-watchlist');

  /// Drives the wide/TV cinematic sheet. Needed so a D-pad "up" on the top
  /// action row can reveal the (non-focusable) eyebrow/title/meta header:
  /// focus traversal alone stops at Play/Sources and never scrolls past it.
  final ScrollController wideScroll = ScrollController();

  bool descriptionExpanded = false;
}
