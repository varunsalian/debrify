import '../../../models/torrent.dart';
import '../models/keyword_search_result.dart';

typedef KeywordBatch = void Function(String source, List<Torrent> torrents);

abstract interface class KeywordSearchRepository {
  bool get isCurrent;
  Future<KeywordSearchResult> search(
    String query, {
    required KeywordBatch onBatch,
  });
  List<Torrent> merge(List<List<Torrent>> batches);
}
