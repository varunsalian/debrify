import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_bound_counts_repository.dart';
import '../models/home_catalog_session.dart';
import 'home_board_providers.dart';

final homeBoundCountsProvider = NotifierProvider.autoDispose
    .family<HomeBoundCountsController, Map<String, int>, HomeCatalogSession>(
      HomeBoundCountsController.new,
      retry: (count, error) => null,
      dependencies: [homeBoundCountsRepositoryProvider],
    );

class HomeBoundCountsController extends Notifier<Map<String, int>> {
  HomeBoundCountsController(this.session);
  final HomeCatalogSession session;
  late HomeBoundCountsRepository _repository;
  Map<String, int> _accepted = const {};
  int _generation = 0;

  @override
  Map<String, int> build() {
    _repository = ref.watch(homeBoundCountsRepositoryProvider(session));
    ref.onDispose(() => _generation++);
    return _accepted;
  }

  Map<String, int> get current => ref.mounted ? state : const {};

  Future<void> load({
    required Iterable<String?> ids,
    required bool Function() isCurrent,
    required void Function() onAccepted,
  }) async {
    bool active() =>
        ref.mounted &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!active()) return;
    final generation = ++_generation;
    bool current() => active() && generation == _generation;
    final counts = await _repository.read(ids, isCurrent: current);
    if (!current() || counts == null) return;
    _accepted = counts;
    state = counts;
    if (current()) onAccepted();
  }
}
