import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../features/discover/presentation/discover_loading.dart';
import '../../features/home/presentation/home_continuation_loading.dart';
import '../../features/home/presentation/home_return_section.dart';
import '../../features/home/presentation/home_saved_content_section.dart';
import '../../features/search/presentation/keyword_search_section.dart';
import 'home_board_composition.dart';
import 'home_catalog_presentation_composition.dart';
import 'home_view_bindings.dart';

typedef HomeContentStartupDeps = ({
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() isTelevision,
});

/// Starts the original tab-specific content loads after bindings and shell setup.
/// Borrowed owners keep their own request guards and disposal responsibilities.
class HomeContentStartup {
  HomeContentStartup(
    this._deps,
    this._board,
    this._catalog,
    this._discover,
    this._view,
    this._return,
    this._continuation,
    this._saved,
    this._keyword,
  );

  final HomeContentStartupDeps _deps;
  final HomeBoardWorkflow _board;
  final HomeCatalogPresentation _catalog;
  final KeywordSearchSection _keyword;
  final DiscoverLoading _discover;
  final HomeViewBindings _view;
  final HomeReturnSection _return;
  final HomeContinuationLoading _continuation;
  final HomeSavedContentSection _saved;

  void start({required bool restoredKeyword}) {
    _catalog.integrations.refreshTraktAuthState();
    _catalog.integrations.refreshSimklAuthState();
    _catalog.integrations.refreshMdblistAuthState();
    _catalog.navigation.loadMergedSeriesFlag();
    // (The keyword restore itself ran earlier — before _board.boardConfiguration.loadHomeDefaultView —
    // see the ordering comment there.) A restored search carries its own
    // filters, so don't overwrite them with the saved defaults.
    if (!restoredKeyword) {
      unawaited(_keyword.loadDefaultKeywordFilters());
    }

    // The dedicated Search tab only shows a field + blank prompt until a query,
    // so it skips the whole board pipeline (home catalogs, Continue Watching,
    // Trakt, favourites) — catalog search fetches its addons on demand. It also
    // never runs _board.boardLoading.load(), which is what clears _board.boardSection.loading, so clear it here or the
    // results grid (HomeBoardRendering.buildBoard) would sit on its initial spinner forever.
    if (_deps.searchMode()) {
      _board.boardSection.finishLoading();
    } else if (_deps.discoverMode()) {
      // Discover browses one source at a time via the Source dropdown, so it
      // skips the board's catalog pipeline and just primes the Continue Watching
      // + Trakt rows its first two sources draw from. _badges.refreshPikpakOnly gates the
      // Quick-Play affordance the same way the board does.
      _board.boardSection.finishLoading();
      _catalog.badges.refreshPikpakOnly();
      _discover.loadAddons();
      _discover.primeRows();
    } else {
      // TV board: last-resort focus reclaim. Several load/reload paths dispose
      // FocusNodes wholesale (_board.boardRows.applySections rebuilds every catalog row's
      // nodes; CW rows re-sync after playback) and any of them can kill the
      // node holding primary focus — leaving the remote dead with no DPAD
      // press able to recover (the shell's recovery only fires when the scope
      // has NO traversable descendants, and the board always has plenty).
      // Watch the FocusManager and re-anchor onto the board when focus dies.
      if (_deps.isTelevision()) {
        FocusManager.instance.addListener(
          _board.boardFocus.onGlobalFocusChange,
        );
      }
      // Kick off every leading-content load. Auto-focus settles to the top as
      // these complete; once they've ALL settled the arrival window is over and
      // re-anchoring latches off (see [_board.boardFocus.settleAutoFocusAfter]), so a later
      // background reload or a return from playback never yanks focus.
      _board.boardFocus.settleAutoFocusAfter([
        if (_view.restoredHome && !restoredKeyword)
          _return.restoreHomeSnapshot(_view.homeSnapshot!)
        else
          _board.boardLoading.load(),
        _continuation.loadContinueWatching(),
        _continuation.loadTraktContinueWatching(),
        // refreshBound:false — _board.boardLoading.load()'s bound-source scan (which now covers the
        // Simkl rows) runs after this on cold start, so a 2nd concurrent scan
        // here would be pure duplicate startup work on weak TV hardware.
        _continuation.loadSimklContinueWatching(refreshBound: false),
        _continuation.loadMdblistContinueWatching(refreshBound: false),
        _continuation.loadIptvContinueWatching(),
        _saved.loadTvFavorites(),
        _saved.loadStremioTvFavorites(),
        _saved.loadIptvFavorites(),
        _saved.loadMyWatchlist(),
        _saved.loadIptvListRows(),
        _saved.loadPlaylistFavorites(),
      ]);
    }
  }
}
