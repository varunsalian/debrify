import '../../models/media_identity.dart';

/// Completed movies and caught-up series in one `/sync/all-items/all/all`
/// response (see `SimklService.fetchCompletedTitleIds`), as the IDs whose
/// posters get a watched tick.
///
/// A series is caught up when every aired regular episode is watched; Simkl
/// keeps such an ongoing show in `watching`, so the counters decide rather
/// than the `completed` bucket. Anime is one Simkl title per cour sharing the
/// show's IMDb/TVDB ids, so a shared id is caught up only when every cour in
/// the library carrying it is.
final class SimklCompletedTitles {
  SimklCompletedTitles._();

  static ({Set<String> movies, Set<String> series}) parse(
    Map<String, dynamic> data,
  ) {
    final movies = <String>{};
    final series = <String>{};

    String? imdbOf(Map<String, dynamic> raw) {
      final content = (raw['movie'] ?? raw['show']) as Map<String, dynamic>?;
      final ids = content?['ids'] as Map<String, dynamic>?;
      return MediaIdentity.preferred(ids);
    }

    void parseMovies(dynamic bucket) {
      if (bucket is! List) return;
      for (final raw in bucket) {
        if (raw is! Map<String, dynamic> || raw['status'] != 'completed') {
          continue;
        }
        final imdb = imdbOf(raw);
        if (imdb != null) {
          movies.addAll(
            MediaIdentity.aliases(
              (raw['movie'] ?? raw['show'])['ids'],
            ).map((id) => MediaIdentity.progressId(id, 'movie')),
          );
        }
      }
    }

    // Each episodic entry's aliases, whether it is caught up, and whether it
    // has aired at all.
    Iterable<(Set<String>, bool, bool)> seriesEntries(dynamic bucket) sync* {
      if (bucket is! List) return;
      for (final raw in bucket) {
        if (raw is! Map<String, dynamic>) continue;
        final imdb = imdbOf(raw);
        if (imdb == null) continue;
        final watched = _asNum(raw['watched_episodes_count'])?.toInt();
        final total = _asNum(raw['total_episodes_count'])?.toInt();
        final notAired = _asNum(raw['not_aired_episodes_count'])?.toInt() ?? 0;
        final aired = total == null ? null : total - notAired;
        final caughtUp =
            watched != null && aired != null && aired > 0 && watched >= aired;
        // `completed` remains a safe fallback for older/minimal response
        // shapes that omit counters entirely.
        yield (
          MediaIdentity.aliases((raw['show'] ?? raw['movie'])['ids']),
          caughtUp ||
              (watched == null &&
                  total == null &&
                  raw['status'] == 'completed'),
          aired == null || aired > 0,
        );
      }
    }

    parseMovies(data['movies']);
    for (final (aliases, caughtUp, _) in seriesEntries(data['shows'])) {
      if (caughtUp) series.addAll(aliases);
    }
    // Simkl wraps anime movies and episodic anime together. Preserve the same
    // mapping used by SimklItemTransformer so their poster cards get the
    // correct movie/series badge semantics too.
    final anime = data['anime'];
    if (anime is List) {
      parseMovies([
        for (final raw in anime)
          if (raw is Map<String, dynamic> && raw['anime_type'] == 'movie') raw,
      ]);
      // Anime is one Simkl title per cour, and the cours share the show's
      // IMDb/TVDB ids: an id is caught up only when every aired entry carrying
      // it is (an announced next cour, nothing aired yet, doesn't count).
      final caughtUpById = <String, bool>{};
      for (final (aliases, caughtUp, aired) in seriesEntries([
        for (final raw in anime)
          if (raw is Map<String, dynamic> && raw['anime_type'] != 'movie') raw,
      ])) {
        if (!aired) continue;
        for (final id in aliases) {
          caughtUpById[id] = (caughtUpById[id] ?? true) && caughtUp;
        }
      }
      series.addAll([
        for (final MapEntry(:key, :value) in caughtUpById.entries)
          if (value) key,
      ]);
    }
    return (movies: movies, series: series);
  }

  static num? _asNum(dynamic v) {
    if (v is num) return v;
    if (v is String) return num.tryParse(v);
    return null;
  }
}
