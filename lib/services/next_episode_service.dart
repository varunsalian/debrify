import 'adjacent_episode_resolver.dart';
import 'native_series_metadata_service.dart';
import 'package:flutter/foundation.dart';
import 'stremio_service.dart';
import '../models/stremio_addon.dart';
import '../models/custom_series_identity.dart';

class NextEpisodeService {
  /// Use the originating catalog guide; source-less titles use built-in metadata.
  /// Returns (season, episode) of the next episode, or null if not found / last episode.
  static Future<({int season, int episode})?> findNextEpisode(
    String imdbId,
    int currentSeason,
    int currentEpisode, {
    NativeSeriesMetadataService? metadata,
    bool preferBuiltIn = false,
    StremioMeta? catalogItem,
    String? originAddonId,
  }) => findAdjacentEpisode(
    imdbId,
    currentSeason,
    currentEpisode,
    direction: 1,
    metadata: metadata,
    preferBuiltIn: preferBuiltIn,
    catalogItem: catalogItem,
    originAddonId: originAddonId,
  );

  /// Resolve either direction using the same provider and season boundaries.
  /// Players may opt into [reportGuideUnavailable] to distinguish an unusable
  /// canonical guide from a confirmed boundary before trying their cached guide.
  /// Custom catalog results remain authoritative.
  static Future<({int season, int episode})?> findAdjacentEpisode(
    String imdbId,
    int currentSeason,
    int currentEpisode, {
    required int direction,
    bool reportGuideUnavailable = false,
    NativeSeriesMetadataService? metadata,
    bool preferBuiltIn = false,
    StremioMeta? catalogItem,
    String? originAddonId,
  }) async {
    if (direction != 1 && direction != -1) return null;
    try {
      final stremioService = StremioService.instance;
      final custom = CustomSeriesIdentity.parse(imdbId);
      if (custom != null) {
        final addon = await stremioService.addonForCustomProgress(imdbId);
        if (addon == null) return null;
        final next = await stremioService.resolveAdjacentSeriesEpisode(
          addonKey: addon.sourceBindingKey,
          catalogId: custom.catalogId,
          season: currentSeason,
          episode: currentEpisode,
          direction: direction,
        );
        return next == null
            ? null
            : (season: next.season, episode: next.episode);
      }
      List<Map<String, dynamic>>? episodes;
      var origin = catalogItem?.sourceAddon;
      if (origin == null &&
          originAddonId != null &&
          originAddonId != NativeSeriesMetadataService.addon.id) {
        final addons = await stremioService.getEnabledAddons();
        final matches = addons
            .where(
              (addon) =>
                  addon.sourceBindingKey == originAddonId ||
                  addon.portableConfigurationKey == originAddonId ||
                  addon.id == originAddonId,
            )
            .toList();
        if (matches.length > 1) return null;
        if (matches.isNotEmpty) origin = matches.single;
      }
      if (!preferBuiltIn &&
          origin != null &&
          origin.baseUrl.isNotEmpty &&
          origin.supportsMeta &&
          (origin.types.isEmpty || origin.types.contains('series'))) {
        episodes = await stremioService.fetchSeriesMeta(
          origin,
          catalogItem?.id ?? imdbId,
        );
      } else {
        episodes = await (metadata ?? NativeSeriesMetadataService.instance)
            .episodesWithFallback(
              imdbId,
              afterSeason: currentSeason,
              afterEpisode: currentEpisode,
              direction: direction,
            );
      }
      if (episodes == null || episodes.isEmpty) {
        if (reportGuideUnavailable) throw const EpisodeGuideUnavailable();
        return null;
      }

      // Sort episodes by season then episode number
      final sorted = List<Map<String, dynamic>>.from(episodes);
      sorted.sort((a, b) {
        final sa = a['season'] as int? ?? 0;
        final sb = b['season'] as int? ?? 0;
        if (sa != sb) return sa.compareTo(sb);
        final ea = a['episode'] as int? ?? a['number'] as int? ?? 0;
        final eb = b['episode'] as int? ?? b['number'] as int? ?? 0;
        return ea.compareTo(eb);
      });

      // Locate the current episode.
      int curIdx = -1;
      for (int i = 0; i < sorted.length; i++) {
        final s = sorted[i]['season'] as int? ?? 0;
        final e =
            sorted[i]['episode'] as int? ?? sorted[i]['number'] as int? ?? 0;
        if (s == currentSeason && e == currentEpisode) {
          curIdx = i;
          break;
        }
      }
      if (curIdx == -1) {
        if (reportGuideUnavailable) throw const EpisodeGuideUnavailable();
        return null;
      }

      // Scan in the requested direction for the first distinct valid episode after/before the current
      // one. Scanning (rather than blindly taking curIdx+1) matters because:
      //  • some aggregator addons list an episode twice — returning that
      //    duplicate row would replay the SAME episode forever;
      //  • a specials / episode-0 boundary row should be skipped over, not
      //    treated as "no next" (which would halt the binge).
      for (
        int i = curIdx + direction;
        i >= 0 && i < sorted.length;
        i += direction
      ) {
        final ns = sorted[i]['season'] as int? ?? 0;
        final ne =
            sorted[i]['episode'] as int? ?? sorted[i]['number'] as int? ?? 0;
        if (ns <= 0 || ne <= 0) continue; // specials / unparseable
        if (ns == currentSeason && ne == currentEpisode) continue; // duplicate
        final released = DateTime.tryParse(
          (sorted[i]['released'] ?? '').toString(),
        );
        // Guides can include announced episodes. Stop at the next unaired
        // episode rather than searching for it or skipping ahead in the story.
        // Unknown dates remain eligible, as they are in random playback.
        if (direction > 0 &&
            released != null &&
            released.isAfter(DateTime.now())) {
          return null;
        }
        return (season: ns, episode: ne);
      }
      return null;
    } catch (e) {
      if (reportGuideUnavailable && !CustomSeriesIdentity.isCustom(imdbId)) {
        throw const EpisodeGuideUnavailable();
      }
      debugPrint('NextEpisodeService: Error finding next episode: $e');
      return null;
    }
  }
}
