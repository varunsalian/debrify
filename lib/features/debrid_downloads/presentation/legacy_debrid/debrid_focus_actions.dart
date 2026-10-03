import 'package:debrify/features/debrid_downloads/models/debrid_downloads_view.dart';
import 'package:flutter/material.dart';

import 'debrid_catalog_state.dart';
import 'debrid_download_state.dart';
import 'debrid_focus_state.dart';
import 'debrid_navigation_state.dart';

typedef DebridFocusActionsDeps = ({
  DebridFocusState focusState,
  bool Function() mounted,
  DebridNavigationState navigationState,
  DebridCatalogState catalogState,
  DebridDownloadState downloadState,
});

class DebridFocusActions {
  DebridFocusActions(this._deps);
  final DebridFocusActionsDeps _deps;

  /// Focus first item if data is loaded, otherwise focus search button
  void focusFirstItemOrFallback() {
    if (!_deps.focusState.shouldFocusOnLoad) return;

    // Use post-frame callback to ensure widgets are built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || !_deps.focusState.shouldFocusOnLoad) return;

      // Check if we're in folder view
      if (_deps.navigationState.currentViewNodes != null &&
          _deps.navigationState.currentViewNodes!.isNotEmpty) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.firstItemFocusNode.requestFocus();
      } else if (_deps.catalogState.selectedView ==
              DebridDownloadsView.torrents &&
          _deps.catalogState.torrents.isNotEmpty) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.firstItemFocusNode.requestFocus();
      } else if (_deps.catalogState.selectedView == DebridDownloadsView.ddl &&
          _deps.downloadState.downloads.isNotEmpty) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.firstItemFocusNode.requestFocus();
      } else if (!_deps.catalogState.isLoadingTorrents &&
          !_deps.downloadState.isLoadingDownloads &&
          !_deps.navigationState.isLoadingFolder) {
        // No items and not loading - focus fallback
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.searchButtonFocusNode.requestFocus();
      }
      // If still loading, keep the flag set - will be called again after load
    });
  }
}
