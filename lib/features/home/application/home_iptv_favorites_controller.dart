import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/iptv_playlist.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_iptv_favorites_repository.dart';
import '../models/home_favorites_session.dart';
import 'home_saved_content_providers.dart';

final homeIptvFavoritesProvider = NotifierProvider.autoDispose
    .family<
      HomeIptvFavoritesController,
      List<IptvChannel>,
      HomeFavoritesSession
    >(
      HomeIptvFavoritesController.new,
      retry: (count, error) => null,
      dependencies: [homeIptvFavoritesRepositoryProvider],
    );

/// Owns accepted favourites; focus and playback remain view responsibilities.
class HomeIptvFavoritesController extends Notifier<List<IptvChannel>> {
  HomeIptvFavoritesController(this.session);
  final HomeFavoritesSession session;
  late HomeIptvFavoritesRepository _repository;
  int _generation = 0;

  @override
  List<IptvChannel> build() {
    _repository = ref.watch(homeIptvFavoritesRepositoryProvider);
    ref.onDispose(() => _generation++);
    return const [];
  }

  List<IptvChannel> get current => ref.mounted ? state : const [];

  Future<void> load({
    required bool Function() isCurrent,
    required void Function(bool hasFavorites) onRows,
  }) async {
    final generation = ++_generation;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!current()) return;
    try {
      final channels = await _repository.read(isCurrent: current);
      if (channels == null || !current()) return;
      state = channels;
      onRows(channels.isNotEmpty);
    } catch (_) {
      // Preserve accepted rows after failed reads or malformed saved metadata.
    }
  }
}
