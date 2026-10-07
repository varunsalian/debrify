import 'dart:async';

import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_entry.dart';
import 'package:debrify/features/iptv_spotlight_timeline/presentation/legacy_iptv_spotlight_timeline/spotlight_timeline_guide_models.dart';
import 'package:flutter/material.dart';

class SpotlightTimelineOwners {
  final FocusNode ownedFocusNode = FocusNode(
    debugLabel: 'spotlight-live-timeline',
  );

  final FocusNode nowFocusNode = FocusNode(debugLabel: 'spotlight-now');

  final ScrollController verticalController = ScrollController();

  final Map<SpotlightTimelineEntryKey, SpotlightTimelineGuideSnapshot> guides =
      {};

  final Map<SpotlightTimelineEntryKey, SpotlightTimelineLoadToken>
  pendingLoads = {};

  late DateTime windowStart;

  late bool followNow;

  late DateTime lastGuideRefreshAt;

  Timer? viewportSettle;

  Timer? clockTick;

  Timer? pointerSettle;

  int requestGeneration = 0;

  double viewportHeight = 0;

  int cursorRow = 0;

  SpotlightTimelineCursorLane cursorLane = SpotlightTimelineCursorLane.identity;

  int? selectedProgrammeStartMs;

  late int cursorTimeMs;

  bool hasFocus = false;

  (SpotlightTimelineEntryKey, int?)? lastTappedCell;
}
