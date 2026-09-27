import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/storage_service.dart';
import '../data/home_iptv_favorites_repository.dart';

final homeIptvFavoritesRepositoryProvider =
    Provider<HomeIptvFavoritesRepository>(
      (ref) => HomeIptvFavoritesRepository(
        favorites: () => StorageService.getIptvFavoriteChannels(),
        headers: StorageService.iptvFavoriteHeaders,
      ),
      dependencies: const [],
    );
