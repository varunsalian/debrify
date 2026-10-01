import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../models/home_favorites_session.dart';
import '../models/home_watchlist.dart';
import 'home_saved_content_providers.dart';

final homeWatchlistProvider = NotifierProvider.autoDispose
    .family<HomeWatchlistController, HomeWatchlist, HomeFavoritesSession>(
      HomeWatchlistController.new,
      retry: (count, error) => null,
      dependencies: [homeWatchlistReaderProvider],
    );

/// Owns accepted grouping and request retirement; focus and actions stay in UI.
class HomeWatchlistController extends Notifier<HomeWatchlist> {
  HomeWatchlistController(this.session);
  final HomeFavoritesSession session;
  late Future<List<StremioMeta>> Function() _read;
  int _generation = 0;

  @override
  HomeWatchlist build() {
    _read = ref.watch(homeWatchlistReaderProvider);
    ref.onDispose(() => _generation++);
    return const HomeWatchlist.empty();
  }

  HomeWatchlist get current =>
      ref.mounted ? state : const HomeWatchlist.empty();

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
      final items = await _read();
      if (!current()) return;
      state = HomeWatchlist.fromItems(items);
      onRows();
    } catch (_) {
      // Preserve accepted shelves after a local read failure, without retry.
    }
  }
}
