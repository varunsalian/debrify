import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/torrent.dart';
import '../data/source_cache_repository.dart';
import '../models/source_cache_state.dart';
import '../models/sources_session.dart';
import 'source_cache_dependencies.dart';
import 'source_seasons_dependencies.dart';

final sourceCacheProvider = NotifierProvider.autoDispose
    .family<SourceCacheController, SourceCacheState, SourcesSession>(
      SourceCacheController.new,
      retry: (count, error) => null,
    );

class SourceCacheController extends Notifier<SourceCacheState> {
  SourceCacheController(this.session);
  final SourcesSession session;
  late SourceCacheRepository _repository;
  SourceCacheSession? _config;
  final Set<String> _checked = {};
  int _generation = 0;
  int _configGeneration = 0;

  void _reset() {
    _generation++;
    _configGeneration++;
    _config = null;
    _checked.clear();
  }

  @override
  SourceCacheState build() {
    _repository = ref.watch(sourceCacheRepositoryProvider(session));
    ref.watch(sourcesSessionActiveProvider(session));
    _reset();
    ref.onDispose(_reset);
    return const SourceCacheState.empty();
  }

  bool get _current => ref.mounted && _repository.isCurrent;
  bool _accept(int generation) => _current && generation == _generation;

  Future<bool> configure() async {
    if (!_current) return false;
    final generation = ++_configGeneration;
    try {
      final config = await _repository.open();
      if (!_current || generation != _configGeneration) return false;
      _config = config;
      state = state.copyWith(
        torboxEnabled: config.torboxEnabled,
        premiumizeEnabled: config.premiumizeEnabled,
      );
      return true;
    } catch (_) {
      if (!_current || generation != _configGeneration) return false;
      rethrow;
    }
  }

  void beginSearch() {
    if (!_current) return;
    _generation++;
    _checked.clear();
    state = SourceCacheState.empty(
      repaintRevision: state.repaintRevision,
      torboxEnabled: state.torboxEnabled,
      premiumizeEnabled: state.premiumizeEnabled,
    );
  }

  Future<void> check(List<Torrent> rows) async {
    final generation = _generation;
    final config = _config;
    if (!_accept(generation) ||
        config == null ||
        (!config.torboxEnabled && !config.premiumizeEnabled)) {
      return;
    }
    final hashes = <String>[];
    for (final torrent in rows) {
      if (!torrent.hasRealInfoHash) continue;
      final hash = torrent.infohash.trim().toLowerCase();
      if (hash.isEmpty || _checked.contains(hash)) continue;
      hashes.add(hash);
    }
    if (hashes.isEmpty) return;
    var tbDone = !config.torboxEnabled;
    var pmDone = !config.premiumizeEnabled;
    if (config.torboxEnabled) {
      try {
        final cached = await config.torbox(hashes);
        if (!_accept(generation)) return;
        state = state.copyWith(
          torbox: {
            ...state.torbox,
            for (final hash in hashes) hash: cached.contains(hash),
          },
        );
        tbDone = true;
      } catch (_) {
        /* A later batch/finish sweep retries unresolved hashes. */
      }
    }
    if (!_accept(generation)) return;
    if (config.premiumizeEnabled) {
      try {
        final cached = await config.premiumize(hashes);
        if (!_accept(generation)) return;
        state = state.copyWith(
          premiumize: {
            ...state.premiumize,
            for (var i = 0; i < hashes.length; i++)
              hashes[i]: i < cached.length && cached[i],
          },
        );
        pmDone = true;
      } catch (_) {
        /* Keep any successful TorBox badges. */
      }
    }
    if (!_accept(generation)) return;
    if (tbDone && pmDone) _checked.addAll(hashes);
    state = state.copyWith(repaintRevision: state.repaintRevision + 1);
  }
}
