import '../utils/show_shuffle.dart';

/// A canonical series guide could not be loaded or locate the playing episode.
/// Unlike a null result (end of guide / upcoming release), this permits a
/// player's already loaded guide to supply the adjacent episode.
class EpisodeGuideUnavailable implements Exception {
  const EpisodeGuideUnavailable();
}

typedef AdjacentEpisodeResolver =
    Future<({int season, int episode})?> Function(
      int season,
      int episode,
      int direction,
    );

Future<({int season, int episode})?> resolveAdjacentWithGuideFallback({
  required AdjacentEpisodeResolver resolver,
  required int season,
  required int episode,
  required int direction,
  required ({int season, int episode})? Function() cachedGuide,
}) async {
  try {
    return await resolver(season, episode, direction);
  } on EpisodeGuideUnavailable {
    return cachedGuide();
  }
}

/// Cached player guides use TVMaze-shaped episode rows.
({int season, int episode})? cachedGuideAdjacentEpisode(
  List<Map<String, dynamic>> guide,
  int season,
  int episode,
  int direction,
) {
  if (direction != 1 && direction != -1) return null;
  final rows =
      guide
          .where(
            (row) =>
                row['season'] is int &&
                row['number'] is int &&
                (row['season'] as int) > 0 &&
                (row['number'] as int) > 0,
          )
          .toList()
        ..sort((a, b) {
          final bySeason = (a['season'] as int).compareTo(b['season'] as int);
          return bySeason != 0
              ? bySeason
              : (a['number'] as int).compareTo(b['number'] as int);
        });
  final current = rows.indexWhere(
    (row) => row['season'] == season && row['number'] == episode,
  );
  if (current < 0) return null;
  for (var i = current + direction; i >= 0 && i < rows.length; i += direction) {
    final row = rows[i];
    if (row['season'] == season && row['number'] == episode) continue;
    if (direction > 0 && !isShuffleEpisodeEligible(row)) return null;
    return (season: row['season'] as int, episode: row['number'] as int);
  }
  return null;
}
