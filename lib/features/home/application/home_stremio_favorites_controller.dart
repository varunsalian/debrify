import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_tv_rotation.dart';
import '../../../models/stremio_tv/stremio_tv_now_playing.dart';
import '../data/home_stremio_favorites_repository.dart';
import '../models/home_favorites_session.dart';
import '../models/home_stremio_favorites.dart';
import 'home_saved_content_providers.dart';

final homeStremioFavoritesProvider = NotifierProvider.autoDispose
    .family<
      HomeStremioFavoritesController,
      HomeStremioFavorites,
      HomeFavoritesSession
    >(
      HomeStremioFavoritesController.new,
      retry: (count, error) => null,
      dependencies: [homeStremioFavoritesRepositoryProvider],
    );

/// Owns accepted snapshots, while the view owns focus, repaint and navigation.
class HomeStremioFavoritesController extends Notifier<HomeStremioFavorites> {
  HomeStremioFavoritesController(this.session);
  final HomeFavoritesSession session;
  late HomeStremioFavoritesRepository _repository;
  int _generation = 0;

  @override
  HomeStremioFavorites build() {
    _repository = ref.watch(homeStremioFavoritesRepositoryProvider);
    ref.onDispose(() => _generation++);
    return const HomeStremioFavorites.empty();
  }

  HomeStremioFavorites get current =>
      ref.mounted ? state : const HomeStremioFavorites.empty();

  StremioTvNowPlaying? playingAt(HomeStremioFavorite channel, DateTime now) {
    final favorites = current;
    return stremioTvPlayingAt(
      channelId: channel.id,
      items: channel.items,
      now: now,
      rotationMinutes: channel.type == 'series'
          ? favorites.seriesRotationMinutes
          : favorites.rotationMinutes,
    );
  }

  Future<void> load({
    required bool Function() isCurrent,
    required void Function(bool hasFavoriteIds) onRows,
  }) async {
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return;
    try {
      final result = await _repository.read(isCurrent: current);
      if (result == null || !current()) return;
      // Empty IDs clear rows without changing the last accepted rotation values.
      state = result.hasFavoriteIds
          ? result.favorites
          : state.withoutChannels();
      onRows(result.hasFavoriteIds);
    } catch (_) {
      // Existing behavior retains accepted rows and rotations without retry.
    }
  }
}
