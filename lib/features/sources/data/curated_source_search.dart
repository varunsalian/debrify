import 'dart:async';

import 'package:debrify/features/sources/application/source_curation.dart';
import 'package:debrify/features/sources/data/iptv_quick_play_search.dart';
import 'package:debrify/models/playback_meta.dart';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:debrify/services/torrent_service.dart';

final class CuratedSourceSearch {
  const CuratedSourceSearch._();

  /// Combined engine, addon and IPTV search, followed by provider ordering
  /// at the caller. IPTV does not participate in torrent-only pack searches.
  static Future<String?> originEpisodeVideoId(
    PlaybackMeta? meta,
    int? season,
    int? episode,
  ) async {
    if (meta == null ||
        !meta.hasStremioEpisodeIdentity ||
        season == null ||
        episode == null) {
      return null;
    }
    if (season == meta.season &&
        episode == meta.episode &&
        meta.stremioVideoId?.trim().isNotEmpty == true) {
      return meta.stremioVideoId!.trim();
    }
    return StremioService.instance.resolveSeriesEpisodeVideoId(
      addonKey: meta.stremioAddonKey!,
      addonId: meta.stremioAddonId,
      catalogId: meta.stremioCatalogId!,
      season: season,
      episode: episode,
    );
  }

  static Future<List<Torrent>> searchCuratedSources({
    required String imdbId,
    required String label,
    String? year,
    required bool isMovie,
    int? season,
    int? episode,
    required String provider,
    QuickPlayRules? rules,
    bool Function()? isCancelled,
    void Function(int count)? onResults,
    PlaybackMeta? originMeta,
  }) async {
    final configuredRules =
        rules ?? QuickPlayRules.debrifyDefault(isMovie: isMovie);
    // A custom Stremio episode ID is the authoritative identity for fan edits
    // and other non-Cinemeta catalogs. Torrent engines cannot represent that
    // identity, so recovery must not let a torrents-only profile skip the
    // originating/compatible stream addons.
    final activeRules = originMeta?.hasStremioEpisodeIdentity == true
        ? configuredRules.copyWith(
            sourceMode: QuickPlaySourceMode.addonsOnly,
            preserveLegacyCombinedPackSearch: false,
          )
        : configuredRules;
    final engineTimeout = activeRules.searchTimeoutSeconds == 0
        ? null
        : Duration(seconds: activeRules.searchTimeoutSeconds);
    final addonTimeout = activeRules.addonTimeoutSeconds == 15
        ? null
        : Duration(seconds: activeRules.addonTimeoutSeconds);

    Future<List<Torrent>> engines() async {
      if (!imdbId.startsWith('tt') ||
          originMeta?.hasStremioEpisodeIdentity == true) {
        return const <Torrent>[];
      }
      final res = await TorrentService.searchByImdb(
        imdbId,
        isMovie: isMovie,
        season: season,
        episode: episode,
        timeout: engineTimeout,
        preserveSourceOrder: activeRules.ranking == QuickPlayRanking.exactOrder,
      );
      var found = (res['torrents'] as List).cast<Torrent>();
      if (isCancelled?.call() ?? false) return found;
      if (found.isNotEmpty) {
        onResults?.call(found.length);
        // Curate candidates so the RIGHT torrent is probed first (mirrors old
        // home): drop unrelated titles, keep/relevance-sort by the requested
        // episode/season, then drop RD-blocked keywords when RD is the provider.
        // Without this the raw seeder-ranked list can lead with wrong-episode/
        // other-season packs that resolve fine but get rejected by
        // _resolvedHasEpisode, burning the probes.
        found = await SourceCuration.curateCandidates(
          found,
          label: label,
          isMovie: isMovie,
          season: season,
          episode: episode,
          provider: provider,
        );
      }
      return found;
    }

    Future<List<Torrent>> addons() async {
      // Addon streams are already id/episode-scoped by the /stream endpoint;
      // their labels are quality descriptions rather than titles, so engine
      // title curation must not be applied to them.
      try {
        final originVideoId = await originEpisodeVideoId(
          originMeta,
          season,
          episode,
        );
        if (originMeta?.hasStremioEpisodeIdentity == true &&
            originVideoId == null) {
          return const <Torrent>[];
        }
        final addonRes = await TorrentService.searchStremioAddonsOnly(
          imdbId: imdbId,
          isMovie: isMovie,
          season: season,
          episode: episode,
          timeout: addonTimeout,
          preserveOrder: activeRules.ranking == QuickPlayRanking.exactOrder,
          originAddonKey: originMeta?.stremioAddonKey,
          originVideoId: originVideoId,
        );
        final found = <Torrent>[
          ...(addonRes['torrents'] as List).cast<Torrent>(),
          if (originMeta?.hasStremioEpisodeIdentity != true)
            ...await IptvQuickPlaySearch.searchIptvForQuickPlay(
              imdbId,
              label,
              year,
              isMovie,
              season,
              episode,
              activeRules,
              isCancelled,
            ),
        ];
        final allowed = activeRules.allowDirectLinks
            ? found
            : found.where((t) => t.streamType != StreamType.directUrl).toList();
        if (allowed.isNotEmpty) onResults?.call(allowed.length);
        return allowed;
      } catch (_) {
        return const [];
      }
    }

    List<Torrent> torrents;
    switch (activeRules.sourceMode) {
      case QuickPlaySourceMode.torrentsThenAddons:
      case QuickPlaySourceMode.addonsThenTorrents:
      case QuickPlaySourceMode.together:
        final batches = await Future.wait([engines(), addons()]);
        // Both families start together, but Future.wait preserves this fixed
        // batch order. Provider priority and stable dedupe run afterwards.
        torrents = [...batches[0], ...batches[1]];
        break;
      case QuickPlaySourceMode.torrentsOnly:
        torrents = await engines();
        break;
      case QuickPlaySourceMode.addonsOnly:
        torrents = await addons();
        break;
    }
    if (isCancelled?.call() ?? false) return torrents;
    return torrents;
  }
}
