import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/stremio_tv_service.dart';
import '../../../services/storage_service.dart';
import '../data/home_stremio_favorites_repository.dart';

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
