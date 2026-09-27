import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/debrify_tv_repository.dart';
import '../../../services/storage_service.dart';
import '../data/home_tv_favorites_repository.dart';

final homeTvFavoritesRepositoryProvider = Provider<HomeTvFavoritesRepository>(
  (ref) => HomeTvFavoritesRepository(
    favoriteIds: () => StorageService.getDebrifyTvFavoriteChannelIds(),
    channels: () => DebrifyTvRepository.instance.fetchAllChannels(),
  ),
  dependencies: const [],
);
