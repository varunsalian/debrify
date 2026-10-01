import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_pikpak_only_repository.dart';
import '../models/home_catalog_session.dart';
import 'home_board_providers.dart';

final homePikpakOnlyProvider = NotifierProvider.autoDispose
    .family<HomePikpakOnlyController, bool, HomeCatalogSession>(
      HomePikpakOnlyController.new,
      retry: (count, error) => null,
      dependencies: [homePikpakOnlyRepositoryProvider],
    );

class HomePikpakOnlyController extends Notifier<bool> {
  HomePikpakOnlyController(this.session);
  final HomeCatalogSession session;
  late HomePikpakOnlyRepository _repository;
  bool _accepted = false;
  int _generation = 0;

  @override
  bool build() {
    _repository = ref.watch(homePikpakOnlyRepositoryProvider(session));
    ref.onDispose(() => _generation++);
    return _accepted;
  }

  bool get current => ref.mounted && state;

  Future<void> load({
    required bool Function() isCurrent,
    required void Function() onChanged,
  }) async {
    bool active() =>
        ref.mounted &&
        session.owner == ProfileSessionMemory.captureOwner() &&
        isCurrent();
    if (!active()) return;
    final generation = ++_generation;
    bool current() => active() && generation == _generation;
    final value = await _repository.read(isCurrent: current);
    if (!current() || value == null || value == state) return;
    _accepted = value;
    state = value;
    if (current()) onChanged();
  }
}
