import '../../models/stremio_addon.dart';

/// Transforms Trakt API items into [StremioMeta] objects.
///
/// Used by both the TraktResultsView (home page Trakt source) and
/// the Stremio TV local catalog importer.
class TraktItemTransformer {
  TraktItemTransformer._();

  /// Transform a single Trakt API item into a [StremioMeta].
  /// Returns null if the item lacks a valid IMDB ID.
  ///
  /// Trakt items have the shape `{ "type": "movie", "movie": { ... } }` or
  /// `{ "type": "show", "show": { ... } }`.
  /// The recommendations endpoint returns flat objects: `{ "title": "...", "ids": {...} }`.
  /// The watched endpoint returns `{ "movie": { ... } }` or `{ "show": { ... } }` without `type`.
  ///
  /// [inferredType] is used as a fallback when `type` is absent (recommendations, watched).
  static StremioMeta? transformItem(Map<String, dynamic> raw, {String? inferredType}) {
    final type = raw['type'] as String?;
    Map<String, dynamic>? content;
    if (type != null) {
      content = (raw[type] ?? raw['movie'] ?? raw['show']) as Map<String, dynamic>?;
    } else if (raw.containsKey('ids')) {
      // Flat format from recommendations endpoint — the item IS the content
      content = raw;
    } else if (raw.containsKey('movie')) {
      // Watched endpoint: no type field, content nested under 'movie'
      content = raw['movie'] as Map<String, dynamic>?;
    } else if (raw.containsKey('show')) {
      // Watched endpoint: no type field, content nested under 'show'
      content = raw['show'] as Map<String, dynamic>?;
    }
    if (content == null) return null;

    final ids = content['ids'] as Map<String, dynamic>? ?? {};
    final imdbId = ids['imdb'] as String?;
    if (imdbId == null || !imdbId.startsWith('tt')) return null;

    final internalType = (type ?? inferredType) == 'show' ? 'series' : 'movie';

    // Resolve poster/fanart from images map
    String? poster;
    String? fanart;
    final images = content['images'] as Map<String, dynamic>?;
    if (images != null) {
      final posterList = images['poster'] as List<dynamic>?;
      if (posterList != null && posterList.isNotEmpty) {
        final url = posterList.first as String?;
        if (url != null) {
          poster = url.startsWith('http') ? url : 'https://$url';
        }
      }
      final fanartList = images['fanart'] as List<dynamic>?;
      if (fanartList != null && fanartList.isNotEmpty) {
        final url = fanartList.first as String?;
        if (url != null) {
          fanart = url.startsWith('http') ? url : 'https://$url';
        }
      }
    }

    // Resolve genres (Trakt uses lowercase hyphenated, e.g. "science-fiction")
    final genres = (content['genres'] as List<dynamic>?)
        ?.cast<String>()
        .map((g) => g
            .split('-')
            .map((w) =>
                w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' '))
        .toList();

    // Round rating to 1 decimal place
    double? rating;
    final rawRating = content['rating'];
    if (rawRating is num) {
      rating = (rawRating.toDouble() * 10).roundToDouble() / 10;
    }

    // Handle year
    String? year;
    final rawYear = content['year'];
    if (rawYear is int) {
      year = rawYear.toString();
    } else if (rawYear is String) {
      year = rawYear;
    }

    // Trakt API does not serve images — generate poster URL from IMDB ID
    // using Stremio's metahub CDN as fallback
    poster ??= 'https://images.metahub.space/poster/medium/$imdbId/img';
    fanart ??= 'https://images.metahub.space/background/medium/$imdbId/img';

    return StremioMeta(
      id: imdbId,
      imdbId: imdbId,
      type: internalType,
      name: content['title'] as String? ?? 'Unknown',
      poster: poster,
      background: fanart,
      description: content['overview'] as String?,
      year: year,
      imdbRating: rating,
      genres: genres,
    );
  }

  /// Transform a list of Trakt API items into [StremioMeta] objects.
  /// Items without valid IMDB IDs are skipped.
  ///
  /// [inferredType] is used as a fallback type for items without a `type` field
  /// (e.g. from the recommendations endpoint). Pass `'movie'` or `'show'`.
  static List<StremioMeta> transformList(List<dynamic> items, {String? inferredType}) {
    final result = <StremioMeta>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final meta = transformItem(raw, inferredType: inferredType);
      if (meta != null) result.add(meta);
    }
    return result;
  }

  /// Transform playback episode items into deduplicated show [StremioMeta] objects.
  /// Playback episodes have shape: { "type": "episode", "episode": {...}, "show": {...} }
  /// We extract the show and deduplicate by IMDB ID so each show appears once.
  static List<StremioMeta> transformPlaybackEpisodes(List<dynamic> items) {
    final seen = <String>{};
    final result = <StremioMeta>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final show = raw['show'] as Map<String, dynamic>?;
      if (show == null) continue;
      final meta = transformItem({'show': show}, inferredType: 'show');
      if (meta == null) continue;
      if (seen.contains(meta.id)) continue;
      seen.add(meta.id);
      result.add(meta);
    }
    return result;
  }
}
