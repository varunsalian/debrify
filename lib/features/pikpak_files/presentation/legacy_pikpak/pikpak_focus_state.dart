import 'package:flutter/material.dart';

// TV content focus handler (stored for proper unregistration)
// Focus nodes for TV/DPAD navigation
// Flag to focus first item after data loads (set by TV content focus handler)
class PikpakFocusState {
  final ScrollController scrollController = ScrollController();

  VoidCallback? tvContentFocusHandler;

  final FocusNode refreshButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-refresh',
  );

  final FocusNode backButtonFocusNode = FocusNode(debugLabel: 'pikpak-back');

  final FocusNode retryButtonFocusNode = FocusNode(debugLabel: 'pikpak-retry');

  final FocusNode settingsButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-settings',
  );

  final FocusNode viewModeDropdownFocusNode = FocusNode(
    debugLabel: 'pikpak-view-mode',
  );

  final FocusNode addLinkButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-add-link',
  );

  final FocusNode firstItemFocusNode = FocusNode(
    debugLabel: 'pikpak-first-item',
  );

  bool shouldFocusOnLoad = false;

  final FocusNode deleteButtonFocusNode = FocusNode(
    debugLabel: 'pikpak-delete-btn',
  );
}
