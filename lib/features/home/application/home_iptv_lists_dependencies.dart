import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/storage_service.dart';
import '../data/home_iptv_lists_repository.dart';

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
