import 'package:debrify/utils/tv_search_focus_handoff.dart';
import 'package:flutter/material.dart';

class TorboxFocusState {
  final ScrollController scrollController = ScrollController();

  final ScrollController webDownloadScrollController = ScrollController();

  // TV content focus handler (stored for proper unregistration)
  VoidCallback? tvContentFocusHandler;

  // Focus nodes for TV/DPAD navigation
  final FocusNode viewModeDropdownFocusNode = FocusNode(
    debugLabel: 'torbox-view-mode',
  );

  late final FocusNode firstItemFocusNode;

  final FocusNode backButtonFocusNode = FocusNode(debugLabel: 'torbox-back');

  // Flag to focus first item after data loads (set by TV content focus handler)
  bool shouldFocusOnLoad = false;

  final FocusNode searchFocusNode = FocusNode(debugLabel: 'torbox-search');

  final FocusNode searchButtonFocusNode = FocusNode(
    debugLabel: 'torbox-search-button',
  );

  final FocusNode searchClearFocusNode = FocusNode(
    debugLabel: 'torbox-search-clear',
  );

  late final FocusNode torrentSearchFocusNode;

  final FocusNode torrentSearchClearFocusNode = FocusNode(
    debugLabel: 'torbox-torrent-search-clear',
  );

  final FocusNode torrentSearchToggleFocusNode = FocusNode(
    debugLabel: 'torbox-torrent-search-toggle',
  );

  final FocusNode deleteButtonFocusNode = FocusNode(
    debugLabel: 'torbox-delete-btn',
  );

  final TvSearchFocusHandoff torrentSearchSubmitFocus = TvSearchFocusHandoff();
}
