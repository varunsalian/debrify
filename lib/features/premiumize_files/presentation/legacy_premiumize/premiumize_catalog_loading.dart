import 'dart:async';

import 'package:debrify/features/premiumize_files/models/folder_view_mode.dart';
import 'package:debrify/features/premiumize_files/models/premiumize_view.dart';
import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:debrify/services/premiumize_service.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_focus_state.dart';
import 'premiumize_navigation_state.dart';
import 'premiumize_search_state.dart';
import 'premiumize_view_state.dart';

typedef PremiumizeCatalogLoadingDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  PremiumizeCatalogState catalogState,
  String? Function() initialFolderId,
  String? Function() initialFolderName,
  PremiumizeNavigationState navigationState,
  String? Function() initialSearchQuery,
  PremiumizeSearchState searchState,
  void Function(String query) performSearch,
  PremiumizeFolderViewMode Function() getCurrentViewMode,
  List<PremiumizeFolderItem> Function(
    PremiumizeFolderViewMode mode,
    List<PremiumizeFolderItem> items,
  )
  applyViewMode,
  void Function() focusFirstItemOrFallback,
  void Function() exitSelectionMode,
  PremiumizeViewState viewState,
  PremiumizeFocusState focusState,
});

class PremiumizeCatalogLoading {
  PremiumizeCatalogLoading(this._deps);
  final PremiumizeCatalogLoadingDeps _deps;

  Future<void> loadSettings() async {
    final enabled = await PremiumizeStorage.getPremiumizeIntegrationEnabled();
    final apiKey = await PremiumizeStorage.getPremiumizeApiKey();

    if (!_deps.mounted()) return;
    _deps.setState(() {
      _deps.catalogState.premiumizeEnabled =
          enabled && apiKey != null && apiKey.isNotEmpty;
      _deps.catalogState.apiKey = apiKey;
      if (_deps.initialFolderId() != null &&
          _deps.initialFolderName() != null) {
        _deps.navigationState.currentFolderId = _deps.initialFolderId();
        _deps.navigationState.currentFolderName = _deps.initialFolderName()!;
      }
      final initialQuery = _deps.initialSearchQuery()?.trim() ?? '';
      if (initialQuery.isNotEmpty) {
        _deps.searchState.isSearchActive = true;
        _deps.searchState.searchController.text = initialQuery;
      }
    });

    if (_deps.catalogState.premiumizeEnabled) {
      loadFolder();
      final initialQuery = _deps.initialSearchQuery()?.trim() ?? '';
      if (initialQuery.isNotEmpty) _deps.performSearch(initialQuery);
    } else {
      _deps.setState(() => _deps.catalogState.initialLoad = false);
    }
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  Future<void> loadFolder() async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null || apiKey.isEmpty || _deps.catalogState.isLoading) {
      return;
    }

    _deps.setState(() {
      _deps.catalogState.isLoading = true;
      _deps.catalogState.errorMessage = '';
    });

    try {
      final listing = await PremiumizeService.listFolder(
        apiKey,
        folderId: _deps.navigationState.currentFolderId,
      );
      if (!_deps.mounted()) return;

      final mode = _deps.getCurrentViewMode();
      final ordered = _deps.applyViewMode(mode, listing.items);

      _deps.setState(() {
        _deps.catalogState.items
          ..clear()
          ..addAll(ordered);
        _deps.catalogState.isLoading = false;
        _deps.catalogState.initialLoad = false;
      });
      _deps.focusFirstItemOrFallback();
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.catalogState.errorMessage = e.toString();
        _deps.catalogState.isLoading = false;
        _deps.catalogState.initialLoad = false;
      });
    }
  }

  Future<void> loadTransfers() async {
    final apiKey = _deps.catalogState.apiKey;
    if (apiKey == null ||
        apiKey.isEmpty ||
        _deps.catalogState.isLoadingTransfers) {
      return;
    }

    _deps.setState(() {
      _deps.catalogState.isLoadingTransfers = true;
      _deps.catalogState.errorMessage = '';
    });

    try {
      final transfers = await PremiumizeService.listTransfers(apiKey);
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.catalogState.transfers
          ..clear()
          ..addAll(transfers);
        _deps.catalogState.isLoadingTransfers = false;
        _deps.catalogState.initialLoad = false;
      });
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _deps.catalogState.errorMessage = e.toString();
        _deps.catalogState.isLoadingTransfers = false;
        _deps.catalogState.initialLoad = false;
      });
    }
  }

  Future<void> refresh() async {
    _deps.exitSelectionMode();
    if (_deps.viewState.selectedView == PremiumizeView.transfers) {
      await loadTransfers();
    } else {
      await loadFolder();
    }
  }

  void switchView(PremiumizeView view) {
    if (_deps.viewState.selectedView == view) return;
    _deps.exitSelectionMode();
    // Reset the Files list offset so a Files→Transfers→Files round-trip
    // doesn't land back on a stale scroll position.
    if (_deps.focusState.scrollController.hasClients) {
      _deps.focusState.scrollController.jumpTo(0);
    }
    _deps.setState(() {
      _deps.viewState.selectedView = view;
      _deps.catalogState.errorMessage = '';
    });
    if (view == PremiumizeView.transfers) {
      loadTransfers();
    } else {
      loadFolder();
    }
  }
}
