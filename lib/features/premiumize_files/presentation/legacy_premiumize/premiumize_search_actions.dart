import 'dart:async';

import 'package:debrify/services/premiumize_service.dart';
import 'package:flutter/material.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_focus_state.dart';
import 'premiumize_search_state.dart';
import 'premiumize_selection_state.dart';

typedef PremiumizeSearchActionsDeps = ({
  void Function(VoidCallback) setState,
  PremiumizeSearchState searchState,
  PremiumizeSelectionState selectionState,
  bool Function() mounted,
  PremiumizeFocusState focusState,
  bool Function() isAtRoot,
  PremiumizeCatalogState catalogState,
  void Function(String message, {bool isError, Duration? duration})
  showSnackBar,
});

class PremiumizeSearchActions {
  PremiumizeSearchActions(this._deps);
  final PremiumizeSearchActionsDeps _deps;

  // ── Search ─────────────────────────────────────────────────────────────────

  void toggleSearch() {
    _deps.setState(() {
      _deps.searchState.isSearchActive = !_deps.searchState.isSearchActive;
      if (!_deps.searchState.isSearchActive) {
        _deps.searchState.searchDebounce?.cancel();
        _deps.searchState.searchController.clear();
        _deps.searchState.searchResults = [];
        _deps.searchState.isSearching = false;
      } else {
        // Search and multi-select are mutually exclusive: selection bar actions
        // operate on _items, not search results.
        _deps.selectionState.isSelectionMode = false;
        _deps.selectionState.selectedIds.clear();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_deps.mounted()) _deps.focusState.searchFocusNode.requestFocus();
        });
      }
    });
  }

  void performSearch(String query) {
    final q = query.trim();
    if (q.isEmpty) {
      _deps.searchState.searchDebounce?.cancel();
      _deps.setState(() {
        _deps.searchState.searchResults = [];
        _deps.searchState.isSearching = false;
      });
      return;
    }

    // Root: server-side cloud search (recursive), debounced to limit calls.
    if (_deps.isAtRoot()) {
      _deps.searchState.searchDebounce?.cancel();
      _deps.setState(() => _deps.searchState.isSearching = true);
      _deps.searchState.searchDebounce = Timer(
        const Duration(milliseconds: 350),
        () => runCloudSearch(q),
      );
      return;
    }

    // Inside a folder: filter the currently-loaded items locally.
    final lower = q.toLowerCase();
    _deps.setState(() {
      _deps.searchState.isSearching = false;
      _deps.searchState.searchResults = _deps.catalogState.items
          .where((i) => !i.isFolder && i.name.toLowerCase().contains(lower))
          .toList();
    });
  }

  Future<void> runCloudSearch(String query) async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    try {
      final results = await PremiumizeService.searchCloud(apiKey, query);
      if (!_deps.mounted()) return;
      // Drop stale results if the query changed while the request was in flight.
      if (_deps.searchState.searchController.text.trim() != query) return;
      _deps.setState(() {
        _deps.searchState.searchResults = results;
        _deps.searchState.isSearching = false;
      });
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() => _deps.searchState.isSearching = false);
      _deps.showSnackBar('Search failed: $e', isError: true);
    }
  }
}
