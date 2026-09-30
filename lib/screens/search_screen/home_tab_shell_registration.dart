import 'dart:async';
import 'package:flutter/widgets.dart';
import '../../features/home/presentation/home_continuation_loading.dart';
import '../../features/home/presentation/home_rows_navigation.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import '../../features/search/presentation/search_mode_section.dart';
import '../../features/search/presentation/search_title_section.dart';
import '../../services/main_page_bridge.dart';

typedef HomeTabShellDeps = ({
  bool Function() mounted,
  int Function() tabIndex,
  bool Function() searchMode,
  bool Function() discoverMode,
  Listenable Function() localCompletion,
  Listenable Function() mdblistPlayback,
});

/// Borrows the tab's shell handlers and releases the same handlers at teardown.
/// Construction registers nothing; the route calls start at its original point.
class HomeTabShellRegistration {
  HomeTabShellRegistration(
    this._deps,
    this._focusContent,
    this._continuation,
    this._saved,
    this._mode,
    this._title,
    this._navigation,
  );
  final HomeTabShellDeps _deps;
  final VoidCallback _focusContent;
  final HomeContinuationLoading _continuation;
  final HomeSavedContentSection _saved;
  final SearchModeSection _mode;
  final SearchTitleSection _title;
  final HomeRowsNavigation _navigation;

  void start() {
    MainPageBridge.registerTvContentFocusHandler(
      _deps.tabIndex(),
      _focusContent,
    );
    if (!_deps.searchMode() && !_deps.discoverMode()) {
      _deps.localCompletion().addListener(
        _continuation.onLocalCompletionChanged,
      );
      _deps.mdblistPlayback().addListener(
        _continuation.onMdblistPlaybackRevision,
      );
      MainPageBridge.addPlaylistChangeListener(_saved.loadPlaylistFavorites);
    }
    if (_deps.searchMode()) {
      MainPageBridge.registerTabBackHandler('search', _mode.handleSearchBack);
      MainPageBridge.activeTab.addListener(_title.onTitleSearchTabChanged);
    }
    // A detail-open handed off from another tab (e.g. the Trakt Calendar, a
    // separate tab that can't reach this screen's state). Only the Home board
    // (not the Search/Discover variants) claims it; the opener switches here via
    // switchTab(15) right after setting it, so it's present by the time we mount.
    if (!_deps.searchMode() && !_deps.discoverMode()) {
      MainPageBridge.registerCatalogDetailOpenHandler(
        _navigation.openPendingCatalogDetail,
      );
      final pending = MainPageBridge.pendingCatalogDetailOpen;
      if (pending != null) {
        MainPageBridge.pendingCatalogDetailOpen = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_deps.mounted()) {
            unawaited(_navigation.openPendingCatalogDetail(pending));
          }
        });
      }
    }
  }

  void dispose() {
    MainPageBridge.unregisterTvContentFocusHandler(
      _deps.tabIndex(),
      _focusContent,
    );
    _deps.localCompletion().removeListener(
      _continuation.onLocalCompletionChanged,
    );
    _deps.mdblistPlayback().removeListener(
      _continuation.onMdblistPlaybackRevision,
    );
    if (!_deps.searchMode() && !_deps.discoverMode()) {
      MainPageBridge.removePlaylistChangeListener(_saved.loadPlaylistFavorites);
      MainPageBridge.unregisterCatalogDetailOpenHandler(
        _navigation.openPendingCatalogDetail,
      );
    }
    if (_deps.searchMode()) {
      MainPageBridge.unregisterTabBackHandler('search', _mode.handleSearchBack);
      MainPageBridge.activeTab.removeListener(_title.onTitleSearchTabChanged);
    }
  }
}
