import '../utils/continue_watching_presentation.dart';
import '../models/stremio_addon.dart';
import 'stremio_service.dart';
import 'tvmaze_service.dart';

/// Resolves a landscape still for a specific episode, with session memoization.
///
/// Stremio meta is preferred because it is already the episode panel's richest
/// source. TVMaze fills gaps for tracker rows and addons without thumbnails.
class EpisodeArtworkService {
  EpisodeArtworkService._();

  static final EpisodeArtworkService instance = EpisodeArtworkService._();

  final Map<String, Future<String?>> _memo = {};
  Future<StremioAddon?>? _metaAddon;

  Future<String?> resolve({
    required String imdbId,
    required int season,
    required int episode,
  }) {
    final key = '${imdbId.toLowerCase()}:$season:$episode';
    return _memo.putIfAbsent(
      key,
      () => _resolve(imdbId: imdbId, season: season, episode: episode),
    );
  }

  Future<String?> _resolve({
    required String imdbId,
    required int season,
    required int episode,
  }) async {
    try {
      final addon = await (_metaAddon ??= StremioService.instance
          .firstMetaCapableAddon());
      if (addon != null) {
        final videos = await StremioService.instance.fetchSeriesMeta(
          addon,
          imdbId,
        );
        final thumbnail = episodeThumbnailFromVideos(
          videos,
          season: season,
          episode: episode,
        );
        if (thumbnail != null) return thumbnail;
      }
    } catch (_) {
      // Best-effort enrichment; TVMaze below may still know the episode.
    }

    try {
      final show = await TVMazeService.lookupByImdbId(imdbId);
      final showId = show?['id'] as int?;
      if (showId == null) return null;
      final episodes = await TVMazeService.getEpisodes(showId);
      for (final raw in episodes) {
        if ((raw['season'] as num?)?.toInt() != season ||
            (raw['number'] as num?)?.toInt() != episode) {
          continue;
        }
        final image = raw['image'] as Map<String, dynamic>?;
        final url =
            image?['medium'] as String? ?? image?['original'] as String?;
        if (url != null && url.isNotEmpty) return url;
      }
    } catch (_) {
      // The show artwork remains the card's deterministic fallback.
    }
    return null;
  }
}
