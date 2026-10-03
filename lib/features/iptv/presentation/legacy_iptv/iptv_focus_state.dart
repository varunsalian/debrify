import 'dart:collection';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/widgets/iptv/spotlight/spotlight_live_timeline.dart';
import 'package:flutter/material.dart';

class IptvFocusState {
  final ScrollController scrollController = ScrollController();

  /// Set when a playlist switch was made from the TV source rail: once the
  /// new catalog presents, DPAD focus moves into the content pane. Moving
  /// focus off the rail is what collapses its expanded overlay (the rail
  /// stays open only while one of its chips holds focus), so this is how
  /// "pick a source → the picker collapses and the list takes over" works.
  bool focusContentAfterLoad = false;

  final FocusNode playlistFilterFocusNode = FocusNode(
    debugLabel: 'iptv-playlist-filter',
  );

  final FocusNode categoryFilterFocusNode = FocusNode(
    debugLabel: 'iptv-category-filter',
  );

  final FocusNode contentTypeFocusNode = FocusNode(
    debugLabel: 'iptv-content-type-filter',
  );

  final FocusNode spotlightCategoryOptionsFocusNode = FocusNode(
    debugLabel: 'iptv-spotlight-category-options',
  );

  final FocusNode spotlightPrimaryFocusNode = FocusNode(
    debugLabel: 'iptv-spotlight-primary-action',
  );

  final FocusScopeNode spotlightRailScope = FocusScopeNode(
    debugLabel: 'iptv-spotlight-sources',
    traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
    directionalTraversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );

  final FocusScopeNode spotlightHeroScope = FocusScopeNode(
    debugLabel: 'iptv-spotlight-hero',
    traversalEdgeBehavior: TraversalEdgeBehavior.parentScope,
  );

  final IptvSpotlightTimelineController spotlightTimelineController =
      IptvSpotlightTimelineController();

  final GlobalKey spotlightTimelineKey = GlobalKey(
    debugLabel: 'iptv-spotlight-timeline',
  );

  final Map<IptvChannel, FocusNode> cardFocusNodes = Map.identity();

  /// Channel instances whose row State has been disposed (reported via
  /// IptvChannelRow.onDetached) — the ONLY reliable "this node is detached"
  /// signal. FocusNode.context is assigned on attach and never cleared on
  /// detach (SDK focus_manager.dart), so the old `node.context == null`
  /// sweeps were dead code: nothing was ever retired, and [cardFocusNodes]
  /// leaked one FocusNode + IptvChannel per row ever scrolled — the
  /// scales-with-catalog OOM on TV. Cleared per-instance when a row is
  /// (re)built, wholesale on reload.
  final Set<IptvChannel> detachedRows = HashSet.identity();
}
