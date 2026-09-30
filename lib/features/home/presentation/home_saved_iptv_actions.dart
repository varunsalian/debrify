import 'package:flutter/material.dart';
import '../../../models/iptv_playlist.dart';
import '../../../screens/iptv/xtream_series_detail.dart';
import '../../../services/profiles/connection_resource_service.dart'
    show ResourceAuthorizationException;
import '../data/home_iptv_favorites_repository.dart';

typedef HomeSavedIptvDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  bool Function() isTelevision,
  void Function(BuildContext, String, IptvChannel, bool) launch,
});

/// Saved IPTV list/favorite dispatch and the existing concurrent-launch latch.
class HomeSavedIptvActions {
  HomeSavedIptvActions(this._deps);
  final HomeSavedIptvDeps _deps;

  /// Play an IPTV custom-list entry by CONTENT TYPE — a list can hold VOD and
  /// collapsed series alongside live channels, and each routes differently
  /// (mirroring [IptvCwRouter]): live → the favourites-row live launch; VOD →
  /// watch-record + direct launch (the player restores resume by URL); an
  /// `xtream-series://` sentinel → the merged Xtream series page.
  Future<void> playIptvListChannel(IptvChannel channel) async {
    if (channel.url.startsWith('xtream-series://')) {
      return openIptvListSeries(channel);
    }
    if (!channel.isLive) {
      // Remember on-demand plays so the IPTV Continue Watching shelf can
      // rebuild the row later — recorded BEFORE the launch (the player
      // process can be killed outright on TV), same as the IPTV page.
      await HomeIptvFavoritesRepository.recordWatch(channel);
      if (!_deps.mounted()) return;
    }
    await playIptvChannel(channel);
  }

  /// A collapsed series sentinel stored in a list: resolve its Xtream origin
  /// and open the merged series page (the episode list / Resume plays from
  /// there) — the sentinel URL itself is not a stream.
  Future<List<IptvPlaylist>?> readIptvPlaylistsForAction() async {
    try {
      return await HomeIptvFavoritesRepository.playlists();
    } on ResourceAuthorizationException {
      if (_deps.mounted()) {
        ScaffoldMessenger.of(_deps.context()).showSnackBar(
          const SnackBar(
            content: Text('IPTV is unavailable. Please retry or sign in.'),
          ),
        );
      }
      return null;
    }
  }

  Future<void> openIptvListSeries(IptvChannel channel) async {
    // xtream-series://<originId>/<seriesId>
    final rest = channel.url.substring('xtream-series://'.length);
    final slash = rest.indexOf('/');
    final originId = slash < 0
        ? (channel.attributes['list_playlist_id'] ?? '')
        : rest.substring(0, slash);
    final seriesId = slash < 0 ? rest : rest.substring(slash + 1);
    if (seriesId.isEmpty) return;
    final playlists = await readIptvPlaylistsForAction();
    if (!_deps.mounted() || playlists == null) return;
    IptvPlaylist? origin;
    for (final p in playlists) {
      if (p.id == originId && p.isXtreamCodes) {
        origin = p;
        break;
      }
    }
    if (origin == null) {
      ScaffoldMessenger.of(_deps.context()).showSnackBar(
        const SnackBar(
          content: Text("This series' provider is no longer available"),
        ),
      );
      return;
    }
    await openXtreamSeries(
      _deps.context(),
      playlist: origin,
      series: IptvChannel(
        name: channel.name,
        url: channel.url,
        logoUrl: channel.logoUrl,
        group: channel.group ?? channel.name,
        contentType: 'series',
        attributes: {
          'series_id': seriesId,
          if (originId.isNotEmpty) 'series_playlist_id': originId,
        },
      ),
      isTelevision: _deps.isTelevision(),
    );
  }

  /// Play an IPTV favourite. Unlike the TV channels there's no bridge/tab
  /// handoff — the stream launches directly in the player (same as Home).
  /// Stremio-addon favourites carry a stremio-tv:// key instead of a stream
  /// URL — resolve it first, and hand the channel through the IPTV path so
  /// both players can walk the remaining candidates if the first one dies.
  /// Latch across the resolve window — repeated OK presses while a Stremio
  /// favourite resolves must not stack player launches.
  bool iptvFavLaunching = false;

  Future<void> playIptvChannel(IptvChannel channel) async {
    if (iptvFavLaunching) return;
    iptvFavLaunching = true;
    try {
      var videoUrl = channel.url;
      final isStremio = HomeIptvFavoritesRepository.isStremioChannelUrl(
        channel.url,
      );
      if (isStremio) {
        // Explicit play intent: bypass a cached-empty resolve and explain an
        // empty answer specifically (addon unreachable vs. no streams).
        final candidates = await HomeIptvFavoritesRepository.resolveCandidates(
          channel.url,
          refreshIfEmpty: true,
        );
        if (!_deps.mounted()) return;
        if (candidates.isEmpty) {
          ScaffoldMessenger.of(_deps.context()).showSnackBar(
            SnackBar(
              content: Text(
                HomeIptvFavoritesRepository.unplayableMessage(
                  channel.url,
                  channel.name,
                ),
              ),
            ),
          );
          return;
        }
        videoUrl = candidates.first.url;
      }
      _deps.launch(_deps.context(), videoUrl, channel, isStremio);
    } finally {
      iptvFavLaunching = false;
    }
  }
}
