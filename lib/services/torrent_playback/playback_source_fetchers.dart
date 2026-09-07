/// The two [SeriesSourceFetcher] factories behind the in-player "Load more
/// sources" drawer, and the rule that decides which provider a fetch searches
/// with — moved verbatim out of [TorrentPlaybackService] (lane T4). No
/// BuildContext, no widgets: the searches themselves live in
/// [PlaybackSourceSearch] and the ordering in [PlaybackCandidateRanking].
library;

import '../../models/quick_play_rules.dart';
import '../../models/torrent.dart';
import '../series_source_fetcher.dart';
import '../series_source_service.dart';
import '../source_priority.dart';
import '../storage/quick_play_policy_prefs.dart';
import '../stream_url_validator.dart';
import '../stremio_service.dart';
import '../torrent_service.dart';
import 'playback_candidate_ranking.dart';
import 'playback_meta.dart';
import 'playback_provider_resolution.dart';
import 'playback_source_search.dart';

class PlaybackSourceFetchers {
  const PlaybackSourceFetchers._();

  /// Builds the [SeriesSourceFetcher] a series play hands to the player: the
  /// "Load more sources" backend for the pack/episode source tabs. Returns
  /// null when the play isn't fetchable-series-shaped (movies, no concrete
  /// season+episode, non-`tt` ids the torrent engines can't search).
  /// [provider] is the launch's debrid provider; a non-debrid launch (bound
  /// 'local' source, addon 'stream') resolves the default configured provider
  /// at fetch time instead. Without one, episode fetches can still return
  /// direct addon links; torrent and pack fetches fail soft.
  static SeriesSourceFetcher? seriesFetcherFor({
    required PlaybackMeta? meta,
    String? provider,
    bool packsFetched = false,
    bool episodesFetched = false,
  }) {
    final imdbId = meta?.imdbId;
    final season = meta?.season;
    final episode = meta?.episode;
    if (meta == null ||
        imdbId == null ||
        !imdbId.startsWith('tt') ||
        meta.contentType == 'movie' ||
        season == null ||
        episode == null) {
      return null;
    }
    final label = meta.title ?? '';
    Future<String?> effectiveProvider() => effectiveFetchProvider(provider);
    final directValidationCache = <String, bool>{};

    return SeriesSourceFetcher(
      season: season,
      episode: episode,
      packsFetched: packsFetched,
      episodesFetched: episodesFetched,
      validateCandidate: (source) async {
        if (source.streamType != StreamType.directUrl) return true;
        final url = source.directUrl;
        if (url == null || url.isEmpty) return false;
        final cached = directValidationCache[url];
        if (cached != null) return cached;
        final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(
          isMovie: false,
        );
        if (!rules.validateDirectLinks) return true;
        if (!PlaybackCandidateRanking.shouldPreflightDirectStream(source)) {
          return true;
        }
        // Match initial series Quick Play: lenient HEAD validation rejects
        // positive evidence of death without penalising HEAD-hostile CDNs.
        final alive = await StreamUrlValidator.isPlayableVideoUrl(
          url,
          minBytes: 10 * 1024 * 1024,
          lenient: true,
        );
        directValidationCache[url] = alive;
        return alive;
      },
      // The (s, e) the fetch passes in is the episode CURRENTLY playing — a
      // season-pack playlist auto-advances inside one player session, so the
      // launch episode captured above is only the fallback.
      searchPacks: (s, e) async {
        final prov = await effectiveProvider();
        if (prov == null) return null;
        final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(
          isMovie: false,
        );
        if (rules.sourcePriority.isNotEmpty) {
          await PlaybackCandidateRanking.warmSourceAliases();
        }
        final ladder = await PlaybackCandidateRanking.loadLadder(
          includeSize: false,
          rules: rules,
        );
        // This feeds the manual Sources drawer, not automatic selection. Keep
        // every candidate visible while retaining the user's ordering. Strict
        // filtering remains enforced by the actual Quick Play path.
        final manualRules = rules.copyWith(relaxFilters: true);
        return PlaybackSourceSearch.searchSeriesPackSources(
          imdbId: imdbId,
          label: label,
          season: s,
          provider: prov,
          ladder: ladder,
          rules: manualRules,
        );
      },
      searchEpisodes: (s, e) async {
        final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(
          isMovie: false,
        );
        if (rules.sourcePriority.isNotEmpty) {
          await PlaybackCandidateRanking.warmSourceAliases();
        }
        final ladder = await PlaybackCandidateRanking.loadLadder(
          includeSize: false,
          rules: rules,
        );
        try {
          final prov = await effectiveProvider();
          final List<Torrent> list;
          if (prov == null) {
            // A direct-addon episode can launch without a Debrify debrid
            // provider. Keep that contract when Next crosses a one-entry
            // playlist: query the episode-scoped addon endpoints and retain
            // only links this provider-free resolver can actually open.
            if (!PlaybackCandidateRanking.allowsAddonSearch(rules) ||
                !rules.allowDirectLinks) {
              return const <Torrent>[];
            }
            final addonTimeout = rules.addonTimeoutSeconds == 15
                ? null
                : Duration(seconds: rules.addonTimeoutSeconds);
            final result = await TorrentService.searchStremioAddonsOnly(
              imdbId: imdbId,
              isMovie: false,
              season: s,
              episode: e,
              timeout: addonTimeout,
              preserveOrder: rules.ranking == QuickPlayRanking.exactOrder,
            );
            list = (result['torrents'] as List).cast<Torrent>().where((t) {
              return t.streamType == StreamType.directUrl &&
                  (t.directUrl?.isNotEmpty ?? false);
            }).toList();
            if (list.isEmpty &&
                ((result['addonErrors'] as Map?)?.isNotEmpty ?? false)) {
              // Addon failures are reported in-band. Keep the fetch retryable
              // when they leave this provider-free path no playable rows.
              return null;
            }
          } else {
            list = await PlaybackSourceSearch.searchCuratedSources(
              imdbId: imdbId,
              label: label,
              isMovie: false,
              season: s,
              episode: e,
              provider: prov,
              rules: rules,
            );
          }
          return PlaybackCandidateRanking.orderCandidatesForRules(
            list,
            rules: rules.copyWith(relaxFilters: true),
            ladder: ladder,
          );
        } catch (_) {
          // Source search failed — null keeps the tab's "Load more" for retry.
          return null;
        }
      },
      listAddons: () async => [
        for (final addon
            in await StremioService.instance.applicableStreamingAddons(
              type: 'series',
              contentId: imdbId,
            ))
          if (!SourcePriority.isRecommendationOnlyAddon(addon.id))
            SourceAddonRef(addon.id, addon.name),
      ],
      listEngines: PlaybackSourceSearch.sourceEngineListing,
      fetchEngine: (engineId, s, e) => PlaybackSourceSearch.fetchOneEngine(
        engineId,
        imdbId: imdbId,
        isMovie: false,
        season: s,
        episode: e,
      ),
      fetchAddonEpisodes: (addonId, s, e) async {
        try {
          return await StremioService.instance.retryAddonStreams(
            addonId: addonId,
            type: 'series',
            imdbId: imdbId,
            season: s,
            episode: e,
            timeout: StremioService.manualRetryTimeout,
          );
        } catch (_) {
          // Null = fetch failed; the sheet keeps the Fetch row for a retry.
          return null;
        }
      },
      fetchAddonPacks: (addonId, s) async {
        try {
          return await StremioService.instance.fetchAddonSeasonPacks(
            addonId: addonId,
            imdbId: imdbId,
            season: s,
            timeout: StremioService.manualRetryTimeout,
          );
        } catch (_) {
          return null;
        }
      },
    );
  }

  /// The provider a "Load more sources" fetch should search with: the
  /// launch's own debrid provider, except non-debrid launches (bound 'local'
  /// source, addon 'stream') resolve the default configured one instead.
  /// Null (nothing configured) fails the fetch soft.
  static Future<String?> effectiveFetchProvider(String? provider) async {
    if (provider != null &&
        provider != SeriesSource.localService &&
        provider != SeriesSource.addonDirectService &&
        provider != 'stream') {
      return provider;
    }
    return PlaybackProviderResolution.defaultConfiguredProvider();
  }

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
      searchMovie: () async {
        final prov = await effectiveFetchProvider(provider);
        if (prov == null) return null;
        // Size buckets are movie-meaningful — keep them (unlike series).
        final rules = await QuickPlayPolicyPrefs.getQuickPlayRules(
          isMovie: true,
        );
        if (rules.sourcePriority.isNotEmpty) {
          await PlaybackCandidateRanking.warmSourceAliases();
        }
        final ladder = await PlaybackCandidateRanking.loadLadder(rules: rules);
        try {
          final list = await PlaybackSourceSearch.searchCuratedSources(
            imdbId: imdbId,
            label: label,
            isMovie: true,
            provider: prov,
            rules: rules,
          );
          return PlaybackCandidateRanking.orderCandidatesForRules(
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
        for (final addon
            in await StremioService.instance.applicableStreamingAddons(
              type: 'movie',
              contentId: imdbId,
            ))
          if (!SourcePriority.isRecommendationOnlyAddon(addon.id))
            SourceAddonRef(addon.id, addon.name),
      ],
      listEngines: PlaybackSourceSearch.sourceEngineListing,
      fetchEngine: (engineId, _, __) => PlaybackSourceSearch.fetchOneEngine(
        engineId,
        imdbId: imdbId,
        isMovie: true,
      ),
      fetchAddonEpisodes: (addonId, _, __) async {
        try {
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
