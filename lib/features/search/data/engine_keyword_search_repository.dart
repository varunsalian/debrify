import '../../../models/torrent.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/torrent_service.dart';
import '../models/keyword_search_result.dart';
import 'keyword_search_repository.dart';

typedef KeywordEngineSearch =
    Future<Map<String, dynamic>> Function(
      String query, {
      KeywordBatch? onBatch,
    });

/// Borrows the existing engine service, including its fan-out, limits, timeouts,
/// authorization and deterministic merge. No second retry or transport layer.
class EngineKeywordSearchRepository implements KeywordSearchRepository {
  final ProfileSessionOwner owner;
  final KeywordEngineSearch searchEngines;

  const EngineKeywordSearchRepository({
    required this.owner,
    this.searchEngines = TorrentService.searchAllEngines,
  });

  @override
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  @override
  Future<KeywordSearchResult> search(
    String query, {
    required KeywordBatch onBatch,
  }) async {
    if (!isCurrent) throw StateError('Retired keyword search session');
    Future<Map<String, dynamic>> run() => searchEngines(
      query,
      onBatch: (source, batch) {
        if (isCurrent) onBatch(source, List.unmodifiable(batch));
      },
    );
    final scope = owner.scope;
    final result = await (scope == null
        ? run()
        : ProfileRuntime.withCapturedScope(scope, run));
    final errors = result['engineErrors'];
    final counts = result['engineCounts'];
    return KeywordSearchResult(
      torrents: (result['torrents'] as List).cast<Torrent>(),
      anyEngineRan:
          (counts is Map && counts.isNotEmpty) ||
          (errors is Map && errors.isNotEmpty),
      hasEngineErrors: errors is Map && errors.isNotEmpty,
    );
  }

  @override
  List<Torrent> merge(List<List<Torrent>> batches) =>
      TorrentService.mergeSearchResults(batches);
}
