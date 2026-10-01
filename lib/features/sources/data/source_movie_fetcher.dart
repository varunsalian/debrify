import 'package:debrify/features/sources/application/source_candidate_ranking.dart';
import 'package:debrify/features/sources/application/source_filter_ladder.dart';
import 'package:debrify/features/sources/application/source_provider_config.dart';
import 'package:debrify/features/sources/data/curated_source_search.dart';
import 'package:debrify/features/sources/data/recovery_source_resolution.dart';
import 'package:debrify/features/sources/data/source_engine_fetchers.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/source_priority.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/stremio_service.dart';

final class SourceMovieFetcher {
  const SourceMovieFetcher._();

  /// Movie counterpart of [seriesFetcherFor]: a bound movie play launches
  /// with just the pinned torrent, so its flat Torrent tab offers one "Load
  /// more sources" that runs the normal movie search chain. Null when the
  /// play isn't a searchable movie. Non-bound movie plays already carry the
  /// full search results, so their launch sites simply don't build one.
  static SeriesSourceFetcher? movieFetcherFor({
    required PlaybackMeta? meta,
    String? provider,
  }) {
    final imdbId = meta?.imdbId;
    if (meta == null ||
        imdbId == null ||
        !imdbId.startsWith('tt') ||
        meta.contentType != 'movie') {
      return null;
    }
    final label = meta.title ?? '';
    return SeriesSourceFetcher.movie(
      searchForRecovery: RecoverySourceResolution.recoverySearch(
        meta,
        provider,
      ),
      searchMovie: () async {
        final prov = await SourceProviderConfig.effectiveFetchProvider(
          provider,
        );
        if (prov == null) return null;
        // Size buckets are movie-meaningful — keep them (unlike series).
        final rules = await StorageService.getQuickPlayRules(isMovie: true);
        if (rules.sourcePriority.isNotEmpty)
          // ignore: curly_braces_in_flow_control_structures
          await SourceCandidateRanking.warmSourceAliases();
        final ladder = await SourceFilterLadder.loadLadder(rules: rules);
        try {
          final list = await CuratedSourceSearch.searchCuratedSources(
            imdbId: imdbId,
            label: label,
            year: meta.year,
            isMovie: true,
            provider: prov,
            rules: rules,
          );
          return SourceCandidateRanking.orderCandidatesForRules(
            list,
            rules: rules.copyWith(relaxFilters: true),
            ladder: ladder,
          );
        } catch (_) {
          // Engine search failed — null keeps "Load more" for retry.
          return null;
        }
      },
      listAddons: () async => [
        ...await SourceEngineFetchers.mediaServerSourceRefs(),
        for (final addon
            in await StremioService.instance.applicableStreamingAddons(
              type: 'movie',
              contentId: imdbId,
            ))
          if (!SourcePriority.isRecommendationOnlyAddon(addon.id))
            SourceAddonRef(
              addon.id,
              addon.displayName,
              addonKey: addon.sourceBindingKey,
              resultSourceKey: addon.sourceKey,
            ),
      ],
      listEngines: SourceEngineFetchers.sourceEngineListing,
      fetchEngine: (engineId, _, __) => SourceEngineFetchers.fetchOneEngine(
        engineId,
        imdbId: imdbId,
        isMovie: true,
      ),
      fetchAddonEpisodes: (addonId, _, __) async {
        try {
          if (addonId.startsWith('mediaserver:')) {
            return SourceEngineFetchers.fetchMediaServerSources(
              addonId,
              imdbId,
              true,
              null,
              null,
            );
          }
          return await StremioService.instance.retryAddonStreams(
            addonId: addonId,
            type: 'movie',
            imdbId: imdbId,
            timeout: StremioService.manualRetryTimeout,
          );
        } catch (_) {
          return null;
        }
      },
    );
  }
}
