import 'package:flutter/foundation.dart';
import 'stremio_service.dart';
import '../models/stremio_addon.dart';

class NextEpisodeService {
  /// Find the next episode after the given season/episode using Stremio catalog addon metadata.
  /// Returns (season, episode) of the next episode, or null if not found / last episode.
  static Future<({int season, int episode})?> findNextEpisode(
    String imdbId,
    int currentSeason,
    int currentEpisode,
  ) async {
    try {
      final stremioService = StremioService.instance;
      final addons = await stremioService.getEnabledAddons();
      if (addons.isEmpty) return null;

      // Find first addon with meta support
      final addon = addons.cast<StremioAddon?>().firstWhere(
        (a) => a?.resources.contains('meta') == true,
        orElse: () => null,
      );
      if (addon == null) return null;

      final episodes = await stremioService.fetchSeriesMeta(addon, imdbId);
      if (episodes == null || episodes.isEmpty) return null;

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
      if (curIdx == -1) return null;

      // Scan forward for the first valid episode strictly after the current
      // one. Scanning (rather than blindly taking curIdx+1) matters because:
      //  • some aggregator addons list an episode twice — returning that
      //    duplicate row would replay the SAME episode forever;
      //  • a specials / episode-0 boundary row should be skipped over, not
      //    treated as "no next" (which would halt the binge).
      for (int i = curIdx + 1; i < sorted.length; i++) {
        final ns = sorted[i]['season'] as int? ?? 0;
        final ne =
            sorted[i]['episode'] as int? ?? sorted[i]['number'] as int? ?? 0;
        if (ns <= 0 || ne <= 0) continue; // specials / unparseable
        if (ns == currentSeason && ne == currentEpisode) continue; // duplicate
        return (season: ns, episode: ne);
      }
      return null;
    } catch (e) {
      debugPrint('NextEpisodeService: Error finding next episode: $e');
      return null;
    }
  }
}
