import 'package:flutter/material.dart';

import '../../search/models/search_mode.dart';
import '../application/home_tracker_authentication_controller.dart';
import '../models/home_catalog_search_status.dart';
import '../models/home_tracker_authentication.dart';
import 'home_board_bindings.dart';
import 'home_board_configuration_section.dart';
import 'home_board_section.dart';
import 'home_catalog_badges.dart';
import 'home_continuation_loading.dart';
import 'home_screen_controls.dart';

typedef HomeIntegrationDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() isTelevision,
  HomeBoardBindings Function() bindings,
});

/// Refreshes accepted integration state and the rows affected by connection changes.
class HomeIntegrationSection {
  HomeIntegrationSection(
    this._deps,
    this._boardSection,
    this._boardConfiguration,
    this._catalogBadges,
    this._continuationLoading,
    this._controls,
    this._catalogSection,
    this._searchController,
  );
  final HomeIntegrationDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeBoardConfigurationSection _boardConfiguration;
  final HomeCatalogBadges _catalogBadges;
  final HomeContinuationLoading _continuationLoading;
  final HomeScreenControls _controls;
  final HomeCatalogSearchStatus _catalogSection;
  final TextEditingController _searchController;

  /// Whether Trakt is connected — gates the Trakt-syncing detail quick actions
  /// (watchlist / collection / watched / rate / list). App actions (Select
  /// Source, Add to Stremio TV, Search Packs) show regardless.
  Map<HomeTracker, HomeTrackerAuthenticationController>
  get trackerAuthControllers => _deps.bindings().authentication;
  bool get isTraktAuthenticated =>
      trackerAuthControllers[HomeTracker.trakt]!.current;

  /// Whether Simkl is connected — gates the Simkl detail quick actions,
  /// rendered as their own strip alongside Trakt's (see [isTraktAuthenticated]).
  bool get isSimklAuthenticated =>
      trackerAuthControllers[HomeTracker.simkl]!.current;

  /// Whether MDBList is connected — gates the MDBList entry in the Discover
  /// source dropdown (hidden when disconnected, so an unauthed user isn't shown
  /// a dead source; kept visible if it's somehow the active source).
  bool get isMdblistAuthenticated =>
      trackerAuthControllers[HomeTracker.mdblist]!.current;

  /// An integration (Trakt / a debrid provider) was connected or disconnected
  /// elsewhere while this tab stayed alive — refresh the state that gates the
  /// detail quick actions, the PikPak-only Play hiding, and the Trakt rows.
  void onIntegrationsChanged() {
    refreshTraktAuthState();
    refreshSimklAuthState();
    refreshMdblistAuthState();
    _catalogBadges.refreshPikpakOnly();
    // Connect/disconnect can change what the local shelves should hold (the
    // single-owner rule keys off scrobbling), so re-read local CW before the
    // tracker rows; _boardConfiguration.reloadForHomeSettings can legitimately return early when
    // no row/layout preference changed.
    if (!_deps.searchMode() && !_deps.discoverMode()) {
      _continuationLoading.loadContinueWatching();
    }
    // Trakt/Simkl Continue Watching rows are never rendered on the dedicated
    // Search tab, so don't refetch them there.
    if (!_deps.searchMode()) {
      _continuationLoading.loadTraktContinueWatching();
      _continuationLoading.loadSimklContinueWatching();
      _continuationLoading.loadMdblistContinueWatching();
    }
    // Opted-in tracker LIST rows live in the board's section pipeline, so a
    // connect/disconnect needs a board reload to add/drop them. Home board
    // only — this listener is registered by every SearchScreen variant, and
    // Search/Discover must never run the board pipeline. Deferred while a
    // catalog search is showing (see _boardConfiguration.requestBoardReload); safe against
    // overlap via _boardSection.boardLoadGen.
    if (!_deps.searchMode() &&
        !_deps.discoverMode() &&
        _boardSection.trackerExtrasEnabled) {
      _boardConfiguration.requestBoardReload();
    }
  }

  Future<void> refreshTraktAuthState() =>
      trackerAuthControllers[HomeTracker.trakt]!.load(
        isCurrent: () => _deps.mounted(),
        onChanged: (_) => _deps.setState(() {}),
      );

  Future<void> refreshSimklAuthState() =>
      trackerAuthControllers[HomeTracker.simkl]!.load(
        isCurrent: () => _deps.mounted(),
        onChanged: (_) => _deps.setState(() {}),
      );

  Future<void> refreshMdblistAuthState() {
    var leaveLists = false;
    return trackerAuthControllers[HomeTracker.mdblist]!.load(
      isCurrent: () => _deps.mounted(),
      beforeChange: (auth) {
        leaveLists = !auth && _controls.mode == SearchMode.lists;
        if (leaveLists) _controls.clearListsSearch();
      },
      onChanged: (_) {
        _deps.setState(() {
          if (leaveLists) _controls.mode = SearchMode.catalog;
        });
        // A disconnect can remove the currently selected mode. Keep the shared
        // query useful by resolving it through Catalog after the selector falls
        // back, unless those exact Catalog results are already present.
        if (leaveLists) {
          final query = _searchController.text.trim();
          if (query.isNotEmpty && query != _catalogSection.catalogQuery) {
            _catalogSection.runCatalogSearch(query);
          }
          if (_deps.isTelevision()) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_deps.mounted()) _controls.searchFieldNode.requestFocus();
            });
          }
        }
      },
    );
  }
}
