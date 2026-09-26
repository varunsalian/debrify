import 'dart:async';

import 'package:debrify/features/search/data/keyword_search_repository.dart';
import 'package:debrify/features/search/models/keyword_search_result.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/torrent_service.dart';

class FakeKeywordRequest {
  FakeKeywordRequest(this.query, this.onBatch);
  final String query;
  final KeywordBatch onBatch;
  final completion = Completer<KeywordSearchResult>();

  void complete(
    List<Torrent> torrents, {
    bool anyEngineRan = true,
    bool hasEngineErrors = false,
  }) => completion.complete(
    KeywordSearchResult(
      torrents: torrents,
      anyEngineRan: anyEngineRan,
      hasEngineErrors: hasEngineErrors,
    ),
  );
}

class FakeKeywordSearchRepository implements KeywordSearchRepository {
  @override
  bool isCurrent = true;
  final requests = <FakeKeywordRequest>[];

  @override
  Future<KeywordSearchResult> search(
    String query, {
    required KeywordBatch onBatch,
  }) {
    final request = FakeKeywordRequest(query, onBatch);
    requests.add(request);
    return request.completion.future;
  }

  @override
  List<Torrent> merge(List<List<Torrent>> batches) =>
      TorrentService.mergeSearchResults(batches);
}
