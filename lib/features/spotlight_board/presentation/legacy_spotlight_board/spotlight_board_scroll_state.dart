import 'package:debrify/features/spotlight_board/presentation/spotlight_board_metrics.dart';
import 'package:flutter/material.dart';

class SpotlightBoardScrollState {
  SpotlightBoardMetrics? lastMetrics;

  final ScrollController scroll = ScrollController();

  /// The hero band's height as of the last build — the scroll listener needs
  /// it to decide "scrolled away", and a listener has no BuildContext to
  /// measure with.
  double heroBandH = 0;

  /// Lazy-list extent estimates can change during scrolling. Refresh only
  /// the veil when metrics change, never the board and its mounted shelves.
  double lastMaxExtent = -1;

  final veilMetricsRevision = ValueNotifier<int>(0);
}
