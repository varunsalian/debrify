import 'package:flutter/material.dart';

import '../../../models/iptv_playlist.dart';
import '../../../widgets/home/spotlight_board.dart';
import '../application/home_stage_metadata.dart';
import '../models/home_favorite_row_ref.dart';
import '../models/home_stremio_favorites.dart';
import 'home_display_section.dart';
import 'home_favorite_focus.dart';
import 'home_hero_live.dart';
import 'home_hero_preview.dart';
import 'home_hero_section.dart';
import 'home_playlist_actions.dart';
import 'home_saved_content_section.dart';
import 'home_saved_iptv_actions.dart';
import 'home_spotlight_favorites.dart';
import 'home_stage_favorite_cards.dart';
import 'home_stage_section.dart';
import 'home_watchlist_actions.dart';

/// Saved-content cells and focus-driven preview overrides for stage layouts.
class HomeStageFavorites {
  HomeStageFavorites(
    this._stageSection,
    this._displaySection,
    this._heroSection,
    this._heroPreview,
    this._heroLive,
    this._savedSection,
    this._savedIptv,
    this._watchlistActions,
    this._playlistActions,
    this._focusSidebar,
  );
  final HomeStageSection _stageSection;
  final HomeDisplaySection _displaySection;
  final HomeHeroSection _heroSection;
  final HomeHeroPreview _heroPreview;
  final HomeHeroLive _heroLive;
  final HomeSavedContentSection _savedSection;
  final HomeSavedIptvActions _savedIptv;
  final HomeWatchlistActions _watchlistActions;
  final HomePlaylistActions _playlistActions;
  final VoidCallback _focusSidebar;

  /// Stage override while a favourites cell has focus (see
  /// [HomeFavoriteFocus]). A ValueNotifier — NOT setState — so scrubbing along
  /// a favourites rail repaints only the stage layers that listen (art +
  /// identity), never the whole board (the hero pipeline's own pattern).
  final ValueNotifier<HomeFavoriteFocus?> canvasFavFocus =
      ValueNotifier<HomeFavoriteFocus?>(null);

  /// A Canvas favourites cell took focus: remember the column, stop any
  /// catalog trailer machinery (a PENDING hero swap firing later would start
  /// a full-bleed trailer of an unrelated title under favourites browsing),
  /// drive the live preview for IPTV, and hand the stage the favourite's own
  /// art + name.
  void canvasFavFocused(
    String railKey,
    int col,
    HomeFavoriteFocus focus, {
    IptvChannel? liveChannel,
  }) {
    _stageSection.canvasCols[railKey] = col;
    _stageSection.stageCol.value = col;
    // Atrium's two-row window needs to know which row owns focus (favourites
    // cells don't go through a HomeBoardCell onFocused), and favourites only
    // ever live in Tonight's RAIL zone, never its Continue queue.
    _stageSection.atriumFocusedRailKey.value = railKey;
    _stageSection.tonightZoneIsQueue = false;
    _heroSection.heroSwap.cancel();
    _heroPreview.clearHeroTrailer();
    if (liveChannel != null && _displaySection.stageWantsLivePreview) {
      _heroLive.setHeroLiveIptv(liveChannel);
    } else {
      _heroLive.clearHeroLiveIptv();
    }
    canvasFavFocus.value = focus;
  }

  /// One favourites cell on the Canvas shelf — the SAME [HomeFavoriteCell] +
  /// [HomeArtPoster] stack the classic rows use (identical art, badges, hold
  /// behaviour and open actions), with UP/DOWN rewired to rail switching and
  /// focus driving the Canvas stage override (and the full-bleed live
  /// preview, for IPTV).
  Widget canvasFavCell(
    HomeFavoriteRowRef ref,
    String railKey,
    int col, {
    VoidCallback? onUp,
    VoidCallback? onDown,
    VoidCallback? onLeft,
    VoidCallback? onRight,
    VoidCallback? onUpHold,
    VoidCallback? onDownHold,
  }) {
    final cells = HomeStageFavoriteCards(
      nodes: _savedSection.favNodesFor(ref),
      column: col,
      showTitle: !_displaySection.hideHomeCardTitlesAndRatings,
      onLeftEdge: _focusSidebar,
      onUp: onUp ?? () => _stageSection.stageSwitchRail(-1),
      onDown: onDown ?? () => _stageSection.stageSwitchRail(1),
      onLeft: onLeft,
      onRight: onRight,
      onUpHold: onUpHold,
      onDownHold: onDownHold,
      onFocused: (focus, liveChannel) =>
          canvasFavFocused(railKey, col, focus, liveChannel: liveChannel),
    );
    if (ref.isIptvList) {
      final row = _savedSection.iptvListRows[ref.list];
      final channel = row.channels[col];
      return cells.iptv(
        channel,
        subtitle: () => 'IPTV · ${row.title.toUpperCase()}',
        previewLive: channel.isLive,
        onOpen: () => _savedIptv.playIptvListChannel(channel),
      );
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
      case HomeFavoriteKind.watchlistSeries:
        final items = ref.kind == HomeFavoriteKind.watchlistMovies
            ? _savedSection.watchlistMovieItems
            : _savedSection.watchlistSeriesItems;
        final item = items[col];
        return cells.watchlist(
          item,
          onOpen: () => _watchlistActions.openMyWatchlistItem(item),
        );
      case HomeFavoriteKind.iptv:
        final channel = _savedSection.iptvFavChannels[col];
        return cells.iptv(
          channel,
          subtitle: () => 'IPTV · FAVORITES',
          previewLive: true,
          onOpen: () => _savedIptv.playIptvChannel(channel),
        );
      case HomeFavoriteKind.debrify:
        final channel = _savedSection.tvFavChannels[col];
        return cells.debrify(
          channel,
          onOpen: () => _savedSection.playChannel(channel),
        );
      case HomeFavoriteKind.stremio:
        final channel = _savedSection.stvFavChannels[col];
        return cells.stremio(
          channel,
          item: _savedSection.stvNowPlaying(channel)?.item,
          onOpen: () => _savedSection.playStremioTvChannel(channel),
        );
      case HomeFavoriteKind.playlist:
        final item = _savedSection.playlistItems[col];
        return cells.playlist(
          item,
          progress: _savedSection.playlistController.current.progressFor(item),
          onOpen: () => _playlistActions.onPlaylistItemTap(item),
        );
    }
  }

  /// A favourites rail as Spotlight cards.
  ///
  /// The four kinds are NOT the same shape. A playlist is a container rather
  /// than a title, so it keeps the poster it was given (or its override) and
  /// says how many items it holds. The three channel kinds carry LOGOS — wide,
  /// frequently transparent marks — which a 2:3 crop cuts in half, so they get
  /// a square tile that contains the art on a plate instead of filling with it.
  SpotlightShelf spotlightFavShelf(HomeFavoriteRowRef ref, {String? id}) {
    final nodes = _savedSection.favNodesFor(ref);
    if (ref.isIptvList) {
      final row = _savedSection.iptvListRows[ref.list];
      return buildSpotlightIptvFavorites(
        id: id,
        title: row.title,
        nodes: nodes,
        channels: row.channels,
        landscape: _displaySection.homeLandscapeCards,
        previewVolume: () => _heroPreview.heroTrailerVolume,
        onOpen: _savedIptv.playIptvListChannel,
      );
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
      case HomeFavoriteKind.watchlistSeries:
        final movies = ref.kind == HomeFavoriteKind.watchlistMovies;
        return buildSpotlightWatchlist(
          id: id,
          nodes: nodes,
          items: movies
              ? _savedSection.watchlistMovieItems
              : _savedSection.watchlistSeriesItems,
          movies: movies,
          landscape: _displaySection.homeLandscapeCards,
          onOpen: _watchlistActions.openMyWatchlistItem,
        );
      case HomeFavoriteKind.playlist:
        return buildSpotlightPlaylists(
          id: id,
          nodes: nodes,
          items: _savedSection.playlistItems,
          progress: _savedSection.playlistController.current.progressFor,
          onOpen: _playlistActions.onPlaylistItemTap,
        );
      case HomeFavoriteKind.iptv:
        return buildSpotlightIptvFavorites(
          id: id,
          title: 'IPTV Favourites',
          nodes: nodes,
          channels: _savedSection.iptvFavChannels,
          landscape: _displaySection.homeLandscapeCards,
          previewVolume: () => _heroPreview.heroTrailerVolume,
          onOpen: _savedIptv.playIptvChannel,
        );
      case HomeFavoriteKind.debrify:
        return buildSpotlightDebrifyFavorites(
          id: id,
          nodes: nodes,
          channels: _savedSection.tvFavChannels,
          landscape: _displaySection.homeLandscapeCards,
          onOpen: _savedSection.playChannel,
        );
      case HomeFavoriteKind.stremio:
        return buildSpotlightStremioFavorites(
          id: id,
          nodes: nodes,
          channels: _savedSection.stvFavChannels,
          landscape: _displaySection.homeLandscapeCards,
          artwork: stvFavArt,
          nowPlaying: (channel) => _savedSection.stvNowPlaying(channel)?.item,
          onOpen: _savedSection.playStremioTvChannel,
        );
    }
  }

  /// A Stremio TV favourite's card art: the channel's rotating now-playing
  /// poster — the same resolution the classic and Canvas rails use. Spotlight
  /// landscape mode instead chooses the title's best wide art. Null
  /// (placeholder) until the channel's items load.
  String? stvFavArt(HomeStremioFavorite ch, {bool landscape = false}) {
    final item = _savedSection.stvNowPlaying(ch)?.item;
    if (item == null) return null;
    if (landscape) return homeStageWideArtwork(item);
    return _firstNonEmpty(item.poster, item.background);
  }

  /// First of [a], [b] that is a non-empty string, else null.
  String? _firstNonEmpty(String? a, String? b) {
    if (a != null && a.isNotEmpty) return a;
    if (b != null && b.isNotEmpty) return b;
    return null;
  }
}
