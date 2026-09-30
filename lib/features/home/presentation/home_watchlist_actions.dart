import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../models/iptv_playlist.dart';
import '../../../models/stremio_addon.dart';
import '../../../screens/iptv/xtream_series_detail.dart';
import 'home_item_actions.dart';
import 'home_saved_iptv_actions.dart';

typedef HomeWatchlistActionsDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  bool Function() isTelevision,
  Future<void> Function(StremioMeta) remove,
  Future<void> Function() reload,
  StremioAddon Function(String?) addonForContinue,
  Future<void> Function() refreshAfterPlayback,
});

/// Watchlist opening and the existing unavailable-series removal prompt.
class HomeWatchlistActions {
  HomeWatchlistActions(this._deps, this._iptv, this._items);
  final HomeWatchlistActionsDeps _deps;
  final HomeSavedIptvActions _iptv;
  final HomeItemActions _items;

  Future<void> offerRemoveUnavailableWatchlistItem(
    StremioMeta item, {
    required String message,
  }) async {
    final context = _deps.context();
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Series unavailable'),
        content: Text('$message\n\nRemove it from My Watchlist?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !context.mounted) return;

    try {
      await _deps.remove(item);
      if (!context.mounted) return;
      HapticFeedback.mediumImpact();
      await _deps.reload();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Removed from My Watchlist')),
        );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update My Watchlist")),
      );
    }
  }

  Future<void> openMyWatchlistItem(StremioMeta item) async {
    final xtream = parseXtreamSeriesMetaId(item.id);
    if (xtream != null || item.sourceAddon?.id == 'xtream-iptv') {
      if (xtream == null) {
        await offerRemoveUnavailableWatchlistItem(
          item,
          message: "This series' saved source is invalid.",
        );
        return;
      }

      final playlists = await _iptv.readIptvPlaylistsForAction();
      if (!_deps.mounted() || playlists == null) return;
      IptvPlaylist? playlist;
      for (final candidate in playlists) {
        if (candidate.id == xtream.playlistId && candidate.isXtreamCodes) {
          playlist = candidate;
          break;
        }
      }
      if (playlist == null) {
        await offerRemoveUnavailableWatchlistItem(
          item,
          message: "This series' provider is no longer available.",
        );
        return;
      }

      await openXtreamSeries(
        _deps.context(),
        playlist: playlist,
        series: IptvChannel(
          name: item.name,
          url: 'xtream-series://${xtream.seriesId}',
          logoUrl: item.poster,
          group: item.name,
          contentType: 'series',
          attributes: {
            'series_id': xtream.seriesId,
            'series_playlist_id': xtream.playlistId,
            if (item.background?.isNotEmpty ?? false)
              'backdrop': item.background!,
            if (item.description?.isNotEmpty ?? false)
              'plot': item.description!,
            if (item.year?.isNotEmpty ?? false) 'releaseDate': item.year!,
            if (item.imdbRating != null) 'rating': item.imdbRating!.toString(),
            if (item.genres?.isNotEmpty ?? false)
              'genre': item.genres!.join(', '),
          },
        ),
        isTelevision: _deps.isTelevision(),
      );
      if (_deps.mounted()) await _deps.refreshAfterPlayback();
      return;
    }

    _items.openItem(item, _deps.addonForContinue(item.sourceAddon?.id));
  }
}
