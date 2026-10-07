import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_focus_state.dart';

typedef PremiumizeFocusActionsDeps = ({
  PremiumizeFocusState focusState,
  bool Function() mounted,
  PremiumizeCatalogState catalogState,
});

class PremiumizeFocusActions {
  PremiumizeFocusActions(this._deps);
  final PremiumizeFocusActionsDeps _deps;

  void focusFirstItemOrFallback() {
    if (!_deps.focusState.shouldFocusOnLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || !_deps.focusState.shouldFocusOnLoad) return;
      if (_deps.catalogState.items.isNotEmpty) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.firstItemFocusNode.requestFocus();
      } else if (!_deps.catalogState.isLoading) {
        _deps.focusState.shouldFocusOnLoad = false;
        _deps.focusState.addLinkButtonFocusNode.requestFocus();
      }
    });
  }
}
