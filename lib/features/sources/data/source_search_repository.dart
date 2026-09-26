import '../../../models/torrent.dart';
import '../../../services/iptv_source_search.dart';
import '../models/source_search_request.dart';
import '../models/source_search_result.dart';

typedef SourceSearchBatch = void Function(String source, List<Torrent> batch);

abstract interface class SourceSearchRepository {
  bool get isCurrent;
  Future<SourceSearchResult?> search(
    SourceSearchRequest request, {
    required SourceSearchBatch onBatch,
    required void Function(IptvSourceResult) onIptvResult,
    required bool Function() shouldContinue,
  });
}
