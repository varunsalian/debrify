import 'dart:async';
import 'package:debrify/features/alldebrid_files/models/alldebrid_view.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_focus_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_library_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_navigation_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_search_state.dart';
import 'package:debrify/features/alldebrid_files/presentation/legacy_alldebrid/alldebrid_selection_state.dart';
import 'package:debrify/models/alldebrid_link.dart';
import 'package:debrify/models/alldebrid_magnet.dart';
import 'package:debrify/services/alldebrid_service.dart';
import 'package:debrify/services/main_page_bridge.dart';
import 'package:flutter/material.dart';

typedef AllDebridNavigationDeps = ({
  AllDebridNavigationState navigationState,
  AllDebridSelectionState selectionState,
  AllDebridSearchState searchState,
  AllDebridFocusState focusState,
  AllDebridLibraryState libraryState,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  void Function() exitSelectionMode,
  void Function() focusFirstItem,
  bool Function() isAtRoot,
  Future<void> Function() load,
  Future<void> Function() loadLinks,
  void Function() navigateUp,
  Future<void> Function(AllDebridMagnet magnet, {bool force}) openMagnet,
  void Function(String message, {bool isError}) snack,
  void Function() toggleSearch,
  List<AllDebridLink> Function() visibleLinks,
  List<AllDebridMagnet> Function() visibleMagnets,
});

class AllDebridNavigation {
  final AllDebridNavigationDeps _deps;
  AllDebridNavigation(this._deps);
  AllDebridNavigationState get _navigation => _deps.navigationState;
  AllDebridSelectionState get _selection => _deps.selectionState;
  AllDebridSearchState get _search => _deps.searchState;
  AllDebridFocusState get _f => _deps.focusState;
  AllDebridLibraryState get _library => _deps.libraryState;

  bool get isAtRoot => _navigation.currentMagnet == null;

  /// Switches to the Web Downloads view and refreshes it. Invoked via
  /// [MainPageBridge.focusAllDebridWebDownloads] when a shared web link is saved
  /// while this screen is already mounted.
  Future<void> focusWebDownloads() async {
    if (!_deps.mounted()) return;
    _deps.setState(() {
      _navigation.selectedView = AllDebridView.webDownloads;
      _navigation.currentMagnet = null;
      _navigation.currentFiles = [];
      _selection.selectionMode = false;
      _selection.selectedIds.clear();
      _search.searchActive = false;
      _search.searchQuery = '';
      _search.searchController.clear();
    });
    await _deps.loadLinks();
  }

  void focusFirstItem() {
    if (!_f.shouldFocusOnLoad) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_deps.mounted() || !_f.shouldFocusOnLoad) return;
      final hasItems = _navigation.selectedView == AllDebridView.webDownloads
          ? _deps.visibleLinks().isNotEmpty
          : _deps.visibleMagnets().isNotEmpty;
      if (_deps.isAtRoot() && hasItems) {
        _f.shouldFocusOnLoad = false;
        _f.firstItemFocusNode.requestFocus();
      }
    });
  }

  Future<void> refresh() async {
    if (_navigation.selectedView == AllDebridView.webDownloads) {
      await _deps.loadLinks();
    } else if (_navigation.currentMagnet != null) {
      await _deps.openMagnet(_navigation.currentMagnet!, force: true);
    } else {
      await _deps.load();
    }
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  Future<void> openMagnet(AllDebridMagnet magnet, {bool force = false}) async {
    final apiKey = _library.apiKey;
    if (apiKey == null || apiKey.isEmpty) return;
    if (!magnet.isReady) {
      _deps.snack(
        magnet.isError
            ? 'This magnet failed on AllDebrid.'
            : 'This magnet is still downloading on AllDebrid.',
        isError: true,
      );
      return;
    }
    _deps.setState(() {
      _navigation.currentMagnet = magnet;
      _navigation.loadingFiles = true;
      _search.fileSearchActive = false;
      _search.fileSearchQuery = '';
      _search.fileSearchController.clear();
      if (!force) _navigation.currentFiles = [];
    });
    try {
      final files = await AllDebridService.getMagnetFiles(apiKey, magnet.id);
      if (!_deps.mounted()) return;
      _deps.setState(() {
        _navigation.currentFiles = files;
        _navigation.loadingFiles = false;
      });
    } catch (e) {
      if (!_deps.mounted()) return;
      _deps.setState(() => _navigation.loadingFiles = false);
      _deps.snack('Failed to load files: $e', isError: true);
    }
  }

  void navigateUp() {
    // Refocus the first magnet row after this synchronous swap back to the
    // (already-loaded) magnet list — the file row that binds
    // _firstItemFocusNode is disposed here and nothing else reclaims DPAD
    // focus. No reload fires, so do it directly.
    _f.shouldFocusOnLoad = true;
    if (_f.scrollController.hasClients) _f.scrollController.jumpTo(0);
    _deps.setState(() {
      _navigation.currentMagnet = null;
      _navigation.currentFiles = [];
      _navigation.loadingFiles = false;
      _search.fileSearchActive = false;
      _search.fileSearchQuery = '';
      _search.fileSearchController.clear();
    });
    _deps.focusFirstItem();
  }

  bool handleBackNavigation() {
    if (_selection.selectionMode) {
      _deps.exitSelectionMode();
      return true;
    }
    if (_search.fileSearchActive) {
      _deps.setState(() {
        _search.fileSearchActive = false;
        _search.fileSearchQuery = '';
        _search.fileSearchController.clear();
      });
      return true;
    }
    if (_search.searchActive) {
      _deps.toggleSearch();
      return true;
    }
    if (_navigation.currentMagnet != null) {
      _deps.navigateUp();
      return true;
    }
    return false;
  }
}
