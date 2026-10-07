import 'dart:async';

import 'package:debrify/models/premiumize_folder_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'premiumize_catalog_state.dart';
import 'premiumize_focus_state.dart';
import 'premiumize_navigation_state.dart';
import 'premiumize_search_state.dart';

typedef PremiumizeFolderNavigationDeps = ({
  PremiumizeNavigationState navigationState,
  void Function() exitSelectionMode,
  PremiumizeFocusState focusState,
  void Function(VoidCallback) setState,
  PremiumizeCatalogState catalogState,
  PremiumizeSearchState searchState,
  Future<void> Function() loadFolder,
});

class PremiumizeFolderNavigation {
  PremiumizeFolderNavigation(this._deps);
  final PremiumizeFolderNavigationDeps _deps;

  bool get isAtRoot => _deps.navigationState.currentFolderId == null;

  // ── Folder navigation ──────────────────────────────────────────────────────

  void navigateIntoFolder(PremiumizeFolderItem folder) {
    _deps.exitSelectionMode();
    _deps.focusState.shouldFocusOnLoad = true;
    // Reset scroll while the outgoing list is still attached, so the new
    // folder never inherits the old offset.
    if (_deps.focusState.scrollController.hasClients) {
      _deps.focusState.scrollController.jumpTo(0);
    }
    _deps.setState(() {
      _deps.navigationState.navigationStack.add((
        id: _deps.navigationState.currentFolderId,
        name: _deps.navigationState.currentFolderName,
      ));
      _deps.navigationState.currentFolderId = folder.id;
      _deps.navigationState.currentFolderName = folder.name;
      // Clear stale rows so the loading skeleton shows instead of the
      // outgoing folder's contents sitting frozen while the fetch runs.
      _deps.catalogState.items.clear();
      _deps.searchState.isSearchActive = false;
      _deps.searchState.searchController.clear();
      _deps.searchState.searchResults = [];
    });
    _deps.loadFolder();
  }

  void navigateUp() {
    _deps.exitSelectionMode();
    if (_deps.navigationState.navigationStack.isEmpty) return;
    // Refocus the first row once the parent listing loads — clearing _items
    // disposes the focused row and nothing else reclaims DPAD focus.
    _deps.focusState.shouldFocusOnLoad = true;
    if (_deps.focusState.scrollController.hasClients) {
      _deps.focusState.scrollController.jumpTo(0);
    }
    _deps.setState(() {
      final previous = _deps.navigationState.navigationStack.removeLast();
      _deps.navigationState.currentFolderId = previous.id;
      _deps.navigationState.currentFolderName = previous.name;
      _deps.catalogState.items.clear();
    });
    _deps.loadFolder();
  }
}
