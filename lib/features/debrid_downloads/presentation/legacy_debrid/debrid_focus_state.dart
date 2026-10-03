import 'package:debrify/utils/tv_search_focus_handoff.dart';
import 'package:flutter/material.dart';

class DebridFocusState {
  VoidCallback? tvContentFocusHandler;

  final ScrollController torrentScrollController = ScrollController();

  final ScrollController downloadScrollController = ScrollController();

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

  bool shouldFocusOnLoad = false;

  final FocusNode searchFocusNode = FocusNode(debugLabel: 'rd-search');

  final FocusNode searchButtonFocusNode = FocusNode(
    debugLabel: 'rd-search-button',
  );

  final FocusNode searchClearFocusNode = FocusNode(
    debugLabel: 'rd-search-clear',
  );

  late final FocusNode torrentSearchFocusNode;

  final FocusNode torrentSearchClearFocusNode = FocusNode(
    debugLabel: 'rd-torrent-search-clear',
  );
}
