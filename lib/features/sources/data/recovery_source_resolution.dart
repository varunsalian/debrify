import 'dart:async';

import 'package:debrify/features/sources/application/source_cache_ordering.dart';
import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/application/source_probing.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/application/source_search_plans.dart';
import 'package:debrify/features/sources/data/automatic_source_bindings.dart';
import 'package:debrify/features/sources/data/curated_source_search.dart';
import 'package:debrify/features/sources/data/iptv_quick_play_search.dart';
import 'package:debrify/features/sources/data/series_pack_search.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/playlist_entry.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/direct_source_authorization.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/torrent_service.dart';
import 'package:debrify/utils/filter_ladder.dart';

final class RecoverySourceResolution {
  const RecoverySourceResolution._();

  /// Recovery uses the same searches, but keeps representations until strict
  /// rules have been applied. Manual drawer deduplication is intentionally later.
  static Future<List<Torrent>?> Function(String, int, int) recoverySearch(
    PlaybackMeta meta,
    String? provider,
  ) => (mode, season, episode) async {
    final contentId = meta.imdbId ?? meta.stremioCatalogId;
    if (contentId == null || contentId.isEmpty) return null;
    final isMovie = meta.contentType == 'movie';
    final rules = await StorageService.getQuickPlayRules(isMovie: isMovie);
    final prov = await SourceProviderConfig.effectiveFetchProvider(provider);
    if (rules.sourcePriority.isNotEmpty)
      // ignore: curly_braces_in_flow_control_structures
      await SourceCandidateRanking.warmSourceAliases();
    if (mode == SeriesSourceFetcher.modePacks) {
      if (!contentId.startsWith('tt') || meta.hasStremioEpisodeIdentity) {
        return const <Torrent>[];
      }
      if (prov == null || prov == 'pikpak') return null;
      return SeriesPackSearch.searchSeriesPackSources(
        imdbId: contentId,
        label: meta.title ?? '',
        season: season,
        provider: prov,
        rules: rules,
        ladder: await SourceFilterLadder.loadLadder(
          includeSize: false,
          rules: rules,
        ),
        preserveRepresentations: true,
      );
    }
    if (prov != null) {
      return CuratedSourceSearch.searchCuratedSources(
        imdbId: contentId,
        label: meta.title ?? '',
        isMovie: isMovie,
        year: meta.year,
        season: isMovie ? null : season,
        episode: isMovie ? null : episode,
        provider: prov,
        rules: rules,
        originMeta: meta,
      );
    }
    // ignore: invalid_use_of_visible_for_testing_member
    if ((!SourceSearchPlans.allowsAddonSearch(rules) &&
            !meta.hasStremioEpisodeIdentity) ||
        !rules.allowDirectLinks) {
      return [];
    }
    final originVideoId = await CuratedSourceSearch.originEpisodeVideoId(
      meta,
      season,
      episode,
    );
    if (meta.hasStremioEpisodeIdentity && originVideoId == null) return null;
    final result = await TorrentService.searchStremioAddonsOnly(
      imdbId: contentId,
      isMovie: isMovie,
      season: isMovie ? null : season,
      episode: isMovie ? null : episode,
      timeout: rules.addonTimeoutSeconds == 15
          ? null
          : Duration(seconds: rules.addonTimeoutSeconds),
      preserveOrder: rules.ranking == QuickPlayRanking.exactOrder,
      originAddonKey: meta.stremioAddonKey,
      originVideoId: originVideoId,
    );
    final list = (result['torrents'] as List)
        .cast<Torrent>()
        .where(
          (t) =>
              t.streamType == StreamType.directUrl &&
              (t.directUrl?.isNotEmpty ?? false),
        )
        .toList();
    if (!meta.hasStremioEpisodeIdentity) {
      list.addAll(
        // ignore: invalid_use_of_visible_for_testing_member
        await IptvQuickPlaySearch.searchIptvForQuickPlay(
          contentId,
          meta.title ?? '',
          meta.year,
          isMovie,
          season,
          episode,
          rules,
          null,
        ),
      );
    }
    return list.isEmpty &&
            ((result['addonErrors'] as Map?)?.isNotEmpty ?? false)
        ? null
        : list;
  };

  /// Shared automatic preparation: strict eligibility BEFORE dedupe, then the
  /// same provider cache-first pass used by Quick Play's torrent preparation.
  static Future<List<Torrent>> prepareRecoverySources(
    List<Torrent> raw, {
    required QuickPlayRules rules,
    required String? provider,
    required FilterLadder ladder,
    Future<List<Torrent>> Function(String, List<Torrent>)? cacheCheck,
  }) async {
    final ordered = SourceCandidateRanking.orderCandidatesForRules(
      raw,
      rules: rules,
      ladder: ladder,
    );
    if (provider != 'torbox' && provider != 'premiumize') return ordered;
    var torrents = ordered
        .where((t) => t.streamType == StreamType.torrent)
        .toList();
    if (torrents.isEmpty) return ordered;
    torrents = await (cacheCheck ?? SourceCacheOrdering.cacheFirst)(
      provider!,
      torrents,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    torrents = SourceCandidateRanking.orderCacheCheckedCandidatesForRules(
      torrents,
      rules: rules,
      ladder: ladder,
    );
    // ignore: invalid_use_of_visible_for_testing_member
    return SourceCandidateRanking.mergePreparedTorrentOrder(ordered, torrents);
  }

  /// One native recovery attempt, using Quick Play's exact-episode validation
  /// and RD/AllDebrid acquisition cleanup. Native owns the overall retry cap.
  static Future<List<PlaylistEntry>?> resolveRecoverySource(
    Torrent source, {
    required String? provider,
    AutomaticSourceBindings? sourceBindings,
    ProfileSessionOwner? owner,
    bool Function()? canContinue,
    int? season,
    int? episode,
  }) async {
    final bindingOwner =
        sourceBindings ??
        AutomaticSourceBindings(owner ?? ProfileSessionMemory.captureOwner());
    Future<List<PlaylistEntry>?> resolve() async {
      bool active() => bindingOwner.isCurrent && (canContinue?.call() ?? true);
      if (!active()) return null;
      if (IptvSourceSearch.isDeferredXtreamSeries(source)) {
        final resolution = await IptvSourceSearch.resolveXtreamSeriesEpisode(
          source,
          season: season,
          episode: episode,
        );
        if (!active() || resolution.source == null) return null;
        source = resolution.source!;
      }
      try {
        await DirectSourceAuthorization.authorize(source);
      } catch (_) {
        return null;
      }
      if (!active()) return null;
      if (source.streamType == StreamType.directUrl) {
        if (source.directUrl?.isNotEmpty != true) return null;
        return [
          PlaylistEntry(
            url: source.directUrl!,
            title: source.displayTitle,
            httpHeaders: source.httpHeaders ?? const {},
          ),
        ];
      }
      if (provider == null) return null;
      final (resolved, _) = await SourceProbing.probeCandidates(
        provider,
        [source],
        sourceBindings: bindingOwner,
        isCancelled: () => !active(),
        season: season,
        episode: episode,
        rules: QuickPlayRules.debrifyDefault(
          isMovie: season == null,
        ).copyWith(tryNextOnFailure: false, maxAttempts: 1),
      );
      if (resolved == null) return null;
      if (resolved.playlist?.isNotEmpty == true) return resolved.playlist;
      if (resolved.playUrl?.isNotEmpty != true) return null;
      return [
        PlaylistEntry(
          url: resolved.playUrl!,
          title: resolved.title,
          httpHeaders: resolved.httpHeaders ?? const {},
        ),
      ];
    }

    final scope = bindingOwner.owner.scope;
    return scope == null
        ? ProfileRuntime.withoutCapturedScope(resolve)
        : ProfileRuntime.withCapturedScope(scope, resolve);
  }
}
