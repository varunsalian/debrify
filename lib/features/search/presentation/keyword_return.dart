import 'package:flutter/widgets.dart';

import '../application/keyword_result_snapshot.dart';
import '../data/keyword_snapshot_repository.dart';
import '../models/keyword_snapshot.dart';
import '../models/search_mode.dart';
import 'keyword_focus_controller.dart';
import 'keyword_viewport.dart';
import 'search_result_bindings.dart';

typedef KeywordReturnDeps = ({
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() keywordAllowed,
  String Function() variant,
  SearchMode Function() mode,
  void Function(SearchMode) setMode,
  KeywordSnapshotRepository Function() repository,
  SearchResultBindings Function() bindings,
  KeywordFocusController Function() focus,
  VoidCallback syncTabs,
});

/// Completed-search handoff; the repository retains profile and variant ownership.
class KeywordReturn {
  KeywordReturn(this._deps, this._searchController, this._viewport);
  final KeywordReturnDeps _deps;
  final TextEditingController _searchController;
  final KeywordViewport _viewport;

  /// Consume the borrowed snapshot once, before constructing providers. Seed
  /// their initial state instead of mutating them during widget initialization.
  KeywordSnapshot? take() {
    if (_deps.isTelevision() && !_deps.searchMode() && !_deps.discoverMode()) {
      return null;
    }
    return _deps.repository().take(
      _deps.variant(),
      allowed: _deps.keywordAllowed(),
    );
  }

  /// Restore presentation fields before the first build, retaining default-view
  /// suppression and scroll timing. Cache state is already seeded in its owner.
  bool restore(KeywordSnapshot? snap) {
    if (snap == null) return false;
    _deps.setMode(SearchMode.keyword);
    _searchController.text = snap.query;
    _deps.focus().clearRows();
    _deps.focus().syncRows(snap.projection.results.length);
    _deps.syncTabs();
    _viewport.pendingOffset = snap.scrollOffset;
    return true;
  }

  void preserve() {
    // Preserve a COMPLETED keyword search so returning to this tab restores
    // results + scroll instead of the blank prompt (the nav rebuilds us fresh).
    // A still-streaming search is NOT preserved: its batches die with this
    // instance, so the snapshot would freeze a partial set that restores
    // looking complete (no strip, no cache badges) — matching pre-streaming
    // behavior, where a mid-flight switch preserved nothing.
    if (_deps.mode() == SearchMode.keyword &&
        _deps.bindings().search.query.isNotEmpty &&
        _deps.bindings().results.results.isNotEmpty &&
        !_deps.bindings().search.searching) {
      final projection = keywordResultsSnapshot(_deps.bindings().results);
      _deps.repository().store(
        KeywordSnapshot(
          variant: _deps.variant(),
          query: _deps.bindings().search.query,
          projection: projection,
          cache: _deps.bindings().cache,
          scrollOffset: _viewport.lastOffset,
        ),
      );
    }
  }
}
