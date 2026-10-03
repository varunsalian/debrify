import 'package:flutter/material.dart';

import 'pikpak_catalog_state.dart';
import 'pikpak_focus_state.dart';

typedef PikpakFocusActionsDeps = ({
  PikpakFocusState focusState,
  bool Function() mounted,
  PikpakCatalogState catalogState,
});

class PikpakFocusActions {
  PikpakFocusActions(this._deps);
  final PikpakFocusActionsDeps _deps;

  /// Focus first item if data is loaded, otherwise focus add button
  void focusFirstItemOrFallback() {
    if (!_deps.focusState.shouldFocusOnLoad) return;

    // Use post-frame callback to ensure widgets are built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || !_deps.focusState.shouldFocusOnLoad) return;

      if (_deps.catalogState.files.isNotEmpty) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.firstItemFocusNode.requestFocus();
      } else if (!_deps.catalogState.isLoading) {
        // No items and not loading - focus fallback
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.addLinkButtonFocusNode.requestFocus();
      }
      // If still loading, keep the flag set - will be called again after load
    });
  }
}
