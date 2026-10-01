import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_playlist_repository.dart';
import '../models/home_favorites_session.dart';
import '../models/home_playlist.dart';
import 'home_saved_content_providers.dart';

final homePlaylistProvider = NotifierProvider.autoDispose
    .family<HomePlaylistController, HomePlaylist, HomeFavoritesSession>(
      HomePlaylistController.new,
      retry: (count, error) => null,
      dependencies: [homePlaylistRepositoryProvider],
    );

class HomePlaylistController extends Notifier<HomePlaylist> {
  HomePlaylistController(this.session);
  final HomeFavoritesSession session;
  late HomePlaylistRepository _repository;
  int _generation = 0;

  @override
  HomePlaylist build() {
    _repository = ref.watch(homePlaylistRepositoryProvider);
    ref.onDispose(() => _generation++);
    return const HomePlaylist.empty();
  }

  HomePlaylist get current => ref.mounted ? state : const HomePlaylist.empty();

  Future<void> load({
    required bool Function() isCurrent,
    required void Function() onRows,
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
      state = result;
      onRows();
    } catch (_) {
      // Retain the last accepted row, favourite flags and progress on failure.
    }
  }
}
