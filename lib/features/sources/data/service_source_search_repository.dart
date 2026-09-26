import '../../../models/torrent.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/stremio_service.dart';
import '../../../services/torrent_service.dart';
import '../models/source_search_request.dart';
import '../models/source_search_result.dart';
import 'source_search_api.dart';
import 'source_search_repository.dart';

class ServiceSourceSearchRepository implements SourceSearchRepository {
  const ServiceSourceSearchRepository({
    required this.owner,
    this.keywordSearch = TorrentService.searchAllEngines,
    this.imdbSearch = TorrentService.searchByImdbWithStremio,
    this.iptvSearch = IptvSourceSearch.search,
    this.resolveVideo = _resolveVideo,
    this.searchOverride,
  });
  final ProfileSessionOwner owner;
  final SourceKeywordSearch keywordSearch;
  final SourceImdbSearch imdbSearch;
  final SourceIptvSearch iptvSearch;
  final SourceVideoResolver resolveVideo;
  // Compatibility for the existing sourcesScreenForTesting injection only.
  final LegacySourceSearchOverride? searchOverride;

  @override
  bool get isCurrent => owner == ProfileSessionMemory.captureOwner();

  static Future<String?> _resolveVideo({
    required String addonKey,
    String? addonId,
    required String catalogId,
    required int season,
    required int episode,
  }) => StremioService.instance.resolveSeriesEpisodeVideoId(
    addonKey: addonKey,
    addonId: addonId,
    catalogId: catalogId,
    season: season,
    episode: episode,
  );

  @override
  Future<SourceSearchResult?> search(
    SourceSearchRequest request, {
    required SourceSearchBatch onBatch,
    required void Function(IptvSourceResult) onIptvResult,
    required bool Function() shouldContinue,
  }) async {
    var acceptingEvents = true;
    bool active() => acceptingEvents && isCurrent && shouldContinue();
    if (!active()) return null;
    void batch(String source, List<Torrent> rows) {
      if (active()) onBatch(source, List.unmodifiable(rows));
    }

    Future<SourceSearchResult?> run() async {
      final selection = request.selection;
      var videoId = selection.stremioVideoId?.trim();
      if (selection.hasStremioEpisodeIdentity &&
          videoId?.isNotEmpty != true &&
          selection.season != null &&
          selection.episode != null) {
        videoId = await resolveVideo(
          addonKey: selection.stremioAddonKey!,
          addonId: selection.stremioAddonId,
          catalogId: selection.stremioCatalogId!,
          season: selection.season!,
          episode: selection.episode!,
        );
        if (!active()) return null;
      }
      if (selection.hasStremioEpisodeIdentity && videoId?.isNotEmpty != true) {
        return SourceSearchResult();
      }
      // Start IPTV beside the engine/addon request. Observe its failure even if
      // the main request fails first; successful completion still awaits it.
      (Object, StackTrace)? iptvFailure;
      final iptv =
          request.keyword == null &&
              searchOverride == null &&
              !selection.hasStremioEpisodeIdentity
          ? iptvSearch(
              selection,
              deferXtreamSeriesEpisodes: true,
              shouldContinue: active,
              onResult: (result) {
                if (!active()) return;
                final snapshot = _snapshot(result);
                onIptvResult(snapshot);
                batch(snapshot.key, snapshot.torrents);
              },
            ).then(
              (value) => value,
              onError: (Object error, StackTrace stack) {
                iptvFailure = (error, stack);
                return <IptvSourceResult>[];
              },
            )
          : null;
      final Map<String, dynamic> result;
      if (searchOverride != null) {
        result = await searchOverride!(batch);
      } else if (request.keyword != null) {
        result = await keywordSearch(
          request.keyword!,
          onBatch: batch,
          preserveSourceOrder: true,
        );
      } else {
        result = await imdbSearch(
          selection.imdbId,
          isMovie: !selection.isSeries,
          season: selection.season,
          episode: selection.episode,
          contentType: selection.contentType,
          availableSeasons: request.availableSeasons.isEmpty
              ? null
              : request.availableSeasons,
          onBatch: batch,
          preserveSourceOrder: true,
          originAddonKey: selection.stremioAddonKey,
          originVideoId: videoId,
        );
      }
      final iptvResults = iptv == null ? <IptvSourceResult>[] : await iptv;
      if (!active()) return null;
      final failure = iptvFailure;
      if (failure != null) Error.throwWithStackTrace(failure.$1, failure.$2);
      final snapshots = [for (final result in iptvResults) _snapshot(result)];
      return SourceSearchResult(
        torrents: [
          ...(result['torrents'] as List).cast<Torrent>(),
          for (final result in snapshots) ...result.torrents,
        ],
        addonStatuses:
            result['addonStatuses'] as List<AddonSearchStatus>? ?? const [],
        iptv: snapshots,
      );
    }

    try {
      final scope = owner.scope;
      return await (scope == null
          ? run()
          : ProfileRuntime.withCapturedScope(scope, run));
    } catch (_) {
      if (!active()) return null;
      rethrow;
    } finally {
      acceptingEvents = false;
    }
  }

  static IptvSourceResult _snapshot(IptvSourceResult result) =>
      IptvSourceResult(
        result.key,
        result.name,
        result.message,
        List.unmodifiable(result.torrents),
        retryableFailure: result.retryableFailure,
      );
}
