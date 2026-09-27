import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/storage_service.dart';
import '../data/home_playlist_repository.dart';

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
