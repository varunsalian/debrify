import '../../../models/stremio_tv/stremio_tv_channel.dart';
import '../models/home_stremio_favorites.dart';

typedef HomeStremioFavoritesRead = ({
  bool hasFavoriteIds,
  HomeStremioFavorites favorites,
});

/// Keeps the existing IDs → parallel preferences → discovery → item-load order.
class HomeStremioFavoritesRepository {
  const HomeStremioFavoritesRepository({
    required Future<Set<String>> Function() favoriteIds,
    required Future<int> Function() rotationMinutes,
    required Future<int> Function() seriesRotationMinutes,
    required Future<List<StremioTvChannel>> Function() discover,
    required Future<void> Function(List<StremioTvChannel>) loadItems,
  }) : _favoriteIds = favoriteIds,
       _rotationMinutes = rotationMinutes,
       _seriesRotationMinutes = seriesRotationMinutes,
       _discover = discover,
       _loadItems = loadItems;

  final Future<Set<String>> Function() _favoriteIds;
  final Future<int> Function() _rotationMinutes;
  final Future<int> Function() _seriesRotationMinutes;
  final Future<List<StremioTvChannel>> Function() _discover;
  final Future<void> Function(List<StremioTvChannel>) _loadItems;

  Future<HomeStremioFavoritesRead?> read({
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    final ids = await _favoriteIds();
    if (!isCurrent()) return null;
    if (ids.isEmpty) {
      return (
        hasFavoriteIds: false,
        favorites: const HomeStremioFavorites.empty(),
      );
    }
    final rotations = await Future.wait([
      _rotationMinutes(),
      _seriesRotationMinutes(),
    ]);
    if (!isCurrent()) return null;
    final all = await _discover();
    if (!isCurrent()) return null;
    final favorites = all.where((channel) => ids.contains(channel.id)).toList();
    await _loadItems(favorites);
    if (!isCurrent()) return null;
    return (
      hasFavoriteIds: true,
      favorites: HomeStremioFavorites(
        channels: [
          for (final channel in favorites)
            HomeStremioFavorite(
              id: channel.id,
              displayName: channel.displayName,
              type: channel.type,
              items: channel.items,
            ),
        ],
        rotationMinutes: rotations[0],
        seriesRotationMinutes: rotations[1],
      ),
    );
  }
}
