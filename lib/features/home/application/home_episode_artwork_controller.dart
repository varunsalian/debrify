import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../data/home_episode_artwork_repository.dart';
import '../models/home_catalog_session.dart';
import '../models/home_episode_artwork.dart';
import 'home_episode_artwork_dependencies.dart';

final homeEpisodeArtworkProvider = NotifierProvider.autoDispose
    .family<
      HomeEpisodeArtworkController,
      HomeEpisodeArtwork,
      HomeCatalogSession
    >(
      HomeEpisodeArtworkController.new,
      retry: (count, error) => null,
      dependencies: [homeEpisodeArtworkRepositoryProvider],
    );

class HomeEpisodeArtworkController extends Notifier<HomeEpisodeArtwork> {
  HomeEpisodeArtworkController(this.session);
  final HomeCatalogSession session;
  late HomeEpisodeArtworkRepository _repository;
  HomeEpisodeArtwork _accepted = const {};
  final _generations = <HomeEpisodeArtworkSource, int>{};
  final _requests =
      <
        HomeEpisodeArtworkSource,
        ({Map<String, HomeEpisodeReference> refs, bool Function() isCurrent})
      >{};
  int _epoch = 0;

  @override
  HomeEpisodeArtwork build() {
    _repository = ref.watch(homeEpisodeArtworkRepositoryProvider(session));
    ref.onDispose(() => _epoch++);
    return _accepted;
  }

  HomeEpisodeArtwork get current => ref.mounted ? state : const {};
  bool get _active =>
      ref.mounted && session.owner == ProfileSessionMemory.captureOwner();

  void _publish(HomeEpisodeArtwork next) {
    _accepted = Map.unmodifiable(next);
    state = _accepted;
  }

  void clear(HomeEpisodeArtworkSource source) {
    if (!_active) return;
    _generations[source] = (_generations[source] ?? 0) + 1;
    _publish({...state}..remove(source));
  }

  Future<void> load({
    required HomeEpisodeArtworkSource source,
    required Map<String, HomeEpisodeReference> refs,
    required bool Function() isCurrent,
    required void Function() onChanged,
  }) async {
    if (!_active || !isCurrent()) return;
    final request = (
      refs: Map<String, HomeEpisodeReference>.unmodifiable(refs),
      isCurrent: isCurrent,
    );
    _requests[source] = request;
    final generation = (_generations[source] ?? 0) + 1;
    _generations[source] = generation;
    final epoch = _epoch;
    bool active() =>
        _active &&
        epoch == _epoch &&
        generation == _generations[source] &&
        isCurrent();
    if (refs.isEmpty) return;
    final artwork = await _repository.read(request.refs, isCurrent: active);
    if (!active() || artwork == null || artwork.isEmpty) return;
    _publish({
      ...state,
      source: Map.unmodifiable({...?state[source], ...artwork}),
    });
    if (active()) onChanged();
  }

  /// Clear old stills synchronously, then reload only still-current shelves.
  void refresh({
    required bool Function() isCurrent,
    required void Function() onChanged,
  }) {
    if (!_active || !isCurrent()) return;
    final epoch = ++_epoch;
    final requests = _requests.entries.toList();
    _publish(const {});
    if (!_active || !isCurrent() || epoch != _epoch) return;
    onChanged();
    for (final entry in requests) {
      if (!_active || !isCurrent() || epoch != _epoch) return;
      if (entry.value.isCurrent()) {
        unawaited(
          load(
            source: entry.key,
            refs: entry.value.refs,
            isCurrent: entry.value.isCurrent,
            onChanged: onChanged,
          ),
        );
      }
    }
  }
}
