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

      // Find the current episode index, then return the next one
      for (int i = 0; i < sorted.length; i++) {
        final s = sorted[i]['season'] as int? ?? 0;
        final e = sorted[i]['episode'] as int? ?? sorted[i]['number'] as int? ?? 0;
        if (s == currentSeason && e == currentEpisode && i + 1 < sorted.length) {
          final next = sorted[i + 1];
          final ns = next['season'] as int? ?? 0;
          final ne = next['episode'] as int? ?? next['number'] as int? ?? 0;
          if (ns > 0 && ne > 0) {
            return (season: ns, episode: ne);
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('NextEpisodeService: Error finding next episode: $e');
      return null;
    }
  }
}
