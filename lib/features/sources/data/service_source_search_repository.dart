import 'dart:async';

import '../../../models/advanced_search_selection.dart';
import '../../../models/torrent.dart';
import '../../../services/iptv_source_search.dart';
import '../../../services/profiles/profile_runtime.dart';
import '../../../services/profiles/profile_session_memory.dart';
import '../../../services/source_search_scope.dart';
import '../../../services/stremio_service.dart';
import '../../../services/torrent_service.dart';
import '../models/source_search_request.dart';
import '../models/source_search_result.dart';
import '../models/webdav_source_status.dart';
import 'source_search_api.dart';
import 'source_search_repository.dart';
import 'webdav_source_search.dart';

class ServiceSourceSearchRepository implements SourceSearchRepository {
  const ServiceSourceSearchRepository({
    required this.owner,
    this.keywordSearch = TorrentService.searchAllEngines,
    this.imdbSearch = TorrentService.searchByImdbWithStremio,
    this.iptvSearch = IptvSourceSearch.search,
    this.webDavSearch = _searchWebDav,
    this.resolveVideo = _resolveVideo,
    this.searchOverride,
    SourceAddonRetry? retryAddon,
  }) : retryAddon = retryAddon ?? _retryAddon;
  final ProfileSessionOwner owner;
  final SourceKeywordSearch keywordSearch;
  final SourceImdbSearch imdbSearch;
  final SourceIptvSearch iptvSearch;
  final SourceWebDavSearch webDavSearch;
  final SourceVideoResolver resolveVideo;
  final SourceAddonRetry retryAddon;
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

  static Future<List<WebDavSourceStatus>> _searchWebDav(
    AdvancedSearchSelection selection, {
    required void Function(WebDavSourceStatus status) onStatus,
    required void Function(String key, List<Torrent> rows) onRows,
    required bool Function() shouldContinue,
  }) => WebDavSourceSearch().search(
    selection,
    onStatus: onStatus,
    onRows: onRows,
    shouldContinue: shouldContinue,
  );

  @override
  Future<SourceSearchResult?> search(
    SourceSearchRequest request, {
    required SourceSearchBatch onBatch,
    required void Function(IptvSourceResult) onIptvResult,
    required bool Function() shouldContinue,
    void Function(WebDavSourceStatus)? onWebDavStatus,
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
      // WebDAV starts beside the other searches but never holds up their
      // result: it keeps streaming rows and progress after the search
      // completes, until the view stops wanting this search. A failure only
      // ever becomes a server status, never an error.
      final webDavRows = <Torrent>[];
      final webDavStatuses = <String, WebDavSourceStatus>{};
      bool webDavActive() => isCurrent && shouldContinue();
      if (request.keyword == null &&
          searchOverride == null &&
          WebDavSourceSearch.supports(selection)) {
        unawaited(
          webDavSearch(
            selection,
            shouldContinue: webDavActive,
            onStatus: (status) {
              if (!webDavActive()) return;
              webDavStatuses[status.key] = status;
              onWebDavStatus?.call(status);
            },
            onRows: (key, rows) {
              if (!webDavActive()) return;
              webDavRows.addAll(rows);
              onBatch(key, List.unmodifiable(rows));
            },
          ).then((_) {}, onError: (Object _, StackTrace _) {}),
        );
      }
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
        SourceSearchScope.log(
          surface: 'sources',
          imdbId: selection.imdbId,
          isMovie: !selection.isSeries,
          season: selection.season,
          episode: selection.episode,
          contentType: selection.contentType,
          originVideoId: videoId,
          result: result,
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
          ...webDavRows,
        ],
        addonStatuses:
            result['addonStatuses'] as List<AddonSearchStatus>? ?? const [],
        iptv: snapshots,
        // Whatever WebDAV has found and reported so far; more may follow.
        webDav: webDavStatuses.values.toList(),
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

  static Future<List<Torrent>> _retryAddon({
    required String addonId,
    required String type,
    required String imdbId,
    int? season,
    int? episode,
    required Duration timeout,
    required bool preserveOrder,
    String? originVideoId,
  }) => StremioService.instance.retryAddonStreams(
    addonId: addonId,
    type: type,
    imdbId: imdbId,
    season: season,
    episode: episode,
    timeout: timeout,
    preserveOrder: preserveOrder,
    originVideoId: originVideoId,
  );

  @override
  Future<List<Torrent>?> retry(
    AdvancedSearchSelection selection,
    String requestKey, {
    required bool Function() shouldContinue,
  }) async {
    bool active() => isCurrent && shouldContinue();
    if (!active()) return null;
    Future<List<Torrent>?> run() async {
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
        return null;
      }
      final rows = await retryAddon(
        addonId: requestKey,
        type:
            selection.contentType ?? (selection.isSeries ? 'series' : 'movie'),
        imdbId: selection.imdbId,
        season: selection.season,
        episode: selection.episode,
        timeout: StremioService.manualRetryTimeout,
        preserveOrder: true,
        originVideoId: videoId,
      );
      return active() ? List.unmodifiable(rows) : null;
    }

    try {
      final scope = owner.scope;
      return await (scope == null
          ? run()
          : ProfileRuntime.withCapturedScope(scope, run));
    } catch (_) {
      if (!active()) return null;
      rethrow;
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
