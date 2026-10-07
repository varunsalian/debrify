import 'package:flutter/material.dart';

class PremiumizeFocusState {
  final ScrollController scrollController = ScrollController();

  // TV content focus handler (stored for proper unregistration).
  VoidCallback? tvContentFocusHandler;

  bool shouldFocusOnLoad = false;

  // Focus nodes for TV/D-pad navigation.
  final FocusNode refreshButtonFocusNode = FocusNode(debugLabel: 'pm-refresh');

  final FocusNode backButtonFocusNode = FocusNode(debugLabel: 'pm-back');

  final FocusNode retryButtonFocusNode = FocusNode(debugLabel: 'pm-retry');

  final FocusNode settingsButtonFocusNode = FocusNode(
    debugLabel: 'pm-settings',
  );

  final FocusNode viewModeDropdownFocusNode = FocusNode(
    debugLabel: 'pm-view-mode',
  );

  final FocusNode addLinkButtonFocusNode = FocusNode(debugLabel: 'pm-add-link');

  final FocusNode firstItemFocusNode = FocusNode(debugLabel: 'pm-first-item');

  final FocusNode deleteButtonFocusNode = FocusNode(
    debugLabel: 'pm-delete-btn',
  );

  final FocusNode searchFocusNode = FocusNode(debugLabel: 'pm-search');

  final FocusNode searchButtonFocusNode = FocusNode(
    debugLabel: 'pm-search-button',
  );

  final FocusNode searchClearFocusNode = FocusNode(
    debugLabel: 'pm-search-clear',
  );
}
