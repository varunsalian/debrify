import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/torrent.dart';
import '../data/keyword_search_repository.dart';
import '../models/keyword_search_state.dart';
import '../models/search_session.dart';
import 'keyword_cache_controller.dart';
import 'keyword_search_dependencies.dart';
import 'search_session_provider.dart';

final keywordSearchProvider = NotifierProvider.autoDispose
    .family<KeywordSearchController, KeywordSearchState, SearchSession>(
      KeywordSearchController.new,
      retry: (count, error) => null,
    );

/// Owns request lifetime and engine publications. Row focus and the temporarily
/// frozen displayed projection remain in presentation during phase 4B.
class KeywordSearchController extends Notifier<KeywordSearchState> {
  KeywordSearchController(this.session);
  final SearchSession session;
  late KeywordSearchRepository _repository;
  late KeywordCacheController _cache;
  int _generation = 0;
  bool _initialized = false;

  @override
  KeywordSearchState build() {
    _repository = ref.watch(keywordSearchRepositoryProvider(session));
    _cache = ref.watch(keywordCacheProvider(session).notifier);
    final active = ref.watch(searchSessionActiveProvider(session));
    ref.onDispose(() => _generation++);
    final query = !_initialized && active ? session.initialKeywordQuery : '';
    _initialized = true;
    return KeywordSearchState.idle(request: _generation, query: query);
  }

  bool get isCurrent => ref.mounted && _repository.isCurrent;
  bool _accepts(int request) => isCurrent && request == _generation;

  void clear() {
    final request = ++_generation;
    _cache.clear(request);
    state = KeywordSearchState.idle(request: request);
  }

  Future<void> search(String query) async {
    if (!isCurrent || query.isEmpty) return;
    final request = ++_generation;
    final batches = <List<Torrent>>[];
    state = KeywordSearchState(
      request: request,
      query: query,
      status: KeywordSearchStatus.searching,
    );
    try {
      // Cache settings must resolve before any engine can publish a batch.
      if (!await _cache.begin(request) || !_accepts(request)) return;
      final result = await _repository.search(
        query,
        onBatch: (source, batch) {
          // Timed-out engine futures can still call back after completion.
          if (!_accepts(request) || !state.searching || batch.isEmpty) return;
          batches.add(List.unmodifiable(batch));
          state = KeywordSearchState(
            request: request,
            query: query,
            status: KeywordSearchStatus.searching,
            results: _repository.merge(batches),
          );
          _cache.checkBatch(batch, request);
        },
      );
      if (!_accepts(request)) return;
      String? error;
      if (result.torrents.isEmpty && !result.anyEngineRan) {
        error =
            'No sources enabled. Turn on at least one source in '
            'Sources, then try again.';
      } else if (result.torrents.isEmpty && result.hasEngineErrors) {
        error =
            'Search failed on all sources. Check your connection or '
            'enabled sources and try again.';
      }
      state = KeywordSearchState(
        request: request,
        query: query,
        status: error == null
            ? KeywordSearchStatus.complete
            : KeywordSearchStatus.failed,
        results: error == null ? result.torrents : null,
        error: error,
      );
    } catch (error) {
      if (!_accepts(request)) return;
      state = KeywordSearchState(
        request: request,
        query: query,
        status: KeywordSearchStatus.failed,
        error: _friendlyError(error),
      );
    }
  }

  // Preserve the legacy network/timeout/generic messages during extraction.
  String _friendlyError(Object error) {
    final message = error.toString().replaceAll('Exception: ', '');
    if (message.contains('SocketException') ||
        message.contains('Failed host lookup')) {
      return 'Network error. Please check your connection.';
    }
    if (message.contains('TimeoutException')) {
      return 'Search timed out. Please try again.';
    }
    if (message.length > 100) return 'Search failed. Please try again.';
    return message;
  }
}
