import 'package:flutter/material.dart';
import '../../../models/debrify_tv/channel.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/stremio_addon.dart';
import '../models/home_favorite_row_ref.dart';
import '../models/home_stremio_favorites.dart';
import 'home_classic_favorite_rows.dart';
import 'home_saved_content_section.dart';
import 'home_playlist_actions.dart';

typedef HomeSavedContentRowsDeps = ({
  HomeClassicFavoriteRows Function(String, List<FocusNode> Function())
  classicRows,
  void Function(DebrifyTvChannel) playChannel,
  void Function(HomeStremioFavorite) playStremio,
  Future<void> Function(IptvChannel) playIptv,
  Future<void> Function(IptvChannel) playIptvList,
  Future<void> Function(StremioMeta) openWatchlist,
});

/// Saved-content row dispatch and the existing Classic renderers' arguments.
class HomeSavedContentRows {
  HomeSavedContentRows(this._deps, this._saved, this._playlist);
  final HomeSavedContentRowsDeps _deps;
  final HomeSavedContentSection _saved;
  final HomePlaylistActions _playlist;

  /// Dispatch to the right favourites-row builder for [ref].
  Widget buildFavRow(HomeFavoriteRowRef ref, String homeRowId) {
    if (ref.isIptvList) {
      return buildIptvListRow(ref, homeRowId);
    }
    switch (ref.kind) {
      case HomeFavoriteKind.watchlistMovies:
      case HomeFavoriteKind.watchlistSeries:
        return buildWatchlistRow(ref, homeRowId);
      case HomeFavoriteKind.iptv:
        return buildIptvFavRow(homeRowId);
      case HomeFavoriteKind.debrify:
        return buildTvFavRow(homeRowId);
      case HomeFavoriteKind.stremio:
        return buildStremioTvFavRow(homeRowId);
      case HomeFavoriteKind.playlist:
        return buildPlaylistFavRow(homeRowId);
    }
  }

  Widget buildWatchlistRow(HomeFavoriteRowRef ref, String homeRowId) {
    final movies = ref.kind == HomeFavoriteKind.watchlistMovies;
    final items = movies
        ? _saved.watchlistMovieItems
        : _saved.watchlistSeriesItems;
    final nodes = movies
        ? _saved.watchlistMovieNodes
        : _saved.watchlistSeriesNodes;
    return _deps
        .classicRows(homeRowId, () => nodes)
        .watchlist(movies: movies, items: items, onOpen: _deps.openWatchlist);
  }

  Widget buildTvFavRow(String homeRowId) => _deps
      .classicRows(homeRowId, () => _saved.tvFavNodes)
      .debrify(
        count: _saved.tvFavChannels.length,
        itemAt: (col) => _saved.tvFavChannels[col],
        onOpen: _deps.playChannel,
      );

  Widget buildStremioTvFavRow(String homeRowId) => _deps
      .classicRows(homeRowId, () => _saved.stvFavNodes)
      .stremio(
        count: _saved.stvFavChannels.length,
        itemAt: (col) => _saved.stvFavChannels[col],
        nowPlaying: (channel) => _saved.stvNowPlaying(channel)?.item,
        onOpen: _deps.playStremio,
      );

  Widget buildIptvFavRow(String homeRowId) => _deps
      .classicRows(homeRowId, () => _saved.iptvFavNodes)
      .iptv(
        title: 'IPTV',
        customList: false,
        count: _saved.iptvFavChannels.length,
        itemAt: (col) => _saved.iptvFavChannels[col],
        onOpen: _deps.playIptv,
      );

  Widget buildIptvListRow(HomeFavoriteRowRef ref, String homeRowId) {
    final row = _saved.iptvListRows[ref.list];
    final nodes = _saved.iptvListFocus.nodesFor(row.listId);
    return _deps
        .classicRows(homeRowId, () => nodes)
        .iptv(
          title: row.title,
          customList: true,
          count: row.channels.length,
          itemAt: (col) => row.channels[col],
          onOpen: _deps.playIptvList,
        );
  }

  Widget buildPlaylistFavRow(String homeRowId) => _deps
      .classicRows(homeRowId, () => _saved.playlistFavNodes)
      .playlist(
        count: _saved.playlistItems.length,
        itemAt: (col) => _saved.playlistItems[col],
        progress: (item) => _saved.playlistController.current.progressFor(item),
        onOpen: _playlist.onPlaylistItemTap,
      );
}
