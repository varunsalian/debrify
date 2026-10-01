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
    favoriteIds: () => StorageService.getDebrifyTvFavoriteChannelIds(),
    channels: () => DebrifyTvRepository.instance.fetchAllChannels(),
  ),
  dependencies: const [],
);

final homeStremioFavoritesRepositoryProvider =
    Provider<HomeStremioFavoritesRepository>(
      (ref) => HomeStremioFavoritesRepository(
        favoriteIds: () => StorageService.getStremioTvFavoriteChannelIds(),
        rotationMinutes: () => StorageService.getStremioTvRotationMinutes(),
        seriesRotationMinutes: () =>
            StorageService.getStremioTvSeriesRotationMinutes(),
        discover: () => StremioTvService.instance.discoverChannels(),
        loadItems: (channels) =>
            StremioTvService.instance.loadAllChannelItems(channels),
      ),
      dependencies: const [],
    );

final homeIptvFavoritesRepositoryProvider =
    Provider<HomeIptvFavoritesRepository>(
      (ref) => HomeIptvFavoritesRepository(
        favorites: () => StorageService.getIptvFavoriteChannels(),
        headers: StorageService.iptvFavoriteHeaders,
      ),
      dependencies: const [],
    );

final homeIptvListsRepositoryProvider = Provider<HomeIptvListsRepository>(
  (ref) => HomeIptvListsRepository(
    extras: StorageService.getHomeExtraRows,
    lists: () async => [
      for (final meta in await StorageService.getIptvLists())
        (id: meta.id, title: meta.name, isFavorites: meta.isFavorites),
    ],
    channels: StorageService.getIptvListChannels,
    headers: StorageService.iptvFavoriteHeaders,
    favoritesListId: StorageService.iptvFavoritesListId,
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
  (ref) => HomePlaylistRepository(
    items: StorageService.getPlaylistItemsRaw,
    favorites: StorageService.getPlaylistFavoriteKeys,
    posters: StorageService.getAllPlaylistPosterOverrides,
    posterKey: StorageService.getPlaylistItemUniqueKey,
    dedupeKey: StorageService.computePlaylistDedupeKey,
    progress: StorageService.buildPlaylistProgressMap,
  ),
  dependencies: const [],
);
