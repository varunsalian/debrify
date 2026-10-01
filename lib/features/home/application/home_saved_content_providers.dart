import 'package:debrify/services/storage/debrify_tv_storage.dart';
import 'package:debrify/services/storage/home_rows_storage.dart';
import 'package:debrify/services/storage/iptv_favorites_storage.dart';
import 'package:debrify/services/storage/stremio_tv_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/debrify_tv_repository.dart';
import '../../../services/storage_service.dart';
import '../../../services/stremio_tv_service.dart';
import '../data/home_iptv_favorites_repository.dart';
import '../data/home_iptv_lists_repository.dart';
import '../data/home_playlist_repository.dart';
import '../data/home_stremio_favorites_repository.dart';
import '../data/home_tv_favorites_repository.dart';

final homeTvFavoritesRepositoryProvider = Provider<HomeTvFavoritesRepository>(
  (ref) => HomeTvFavoritesRepository(
    favoriteIds: () => DebrifyTvStorage.getDebrifyTvFavoriteChannelIds(),
    channels: () => DebrifyTvRepository.instance.fetchAllChannels(),
  ),
  dependencies: const [],
);

final homeStremioFavoritesRepositoryProvider =
    Provider<HomeStremioFavoritesRepository>(
      (ref) => HomeStremioFavoritesRepository(
        favoriteIds: () => StremioTvStorage.getStremioTvFavoriteChannelIds(),
        rotationMinutes: () => StremioTvStorage.getStremioTvRotationMinutes(),
        seriesRotationMinutes: () =>
            StremioTvStorage.getStremioTvSeriesRotationMinutes(),
        discover: () => StremioTvService.instance.discoverChannels(),
        loadItems: (channels) =>
            StremioTvService.instance.loadAllChannelItems(channels),
      ),
      dependencies: const [],
    );

final homeIptvFavoritesRepositoryProvider =
    Provider<HomeIptvFavoritesRepository>(
      (ref) => HomeIptvFavoritesRepository(
        favorites: () => IptvFavoritesStorage.getIptvFavoriteChannels(),
        headers: IptvFavoritesStorage.iptvFavoriteHeaders,
      ),
      dependencies: const [],
    );

final homeIptvListsRepositoryProvider = Provider<HomeIptvListsRepository>(
  (ref) => HomeIptvListsRepository(
    extras: HomeRowsStorage.getHomeExtraRows,
    lists: () async => [
      for (final meta in await IptvFavoritesStorage.getIptvLists())
        (id: meta.id, title: meta.name, isFavorites: meta.isFavorites),
    ],
    channels: IptvFavoritesStorage.getIptvListChannels,
    headers: IptvFavoritesStorage.iptvFavoriteHeaders,
    favoritesListId: IptvFavoritesStorage.iptvFavoritesListId,
  ),
  dependencies: const [],
);

/// The existing storage API already supplies a typed, ordered list.
final homeWatchlistReaderProvider =
    Provider<Future<List<StremioMeta>> Function()>(
      (ref) => StorageService.getMyWatchlistItems,
      dependencies: const [],
    );

final homePlaylistRepositoryProvider = Provider<HomePlaylistRepository>(
  (ref) => const HomePlaylistRepository(
    items: StorageService.getPlaylistItemsRaw,
    favorites: StorageService.getPlaylistFavoriteKeys,
    posters: StorageService.getAllPlaylistPosterOverrides,
    posterKey: StorageService.getPlaylistItemUniqueKey,
    dedupeKey: StorageService.computePlaylistDedupeKey,
    progress: StorageService.buildPlaylistProgressMap,
  ),
  dependencies: const [],
);
