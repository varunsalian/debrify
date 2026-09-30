import 'package:flutter/widgets.dart';
import '../../../models/torrent.dart';
import '../application/keyword_results_controller.dart';

typedef KeywordSelectionDeps = ({
  bool Function() mounted,
  KeywordResultsController Function() controller,
  List<FocusNode> Function() toolbarNodes,
  VoidCallback freezeAndAdopt,
});

/// Selection mutations and toolbar return focus for Keyword results.
class KeywordSelection {
  KeywordSelection(this._deps);
  final KeywordSelectionDeps _deps;
  void enterKwSelection() {
    // Multi-select over a live-shifting list would let rows move under the
    // checkmarks — freeze and fold parked arrivals in first.
    _deps.freezeAndAdopt();
    // Entering selection swaps the toolbar to 3 pills; if DPAD focus was on the
    // now-gone "Select" pill (index 3), pull it back to the new first pill so
    // the remote doesn't lose focus.
    final refocusToolbar = _deps.toolbarNodes().any((n) => n.hasFocus);
    _deps.controller().setSelectionMode(true);
    if (refocusToolbar) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_deps.mounted()) _deps.toolbarNodes().first.requestFocus();
      });
    }
  }

  void exitKwSelection() {
    _deps.controller().setSelectionMode(false);
  }

  void toggleKwSelection(Torrent t) =>
      _deps.controller().toggleSelection(t.infohash);

  void selectAllKw() => _deps.controller().selectAll();

  /// Clear the selection but stay in selection mode (matches Home's "None").
  void deselectAllKw() => _deps.controller().deselectAll();
}
