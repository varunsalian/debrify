import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/debrify_tv/channel.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_tv_favorites_repository.dart';
import '../models/home_favorites_session.dart';
import 'home_saved_content_providers.dart';

final homeTvFavoritesProvider = NotifierProvider.autoDispose
    .family<
      HomeTvFavoritesController,
      List<DebrifyTvChannel>,
      HomeFavoritesSession
    >(
      HomeTvFavoritesController.new,
      retry: (count, error) => null,
      dependencies: [homeTvFavoritesRepositoryProvider],
    );

/// Owns accepted channels and refresh retirement. Focus and navigation stay in
/// the view; construction does not read storage or the channel database.
class HomeTvFavoritesController extends Notifier<List<DebrifyTvChannel>> {
  HomeTvFavoritesController(this.session);
  final HomeFavoritesSession session;
  late HomeTvFavoritesRepository _repository;
  int _generation = 0;

  @override
  List<DebrifyTvChannel> build() {
    _repository = ref.watch(homeTvFavoritesRepositoryProvider);
    ref.onDispose(() => _generation++);
    return const [];
  }

  List<DebrifyTvChannel> get current => ref.mounted ? state : const [];

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
      state = result.channels;
      onRows(result.hasFavoriteIds);
    } catch (_) {
      // Preserve the existing silent policy: leave previously accepted rows.
    }
  }
}
