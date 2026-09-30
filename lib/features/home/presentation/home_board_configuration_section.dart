import '../application/home_configuration_changes.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../application/home_default_view.dart';
import '../application/home_configuration_refresh.dart';
import '../application/home_catalog_preferences_dependencies.dart';
import '../application/home_board_dependencies.dart';
import '../application/home_refresh_queue.dart';
import '../models/home_row_refresh.dart';
import '../../search/presentation/keyword_search_section.dart';
import '../../search/presentation/catalog_search_section.dart';
import '../../search/presentation/search_mode_section.dart';
import 'home_board_bindings.dart';
import 'home_board_section.dart';
import 'home_board_loading.dart';
import 'home_board_focus.dart';
import 'home_display_section.dart';
import 'home_hero_preview.dart';
import 'home_continuation_section.dart';
import 'home_continuation_loading.dart';
import 'home_saved_content_section.dart';
import 'home_spotlight_section.dart';
import 'home_stage_rows.dart';

typedef HomeBoardConfigurationDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  HomeBoardBindings Function() bindings,
});

/// Settings reconciliation and coalesced Home row/addon refresh dispatch.
class HomeBoardConfigurationSection {
  HomeBoardConfigurationSection(
    this.ref,
    this._deps,
    this._boardSection,
    this._boardLoading,
    this._boardFocus,
    this._keywordSection,
    this._displaySection,
    this._continuationSection,
    this._continuationLoading,
    this._heroPreview,
    this._modeSection,
    this._catalogSection,
    this._spotlightSection,
    this._savedSection,
  );
  final WidgetRef ref;
  final HomeBoardConfigurationDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeBoardLoading _boardLoading;
  final HomeBoardFocus _boardFocus;
  final KeywordSearchSection _keywordSection;
  final HomeDisplaySection _displaySection;
  final HomeContinuationSection _continuationSection;
  final HomeContinuationLoading _continuationLoading;
  final HomeHeroPreview _heroPreview;
  final SearchModeSection _modeSection;
  final CatalogSearchSection _catalogSection;
  final HomeSpotlightSection _spotlightSection;
  final HomeSavedContentSection _savedSection;

  late final ProviderSubscription<HomeDefaultView> homeDefaultViewSubscription;
  HomeDefaultView get homeDefaultView => homeDefaultViewSubscription.read();

  /// Re-read the hidden-rows set + opted-in extras and reload the board if
  /// either actually changed. Fires on any home-settings change (the
  /// broadcast is shared), so the equality guards skip reloads for unrelated
  /// settings.
  Future<void> reloadForHomeSettings() => _deps.bindings().settings.run(
    isCurrent: () => _deps.mounted(),
    refreshAppearance: (current) =>
        _keywordSection.loadSourceTextFormatting(isCurrent: current),
    refreshDisplay: (current) =>
        _displaySection.loadHomeCardOrientation(isCurrent: current),
    refreshContinuation: (current) => _continuationSection
        .continuationLayoutController
        .refresh(isCurrent: current),
    reconcileContinuation: reconcileContinuationLayout,
    refreshTrailers: (current) =>
        _heroPreview.reloadHeroTrailerPrefs(isCurrent: current),
    selectDefaultView: (current) => loadHomeDefaultView(isCurrent: current),
    refreshConfiguration: (current) =>
        HomeConfigurationRefresh(
          catalog: _boardSection.homeCatalogController,
          preferences: ref.read(homeCatalogPreferencesRepositoryProvider),
          collections: _boardSection.homeCollectionsRepository,
          readHideWatched: ref.read(homeBoardServicesProvider).hideWatched,
        ).run(
          isCurrent: current,
          isHome: !_deps.searchMode() && !_deps.discoverMode(),
        ),
    applyConfiguration: applyHomeConfigurationChanges,
  );

  // Reconcile nodes against accepted rows without refetching continuation data.
  void reconcileContinuationLayout() {
    _deps.setState(() {
      _continuationSection.continuationNodes.resize(
        HomeContinuationKind.local,
        movies: _continuationSection.cwMergeLocal
            ? _continuationSection.cwAll.length
            : _continuationSection.cwMovies.length,
        series: _continuationSection.cwMergeLocal
            ? 0
            : _continuationSection.cwSeries.length,
        requestFocus: _boardFocus.requestRowFocus,
      );
      _continuationSection.continuationNodes.resize(
        HomeContinuationKind.trakt,
        movies: _continuationSection.cwMergeTrakt
            ? _continuationSection.traktAll.length
            : _continuationSection.traktMovies.length,
        series: _continuationSection.cwMergeTrakt
            ? 0
            : _continuationSection.traktSeries.length,
        requestFocus: _boardFocus.requestRowFocus,
      );
      _continuationSection.continuationNodes.resize(
        HomeContinuationKind.simkl,
        movies: _continuationSection.cwMergeSimkl
            ? _continuationSection.simklAll.length
            : _continuationSection.simklMovies.length,
        series: _continuationSection.cwMergeSimkl
            ? 0
            : _continuationSection.simklSeries.length,
        requestFocus: _boardFocus.requestRowFocus,
      );
      _continuationSection.continuationNodes.resize(
        HomeContinuationKind.mdblist,
        movies: _continuationSection.cwMergeMdblist
            ? _continuationSection.mdblistAll.length
            : _continuationSection.mdblistMovies.length,
        series: _continuationSection.cwMergeMdblist
            ? 0
            : _continuationSection.mdblistSeries.length,
        requestFocus: _boardFocus.requestRowFocus,
      );
    });
  }

  void applyHomeConfigurationChanges(HomeConfigurationChanges changes) {
    _deps.setState(() {});
    // Hide-watched changes row MEMBERSHIP, so it takes the full reload path.
    if (changes.reloadBoard) {
      requestBoardReload();
    } else if (changes.reloadHero) {
      // Only the hero source moved — re-roll the reel without refetching the
      // whole board. `_boardLoading.load` isn't rerun here, so resolve from the addons the
      // last load cached.
      unawaited(
        _spotlightSection.resolveSpotlightHeroSource(
          _boardSection.addonsById.values.toList(),
        ),
      );
    }
    // IPTV list rows live outside the board's section pipeline. The loader
    // reads its own extras from storage, so it can't race the reload above.
    if (changes.reloadIptv) unawaited(_savedSection.loadIptvListRows());
  }

  /// Run [_boardLoading.load] for a TRIGGERED reload (Home Rows save, integration
  /// connect/disconnect) — unless a catalog search is showing its results, in
  /// which case `_boardLoading.load`'s visible reset would stomp the search view. The
  /// reload is latched instead and [_restoreHome] performs it when the board
  /// comes back. (The initState load never comes through here.)
  void requestBoardReload() {
    if (_catalogSection.catalogQuery.isNotEmpty ||
        _catalogSection.catalogSearching) {
      _boardSection.pendingBoardReload = true;
      return;
    }
    _boardLoading.load();
  }

  Future<void> loadHomeDefaultView({bool Function()? isCurrent}) =>
      homeDefaultView.load(
        isTelevision: _deps.isTelevision(),
        isHome: !_deps.searchMode() && !_deps.discoverMode(),
        isCurrent: () => _deps.mounted() && (isCurrent?.call() ?? true),
        select: (mode) {
          if (_modeSection.mode != mode) _modeSection.switchMode(mode);
        },
      );

  late final homeRefreshQueue = HomeRefreshQueue(
    isCurrent: () => _deps.mounted(),
    isVisible: () => ModalRoute.of(_deps.context())?.isCurrent ?? false,
    refreshRow: (row) {
      switch (row) {
        case HomeRowRefresh.tvFavorites:
          unawaited(_savedSection.loadTvFavorites());
        case HomeRowRefresh.stremioTvFavorites:
          unawaited(_savedSection.loadStremioTvFavorites());
        case HomeRowRefresh.playlist:
          unawaited(_savedSection.loadPlaylistFavorites());
        case HomeRowRefresh.watchlist:
          unawaited(_savedSection.loadMyWatchlist());
        case HomeRowRefresh.playback:
          // Do not consume the local playback/tracker refresh latch here.
          unawaited(_continuationLoading.loadContinueWatching());
          unawaited(_continuationLoading.loadIptvContinueWatching());
      }
    },
    refreshAddons: () {
      if (_catalogSection.catalogQuery.isNotEmpty ||
          _catalogSection.catalogSearching) {
        _boardSection.pendingBoardReload = true;
      } else {
        unawaited(_boardLoading.load(preserveVisibleRows: true));
      }
    },
  );

  void onHomeAddonsChanged() => homeRefreshQueue.addonsChanged();

  void queueHomeRows(Set<HomeRowRefresh> rows) =>
      homeRefreshQueue.enqueue(rows);
}
