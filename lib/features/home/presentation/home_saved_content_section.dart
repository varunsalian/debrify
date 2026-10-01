import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';
import '../application/home_iptv_favorites_controller.dart';
import '../application/home_iptv_lists_controller.dart';
import '../application/home_playlist_controller.dart';
import '../application/home_stremio_favorites_controller.dart';
import '../application/home_tv_favorites_controller.dart';
import '../application/home_watchlist_controller.dart';
import '../models/home_catalog_search_status.dart';
import '../models/home_favorite_row_ref.dart';
import '../models/home_iptv_list.dart';
import '../models/home_playlist.dart';
import '../models/home_stremio_favorites.dart';
import 'home_favorite_bindings.dart';
import 'home_favorite_nodes.dart';
import 'home_iptv_list_focus.dart';

typedef HomeSavedContentDeps = ({
  HomeFavoriteBindings Function() bindings,
  bool Function() mounted,
  void Function(VoidCallback) setState,
  Set<String> Function() disabled,
  VoidCallback autoFocus,
  VoidCallback focusContent,
  void Function(List<FocusNode>, int) requestRowFocus,
  bool Function() debrifyTvAllowed,
  bool Function() stremioTvAllowed,
  bool Function() iptvAllowed,
  String Function(String) iptvListId,
  void Function(DebrifyTvChannel) playChannel,
  void Function(HomeStremioFavorite) playStremio,
});

/// Owns saved-row loading, visibility and focus pools for this route.
class HomeSavedContentSection {
  HomeSavedContentSection(this._deps, this._catalog);
  final HomeSavedContentDeps _deps;
  final HomeCatalogSearchStatus _catalog;

  /// Launch a Debrify TV channel (same path the Home screen uses): hand off to
  /// the live player if it's mounted, else queue an auto-play and switch tabs.
  void playChannel(DebrifyTvChannel channel) => _deps.playChannel(channel);

  /// Open a Stremio TV channel (same path the Home screen uses): hand off to the
  /// live player if it's mounted, else queue an auto-play and switch tabs.
  void playStremioTvChannel(HomeStremioFavorite channel) =>
      _deps.playStremio(channel);

  // Debrify TV favourites — a leading "Debrify TV" row of the user's starred
  // keyword channels, shown between Continue Watching and the catalog rows.
  // Channels have no artwork, so they render as Stremio-shaped cards with a
  // gradient + glyph placeholder (see [HomeArtPoster]).
  final favoriteNodes = HomeFavoriteNodes();
  HomeTvFavoritesController get tvFavoritesController => _deps.bindings().tv;
  List<DebrifyTvChannel> get tvFavChannels => tvFavoritesController.current;
  List<FocusNode> get tvFavNodes =>
      favoriteNodes.nodes(HomeFavoriteKind.debrify);

  // Stremio TV favourites — a leading row of the user's starred Stremio
  // "channels" (catalogs treated as TV channels). Each card shows the channel's
  // current now-playing item poster (same time-based rotation as the Home /
  // Stremio TV screens); tapping opens the channel. Loaded once on init.
  HomeStremioFavoritesController get stremioFavoritesController =>
      _deps.bindings().stremio;
  List<HomeStremioFavorite> get stvFavChannels =>
      stremioFavoritesController.current.channels;
  List<FocusNode> get stvFavNodes =>
      favoriteNodes.nodes(HomeFavoriteKind.stremio);

  // IPTV favourites — a leading row of the user's starred live IPTV channels.
  // Cards show the channel logo (glyph fallback); tapping plays the stream
  // directly via VideoPlayerLauncher (no tab switch). Reloaded whenever list
  // membership or manual order changes.
  HomeIptvFavoritesController get iptvFavoritesController =>
      _deps.bindings().iptv;
  List<IptvChannel> get iptvFavChannels => iptvFavoritesController.current;
  List<FocusNode> get iptvFavNodes =>
      favoriteNodes.nodes(HomeFavoriteKind.iptv);

  // Debrify's account-independent movie/series watchlist. Full metadata is
  // stored locally and presented as separate movie and series rows, so neither
  // row needs a tracker or catalog network request.
  HomeWatchlistController get watchlistController => _deps.bindings().watchlist;
  List<StremioMeta> get watchlistMovieItems =>
      watchlistController.current.movies;
  List<StremioMeta> get watchlistSeriesItems =>
      watchlistController.current.series;
  List<FocusNode> get watchlistMovieNodes =>
      favoriteNodes.nodes(HomeFavoriteKind.watchlistMovies);
  List<FocusNode> get watchlistSeriesNodes =>
      favoriteNodes.nodes(HomeFavoriteKind.watchlistSeries);

  // Opted-in IPTV custom lists as Home rows (`iptvlist:` extras), rendered
  // through the favourites-row family after the IPTV favourites row. Rebuilt
  // by [loadIptvListRows] on init, on Home Rows saves, and whenever
  // [IptvMediaStore.listsRevision] bumps (any list mutation anywhere in the
  // app). The view owns FocusNodes, reconciled by list id across reloads.
  HomeIptvListsController get iptvListsController => _deps.bindings().iptvLists;
  List<HomeIptvList> get iptvListRows => iptvListsController.current;
  final iptvListFocus = HomeIptvListFocus();

  // Playlist favourites — a leading row of the user's saved playlist items
  // (movies / collections added from search or cloud). Cards show the item
  // poster with resume progress; tapping opens a full action menu (play / play
  // random / view files / favorite / clear progress / launch-on-startup /
  // delete), so this row is a complete playlist manager on its own now that the
  // Home playlist section is being phased out. Loaded once on init.
  HomePlaylistController get playlistController => _deps.bindings().playlist;
  List<HomePlaylistItem> get playlistItems => playlistController.current.items;
  List<FocusNode> get playlistFavNodes =>
      favoriteNodes.nodes(HomeFavoriteKind.playlist);

  // The leading favourites rows (between Continue Watching and the catalog) are
  // only shown on the board, never over search results — same gate as
  // [_cwVisible]. Each has its own visibility so an empty source just drops out.
  bool get iptvFavVisible =>
      iptvFavChannels.isNotEmpty &&
      !_deps.disabled().contains('fav:iptv') &&
      _catalog.catalogQuery.isEmpty &&
      !_catalog.catalogSearching;
  bool get tvFavVisible =>
      tvFavChannels.isNotEmpty &&
      !_deps.disabled().contains('fav:debrify') &&
      _catalog.catalogQuery.isEmpty &&
      !_catalog.catalogSearching;
  bool get stvFavVisible =>
      stvFavChannels.isNotEmpty &&
      !_deps.disabled().contains('fav:stremio') &&
      _catalog.catalogQuery.isEmpty &&
      !_catalog.catalogSearching;
  bool get playlistFavVisible =>
      playlistItems.isNotEmpty &&
      !_deps.disabled().contains('fav:playlist') &&
      _catalog.catalogQuery.isEmpty &&
      !_catalog.catalogSearching;
  bool get watchlistMoviesVisible =>
      watchlistMovieItems.isNotEmpty &&
      !_deps.disabled().contains('watchlist:movies') &&
      _catalog.catalogQuery.isEmpty &&
      !_catalog.catalogSearching;
  bool get watchlistSeriesVisible =>
      watchlistSeriesItems.isNotEmpty &&
      !_deps.disabled().contains('watchlist:series') &&
      _catalog.catalogQuery.isEmpty &&
      !_catalog.catalogSearching;

  /// The visible saved-content rows in render order: Watchlist Movies,
  /// Watchlist Series, Playlist, Debrify TV, Stremio TV, IPTV favourites, then
  /// opted-in IPTV custom lists.
  /// This is the single source of truth for both rendering ([_buildBoard]) and
  /// the index-based DPAD focus wiring below, so the two never drift out of
  /// sync. IPTV list rows share the favourites gates (board only, non-empty)
  /// and are opt-in by construction — [iptvListRows] only ever holds enabled
  /// lists.
  // Reach-sweep rule: a feature that's off drops its Home rows too, not
  // just its tab — the profile should never see a shelf it can't open.
  List<HomeFavoriteRowRef> get favRowKinds => [
    if (watchlistMoviesVisible)
      const HomeFavoriteRowRef(HomeFavoriteKind.watchlistMovies),
    if (watchlistSeriesVisible)
      const HomeFavoriteRowRef(HomeFavoriteKind.watchlistSeries),
    if (playlistFavVisible) const HomeFavoriteRowRef(HomeFavoriteKind.playlist),
    if (tvFavVisible && _deps.debrifyTvAllowed())
      const HomeFavoriteRowRef(HomeFavoriteKind.debrify),
    if (stvFavVisible && _deps.stremioTvAllowed())
      const HomeFavoriteRowRef(HomeFavoriteKind.stremio),
    if (iptvFavVisible && _deps.iptvAllowed())
      const HomeFavoriteRowRef(HomeFavoriteKind.iptv),
    if (_catalog.catalogQuery.isEmpty &&
        !_catalog.catalogSearching &&
        _deps.iptvAllowed())
      for (var i = 0; i < iptvListRows.length; i++)
        if (iptvListRows[i].channels.isNotEmpty)
          HomeFavoriteRowRef(HomeFavoriteKind.iptv, i),
  ];

  int get favRowCount => favRowKinds.length;
  bool get anyFavVisible => favRowKinds.isNotEmpty;

  String favRowId(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) {
      return _deps.iptvListId(iptvListRows[ref.list].listId);
    }
    return switch (ref.kind) {
      HomeFavoriteKind.watchlistMovies => 'watchlist:movies',
      HomeFavoriteKind.watchlistSeries => 'watchlist:series',
      HomeFavoriteKind.playlist => 'fav:playlist',
      HomeFavoriteKind.debrify => 'fav:debrify',
      HomeFavoriteKind.stremio => 'fav:stremio',
      HomeFavoriteKind.iptv => 'fav:iptv',
    };
  }

  /// The focus-node list backing a favourites row of the given [ref].
  List<FocusNode> favNodesFor(HomeFavoriteRowRef ref) {
    if (ref.isIptvList) {
      return iptvListFocus.nodesFor(iptvListRows[ref.list].listId);
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
        return watchlistMovieNodes;
      case HomeFavoriteKind.watchlistSeries:
        return watchlistSeriesNodes;
      case HomeFavoriteKind.iptv:
        return iptvFavNodes;
      case HomeFavoriteKind.debrify:
        return tvFavNodes;
      case HomeFavoriteKind.stremio:
        return stvFavNodes;
      case HomeFavoriteKind.playlist:
        return playlistFavNodes;
    }
  }

  /// Focus a card in the favourites row at [favIndex] (index into the visible
  /// favourites rows), clamping the column to that row's length. Returns false
  /// when no such row is focusable (same contract as [_focusCwRow]).
  bool focusFavRowAt(int favIndex, int column) {
    final kinds = favRowKinds;
    if (favIndex < 0 || favIndex >= kinds.length) return false;
    final nodes = favNodesFor(kinds[favIndex]);
    if (nodes.isEmpty) return false;
    _deps.requestRowFocus(nodes, column.clamp(0, nodes.length - 1));
    return true;
  }

  /// Reload starred channels without replacing newer row data.
  Future<void> loadTvFavorites() => tvFavoritesController.load(
    isCurrent: () => _deps.mounted(),
    onRows: (hasFavoriteIds) {
      _deps.setState(() {});
      syncTvFavNodes();
      if (hasFavoriteIds) _deps.autoFocus();
    },
  );

  /// Grow/shrink the favourites row's focus nodes to match the channel count.
  void syncTvFavNodes() =>
      syncFavoriteNodes(HomeFavoriteKind.debrify, tvFavChannels.length);

  /// Reload starred Stremio TV channels without replacing newer row data.
  Future<void> loadStremioTvFavorites() => stremioFavoritesController.load(
    isCurrent: () => _deps.mounted(),
    onRows: (hasFavoriteIds) {
      _deps.setState(() {});
      syncStvFavNodes();
      if (hasFavoriteIds) _deps.autoFocus();
    },
  );

  void syncStvFavNodes() =>
      syncFavoriteNodes(HomeFavoriteKind.stremio, stvFavChannels.length);

  /// The now-playing item for a Stremio TV channel, using the same time-based
  /// rotation as the Home / Stremio TV screens (series rotate on their own
  /// cadence). Null when the channel has no loaded items.
  StremioTvNowPlaying? stvNowPlaying(HomeStremioFavorite channel) {
    if (channel.items.isEmpty) return null;
    return stremioFavoritesController.playingAt(channel, DateTime.now());
  }

  /// Reload the live-only favourites projection; custom lists retain their own mapping.
  Future<void> loadIptvFavorites() => iptvFavoritesController.load(
    isCurrent: () => _deps.mounted(),
    onRows: (hasFavorites) {
      _deps.setState(() {});
      syncIptvFavNodes();
      if (hasFavorites) _deps.autoFocus();
    },
  );

  void syncIptvFavNodes() =>
      syncFavoriteNodes(HomeFavoriteKind.iptv, iptvFavChannels.length);

  /// Apply a complete custom-list snapshot while retaining surviving row nodes.
  Future<void> loadIptvListRows() => iptvListsController.load(
    isCurrent: () => _deps.mounted(),
    beforeRows: iptvListFocus.reconcile,
    onRows: () {
      _deps.setState(() {});
      _deps.autoFocus();
    },
  );

  /// [IptvMediaStore.listsRevision] bumped — some list mutated somewhere in
  /// the app (picker, IPTV settings, provider deletion, reconcile, import).
  void onIptvListsRevision() {
    if (!_deps.mounted()) return;
    unawaited(loadIptvFavorites());
    unawaited(loadIptvListRows());
  }

  Future<void> loadMyWatchlist() => watchlistController.load(
    isCurrent: () => _deps.mounted(),
    onRows: () {
      _deps.setState(() {});
      syncMyWatchlistNodes();
      _deps.autoFocus();
    },
  );

  void syncFavoriteNodes(HomeFavoriteKind kind, int count) =>
      favoriteNodes.sync(
        kind,
        count,
        isCurrent: () => _deps.mounted(),
        onEmpty: _deps.focusContent,
      );

  void syncMyWatchlistNodes() {
    syncFavoriteNodes(
      HomeFavoriteKind.watchlistMovies,
      watchlistMovieItems.length,
    );
    syncFavoriteNodes(
      HomeFavoriteKind.watchlistSeries,
      watchlistSeriesItems.length,
    );
  }

  /// Refresh accepted playlist rows, posters, favourite flags and progress.
  Future<void> loadPlaylistFavorites() => playlistController.load(
    isCurrent: () => _deps.mounted(),
    onRows: () {
      _deps.setState(() {});
      syncPlaylistFavNodes();
      _deps.autoFocus();
    },
  );

  void syncPlaylistFavNodes() =>
      syncFavoriteNodes(HomeFavoriteKind.playlist, playlistItems.length);
}
