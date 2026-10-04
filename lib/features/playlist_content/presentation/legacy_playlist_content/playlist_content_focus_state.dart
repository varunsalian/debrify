import 'package:flutter/material.dart';

class PlaylistContentFocusState {
  // Focus management for TV navigation
  final FocusNode viewModeDropdownFocusNode = FocusNode(
    debugLabel: 'playlist-view-mode-dropdown',
  );

  final FocusNode backButtonFocusNode = FocusNode(
    debugLabel: 'playlist-back-button',
  );

  final FocusNode searchFocusNode = FocusNode(debugLabel: 'playlist-search');

  final FocusNode searchButtonFocusNode = FocusNode(
    debugLabel: 'playlist-search-button',
  );

  final FocusNode searchClearFocusNode = FocusNode(
    debugLabel: 'playlist-search-clear',
  );
}
