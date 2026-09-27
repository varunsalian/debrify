import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_iptv_lists_repository.dart';
import '../models/home_favorites_session.dart';
import '../models/home_iptv_list.dart';
import 'home_iptv_lists_dependencies.dart';

final homeIptvListsProvider = NotifierProvider.autoDispose
    .family<HomeIptvListsController, List<HomeIptvList>, HomeFavoritesSession>(
      HomeIptvListsController.new,
      retry: (count, error) => null,
      dependencies: [homeIptvListsRepositoryProvider],
    );

/// Publishes complete list snapshots; a failed later read cannot mutate rows
/// already accepted by the view. The view reconciles its nodes before repaint.
class HomeIptvListsController extends Notifier<List<HomeIptvList>> {
  HomeIptvListsController(this.session);
  final HomeFavoritesSession session;
  late HomeIptvListsRepository _repository;
  int _generation = 0;

  @override
  List<HomeIptvList> build() {
    _repository = ref.watch(homeIptvListsRepositoryProvider);
    ref.onDispose(() => _generation++);
    return const [];
  }

  List<HomeIptvList> get current => ref.mounted ? state : const [];

  Future<void> load({
    required bool Function() isCurrent,
    required void Function(List<HomeIptvList>) beforeRows,
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
      if (!result.hasWantedLists && state.isEmpty) return;
      beforeRows(result.rows);
      if (!current()) return;
      state = result.rows;
      onRows();
    } catch (_) {
      // Retain the entire accepted snapshot when any list read/mapping fails.
    }
  }
}
