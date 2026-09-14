import 'package:flutter/foundation.dart';

enum HomeRowRefresh {
  tvFavorites,
  stremioTvFavorites,
  watchlist,
  playback,
  playlist,
}

/// Data changes for mounted Home rows, independent of route visibility.
abstract final class HomeRowRefreshSignal {
  static final _listeners = <ValueChanged<Set<HomeRowRefresh>>>[];

  static void addListener(ValueChanged<Set<HomeRowRefresh>> listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  static void removeListener(ValueChanged<Set<HomeRowRefresh>> listener) {
    _listeners.remove(listener);
  }

  static void dispatch(Set<String> keys) {
    final rows = <HomeRowRefresh>{
      if (keys.contains('debrify_tv_favorite_channels_v1') ||
          keys.contains('tv/ch'))
        HomeRowRefresh.tvFavorites,
      if (keys.contains('stremio_tv_favorite_channels_v1') ||
          keys.contains('stremio_tv_disabled_channel_filters_v1') ||
          keys.contains('stremio_tv_local_catalogs_v1') ||
          keys.contains('stremio_tv_rotation_minutes') ||
          keys.contains('stremio_tv_series_rotation_minutes'))
        HomeRowRefresh.stremioTvFavorites,
      if (keys.contains('playlist_poster_overrides_v1') ||
          keys.contains('playback_state_v1'))
        HomeRowRefresh.playlist,
      if (keys.contains('my_watchlist_v1')) HomeRowRefresh.watchlist,
      if (keys.contains('resume') || keys.contains('iptv/watch'))
        HomeRowRefresh.playback,
    };
    if (rows.isEmpty) return;
    final immutableRows = Set<HomeRowRefresh>.unmodifiable(rows);
    for (final listener in List.of(_listeners)) {
      try {
        listener(immutableRows);
      } catch (_) {
        // A disposed consumer must not interrupt a committed sync.
      }
    }
  }
}
