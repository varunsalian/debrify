import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent.dart';
import '../data/keyword_cache_repository.dart';
import '../models/keyword_cache_state.dart';
import '../models/search_session.dart';
import 'keyword_cache_dependencies.dart';
import 'search_session_provider.dart';

final keywordCacheProvider = NotifierProvider.autoDispose
    .family<KeywordCacheController, KeywordCacheState, SearchSession>(
      KeywordCacheController.new,
      retry: (count, error) => null,
    );

/// Owns cache work for one keyword workflow. The request token comes from that
/// workflow; a private generation also rejects work across provider rebuilds.
class KeywordCacheController extends Notifier<KeywordCacheState> {
  KeywordCacheController(this.session);
  final SearchSession session;
  late KeywordCacheRepository _repository;
  KeywordCacheSession? _cacheSession;
  final Set<String> _checked = {};
  final List<Future<void>> _pending = [];
  int _request = -1;
  int _generation = 0;
  bool _torboxRan = false;
  bool _initialized = false;

  @override
  KeywordCacheState build() {
    _repository = ref.watch(keywordCacheRepositoryProvider(session));
    final active = ref.watch(searchSessionActiveProvider(session));
    _resetWork();
    ref.onDispose(_resetWork);
    final initial = !_initialized && active
        ? session.initialKeywordCache
        : const KeywordCacheState.empty();
    _initialized = true;
    return initial;
  }

  void _resetWork() {
    _generation++;
    _cacheSession = null;
    _checked.clear();
    _pending.clear();
    _torboxRan = false;
  }

  bool _accepts(int request, int generation) =>
      ref.mounted &&
      request == _request &&
      generation == _generation &&
      _repository.isCurrent;

  Future<bool> begin(int request) async {
    if (!_repository.isCurrent) return false;
    _resetWork();
    _request = request;
    final generation = _generation;
    state = const KeywordCacheState.empty();
    final config = await _repository.open();
    if (!_accepts(request, generation)) return false;
    _cacheSession = config;
    return true;
  }

  void clear(int request) {
    _resetWork();
    _request = request;
    // Existing field-clear behavior retained the hidden cached-only flag until
    // the next search reset it. An empty result set cannot display its banner.
    state = KeywordCacheState.empty(cachedOnly: state.cachedOnly);
  }

  void checkBatch(List<Torrent> torrents, int request) {
    if (!_accepts(request, _generation)) return;
    _pending.add(check(torrents, request));
  }

  Future<void> check(List<Torrent> torrents, int request) async {
    final generation = _generation;
    final config = _cacheSession;
    if (config == null || !_accepts(request, generation)) return;
    final hashes = <String>[];
    for (final torrent in torrents) {
      final hash = torrent.infohash.toLowerCase();
      // Preserve duplicates and whitespace: legacy dispatch only lowercased.
      if (hash.isEmpty || _checked.contains(hash)) continue;
      hashes.add(hash);
    }
    if (hashes.isEmpty) return;
    final additions = <String, List<String>>{};
    var tbDone = !config.torboxEnabled;
    var pmDone = !config.premiumizeEnabled;
    var tbOk = false;
    if (config.torboxEnabled) {
      try {
        final cached = await config.torbox(hashes);
        tbDone = true;
        tbOk = true;
        for (final hash in cached) {
          (additions[hash] ??= []).add('TB');
        }
      } catch (_) {
        /* Remains eligible for a later batch/completion retry. */
      }
    }
    if (config.premiumizeEnabled) {
      try {
        final cached = await config.premiumize(hashes);
        pmDone = true;
        for (var i = 0; i < hashes.length && i < cached.length; i++) {
          if (cached[i]) (additions[hashes[i]] ??= []).add('PM');
        }
      } catch (_) {
        /* Retain successful badges without confirming this hash. */
      }
    }
    if (!_accepts(request, generation)) return;
    if (tbOk) _torboxRan = true;
    if (tbDone && pmDone) _checked.addAll(hashes);
    // Legacy addAll replaced labels for a repeated key, while keeping unrelated
    // hashes. Preserve that contract rather than silently unioning the labels.
    state = KeywordCacheState(
      badges: {...state.badges, ...additions},
      cachedOnly: state.cachedOnly,
    );
  }

  /// True only when cached-only filtering changed and presentation must
  /// reconcile its visible rows/focus. Badges alone never require that step.
  Future<bool> finish(List<Torrent> full, int request) async {
    final generation = _generation;
    try {
      await Future.wait(List<Future<void>>.of(_pending));
    } catch (_) {}
    if (!_accepts(request, generation)) return false;
    await check(full, request);
    if (!_accepts(request, generation)) return false;
    final cachedOnly =
        _torboxRan && !(_cacheSession?.otherProviderActive ?? false);
    final changed = cachedOnly != state.cachedOnly;
    state = KeywordCacheState(badges: state.badges, cachedOnly: cachedOnly);
    return changed;
  }
}
