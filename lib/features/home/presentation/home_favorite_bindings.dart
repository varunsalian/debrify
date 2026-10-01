import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/debrify_tv/channel.dart';
import '../../../models/iptv_playlist.dart';
import '../application/home_iptv_favorites_controller.dart';
import '../application/home_iptv_lists_controller.dart';
import '../application/home_playlist_controller.dart';
import '../application/home_stremio_favorites_controller.dart';
import '../application/home_tv_favorites_controller.dart';
import '../application/home_watchlist_controller.dart';
import '../models/home_favorites_session.dart';
import '../models/home_iptv_list.dart';
import '../models/home_playlist.dart';
import '../models/home_stremio_favorites.dart';
import '../models/home_watchlist.dart';

/// Retains Home's saved-content providers for the route lifetime. Each provider
/// receives its original fresh view identity; controllers own all application state.
class HomeFavoriteBindings {
  HomeFavoriteBindings(
    WidgetRef ref, {
    required HomeFavoritesSession Function() newSession,
  }) {
    final tvSession = newSession();
    _tv = ref.listenManual(homeTvFavoritesProvider(tvSession), (_, _) {});
    tv = ref.read(homeTvFavoritesProvider(tvSession).notifier);
    final stremioSession = newSession();
    _stremio = ref.listenManual(
      homeStremioFavoritesProvider(stremioSession),
      (_, _) {},
    );
    stremio = ref.read(homeStremioFavoritesProvider(stremioSession).notifier);
    final iptvSession = newSession();
    _iptv = ref.listenManual(homeIptvFavoritesProvider(iptvSession), (_, _) {});
    iptv = ref.read(homeIptvFavoritesProvider(iptvSession).notifier);
    final iptvListsSession = newSession();
    _iptvLists = ref.listenManual(
      homeIptvListsProvider(iptvListsSession),
      (_, _) {},
    );
    iptvLists = ref.read(homeIptvListsProvider(iptvListsSession).notifier);
    final watchlistSession = newSession();
    _watchlist = ref.listenManual(
      homeWatchlistProvider(watchlistSession),
      (_, _) {},
    );
    watchlist = ref.read(homeWatchlistProvider(watchlistSession).notifier);
    final playlistSession = newSession();
    _playlist = ref.listenManual(
      homePlaylistProvider(playlistSession),
      (_, _) {},
    );
    playlist = ref.read(homePlaylistProvider(playlistSession).notifier);
  }

  late final ProviderSubscription<List<DebrifyTvChannel>> _tv;
  late final HomeTvFavoritesController tv;
  late final ProviderSubscription<HomeStremioFavorites> _stremio;
  late final HomeStremioFavoritesController stremio;
  late final ProviderSubscription<List<IptvChannel>> _iptv;
  late final HomeIptvFavoritesController iptv;
  late final ProviderSubscription<List<HomeIptvList>> _iptvLists;
  late final HomeIptvListsController iptvLists;
  late final ProviderSubscription<HomeWatchlist> _watchlist;
  late final HomeWatchlistController watchlist;
  late final ProviderSubscription<HomePlaylist> _playlist;
  late final HomePlaylistController playlist;

  void close() {
    _tv.close();
    _stremio.close();
    _iptv.close();
    _iptvLists.close();
    _watchlist.close();
    _playlist.close();
  }
}
