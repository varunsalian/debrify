import '../../../models/advanced_search_selection.dart';
import '../../../models/iptv_source_result.dart';
import '../../../models/torrent.dart';
import '../models/source_search_request.dart';
import '../models/source_search_result.dart';

typedef SourceSearchBatch = void Function(String source, List<Torrent> batch);

abstract interface class SourceSearchRepository {
  bool get isCurrent;
  Future<List<Torrent>?> retry(
    AdvancedSearchSelection selection,
    String requestKey, {
    required bool Function() shouldContinue,
  });
  Future<SourceSearchResult?> search(
    SourceSearchRequest request, {
    required SourceSearchBatch onBatch,
    required void Function(IptvSourceResult) onIptvResult,
    required bool Function() shouldContinue,
  });
}
