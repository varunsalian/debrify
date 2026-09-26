import '../../../models/torrent.dart';
import '../../../models/advanced_search_selection.dart';
import '../../../services/iptv_source_search.dart';
import 'source_search_repository.dart';

// Legacy service maps are confined to this integration boundary.
typedef SourceKeywordSearch =
    Future<Map<String, dynamic>> Function(
      String query, {
      required SourceSearchBatch onBatch,
      required bool preserveSourceOrder,
    });
typedef SourceImdbSearch =
    Future<Map<String, dynamic>> Function(
      String imdbId, {
      required bool isMovie,
      int? season,
      int? episode,
      String? contentType,
      List<int>? availableSeasons,
      required SourceSearchBatch onBatch,
      required bool preserveSourceOrder,
      String? originAddonKey,
      String? originVideoId,
    });
typedef SourceVideoResolver =
    Future<String?> Function({
      required String addonKey,
      String? addonId,
      required String catalogId,
      required int season,
      required int episode,
    });
typedef SourceIptvSearch =
    Future<List<IptvSourceResult>> Function(
      AdvancedSearchSelection selection, {
      required void Function(IptvSourceResult) onResult,
      required bool Function() shouldContinue,
      required bool deferXtreamSeriesEpisodes,
    });
typedef LegacySourceSearchOverride =
    Future<Map<String, dynamic>> Function(SourceSearchBatch onBatch);

typedef SourceAddonRetry =
    Future<List<Torrent>> Function({
      required String addonId,
      required String type,
      required String imdbId,
      int? season,
      int? episode,
      required Duration timeout,
      required bool preserveOrder,
      String? originVideoId,
    });
