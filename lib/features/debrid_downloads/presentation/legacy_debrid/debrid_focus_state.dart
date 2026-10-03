import 'package:debrify/utils/tv_search_focus_handoff.dart';
import 'package:flutter/material.dart';

class DebridFocusState {
  // TV content focus handler (stored for proper unregistration)
  VoidCallback? tvContentFocusHandler;

  final ScrollController torrentScrollController = ScrollController();

  final ScrollController downloadScrollController = ScrollController();

  // TV/DPAD navigation
  final FocusNode backButtonFocusNode = FocusNode(debugLabel: 'rd-back');

  final FocusNode refreshButtonFocusNode = FocusNode(debugLabel: 'rd-refresh');

  final FocusNode viewModeDropdownFocusNode = FocusNode(
    debugLabel: 'rd-view-mode',
  );

  late final FocusNode firstItemFocusNode;

  final FocusNode deleteButtonFocusNode = FocusNode(
    debugLabel: 'rd-delete-btn',
  );

  final TvSearchFocusHandoff torrentSearchSubmitFocus = TvSearchFocusHandoff();

  // Flag to focus first item after data loads (set by TV content focus handler)
  bool shouldFocusOnLoad = false;

  final FocusNode searchFocusNode = FocusNode(debugLabel: 'rd-search');

  final FocusNode searchButtonFocusNode = FocusNode(
    debugLabel: 'rd-search-button',
  );

  final FocusNode searchClearFocusNode = FocusNode(
    debugLabel: 'rd-search-clear',
  );

  // Focus nodes for torrent search DPAD navigation
  late final FocusNode torrentSearchFocusNode;

  final FocusNode torrentSearchClearFocusNode = FocusNode(
    debugLabel: 'rd-torrent-search-clear',
  );
}
