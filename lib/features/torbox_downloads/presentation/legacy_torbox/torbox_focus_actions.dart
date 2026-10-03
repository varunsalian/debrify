import 'package:debrify/features/torbox_downloads/presentation/torbox_downloads_view.dart';
import 'package:flutter/material.dart';

import 'torbox_catalog_state.dart';
import 'torbox_focus_state.dart';
import 'torbox_view_state.dart';
import 'torbox_web_state.dart';

typedef TorboxFocusActionsDeps = ({
  TorboxFocusState focusState,
  bool Function() mounted,
  TorboxViewState viewState,
  TorboxCatalogState catalogState,
  TorboxWebState webState,
});

class TorboxFocusActions {
  TorboxFocusActions(this._deps);
  final TorboxFocusActionsDeps _deps;

  /// Focus first item if data is loaded, otherwise focus search button
  void focusFirstItemOrFallback() {
    if (!_deps.focusState.shouldFocusOnLoad) return;

    // Use post-frame callback to ensure widgets are built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || !_deps.focusState.shouldFocusOnLoad) return;

      // Check if we're in folder view
      if (_deps.viewState.currentViewNodes != null &&
          _deps.viewState.currentViewNodes!.isNotEmpty) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.firstItemFocusNode.requestFocus();
      } else if (_deps.catalogState.selectedView ==
              TorboxDownloadsView.torrents &&
          _deps.catalogState.torrents.isNotEmpty) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.firstItemFocusNode.requestFocus();
      } else if (_deps.catalogState.selectedView ==
              TorboxDownloadsView.webDownloads &&
          _deps.webState.webDownloads.isNotEmpty) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.firstItemFocusNode.requestFocus();
      } else if (!_deps.catalogState.isLoading &&
          !_deps.webState.isLoadingWebDownloads) {
        // No items and not loading - focus fallback
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.searchButtonFocusNode.requestFocus();
      }
      // If still loading, keep the flag set - will be called again after load
    });
  }
}
