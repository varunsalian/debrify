import '../../models/stremio_addon.dart';

/// Transforms Simkl API items into [StremioMeta] objects.
///
/// Simkl splits content into movies/shows/anime, but [StremioMeta.type] (and
/// every screen that renders it) only knows `'movie'`/`'series'` — so anime is
/// folded into whichever of those two it structurally matches rather than
/// introducing a third type app-wide. Movie-shaped anime entries are rare in
/// the endpoints this app calls (best/premieres skew TV-style); the heuristic
/// below only has to be "mostly right", not perfect, since a stray anime film
/// showing up in the Series bucket is a cosmetic filter miss, not a crash.
class SimklItemTransformer {
  SimklItemTransformer._();

  /// Transform a single Simkl API item into a [StremioMeta].
  /// Returns null if the item lacks a valid IMDb ID — Simkl's anime entries
  /// are sometimes only identified by MAL/AniDB ids, which this app's
  /// IMDb-centric model (shared with the Trakt integration) can't represent.
  ///
  /// Simkl items show up in three shapes depending on the endpoint:
  ///  - `/sync/all-items`, `/sync/ratings`: `{ "show": {...} }` or
  ///    `{ "movie": {...} }`, with watchlist metadata (status, rating, etc.)
  ///    alongside.
  ///  - `/tv/best`, `/tv/premieres`, `/anime/best`, `/anime/premieres`: flat
  ///    `{ "title": ..., "ids": {...}, ... }` — the item IS the content.
  ///  - Trending CDN files, `/movies/genres/...`: also flat, same shape as
  ///    above.
  ///
  /// [inferredType] is the fallback `'movie'`/`'series'` for flat shapes that
  /// don't otherwise disambiguate (e.g. every item from a movies-only fetch).
  static StremioMeta? transformItem(
    Map<String, dynamic> raw, {
    String? inferredType,
  }) {
    Map<String, dynamic>? content;
    String? shapeType; // 'movie' / 'series', when the wrapper key tells us
    if (raw['show'] is Map) {
      content = (raw['show'] as Map).cast<String, dynamic>();
      shapeType = 'series';
    } else if (raw['movie'] is Map) {
      content = (raw['movie'] as Map).cast<String, dynamic>();
      shapeType = 'movie';
    } else if (raw.containsKey('ids')) {
      // Flat shape — the item IS the content (best/premieres/trending/genre
      // endpoints).
      content = raw;
    }
    if (content == null) return null;

    final ids = content['ids'] as Map<String, dynamic>? ?? {};
    final imdbId = ids['imdb'] as String?;
    if (imdbId == null || !imdbId.startsWith('tt')) return null;

    // Anime is wrapped exactly like a TV show (`{"show": {...}}`) with an
    // explicit `anime_type` sibling field distinguishing an anime movie from
    // an episodic one — checked FIRST, since `shapeType` alone would
    // otherwise always resolve to 'series' for every show-wrapped item,
    // anime movies included. Falls back to whether the item looks episodic
    // (has a season/episode count), then finally [inferredType].
    final animeType = content['anime_type'] as String?;
    final looksEpisodic =
        content['total_episodes_count'] != null ||
        content['episodes'] != null;
    final internalType = animeType == 'movie'
        ? 'movie'
        : (shapeType ?? (looksEpisodic ? 'series' : (inferredType ?? 'series')));

    String? poster = _imageUrl(content['poster'] as String?, 'posters', '_m');
    String? fanart = _imageUrl(content['fanart'] as String?, 'fanart', '_w');

    // whereType (not a force-cast) so one non-string genre entry drops that
    // entry instead of throwing and stranding the whole fetch mid-transform.
    final genres = (content['genres'] as List<dynamic>?)
        ?.whereType<String>()
        .toList();

    double? rating;
    final ratingsBlock = content['ratings'] as Map<String, dynamic>?;
    final simklRatingBlock = ratingsBlock?['simkl'] as Map<String, dynamic>?;
    final rawRating = simklRatingBlock?['rating'] ?? content['rating'];
    if (rawRating is num) {
      rating = (rawRating.toDouble() * 10).roundToDouble() / 10;
    }

    String? year;
    final rawYear = content['year'];
    if (rawYear is int) {
      year = rawYear.toString();
    } else if (rawYear is String) {
      year = rawYear;
    }

    // Fall back to Stremio's metahub CDN (same as the Trakt transformer) when
    // Simkl doesn't supply an image at all, so a miss here fails safe (a
    // generic poster) instead of a broken image.
    poster ??= 'https://images.metahub.space/poster/medium/$imdbId/img';
    fanart ??= 'https://images.metahub.space/background/medium/$imdbId/img';

    return StremioMeta(
      id: imdbId,
      imdbId: imdbId,
      type: internalType,
      name: content['title'] as String? ?? 'Unknown',
      poster: poster,
      background: fanart,
      description: content['overview'] as String? ?? content['description'] as String?,
      year: year,
      imdbRating: rating,
      genres: genres,
      addedAtMs: rowDateMs(raw),
    );
  }

  /// Epoch-ms of the date the WRAPPER row carries, or null for the flat shapes
  /// (best/premieres/trending/genre) that are catalogue rows rather than the
  /// user's own.
  ///
  /// `added_to_watchlist_at` is the one the user means by "date added" — it is
  /// set when the title enters the list and does not move when they watch or
  /// rate it. The other two are fallbacks for rows that predate it or come
  /// from `/sync/ratings`.
  static int? rowDateMs(Map<String, dynamic> row) {
    const fields = [
      'added_to_watchlist_at',
      'user_rated_at',
      'last_watched_at',
    ];
    for (final f in fields) {
      final v = row[f];
      if (v is String) {
        final t = DateTime.tryParse(v);
        if (t != null) return t.millisecondsSinceEpoch;
      }
    }
    return null;
  }

  /// Simkl's poster/fanart fields are a bare CDN path/hash (e.g.
  /// `"74/74415673dcdc9cdd"`), not a ready-to-use URL — built into
  /// `https://simkl.in/{category}/{path}{size}.webp` per Simkl's documented
  /// image convention (api.simkl.org/conventions/images). A value that's
  /// already a full URL (some endpoints may differ) is used as-is.
  static String? _imageUrl(String? raw, String category, String size) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return 'https://simkl.in/$category/$raw$size.webp';
  }

  /// Transform a list of Simkl API items into [StremioMeta] objects.
  /// Items without a valid IMDb ID are skipped.
  static List<StremioMeta> transformList(
    List<dynamic> items, {
    String? inferredType,
  }) {
    final result = <StremioMeta>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final meta = transformItem(raw, inferredType: inferredType);
      if (meta != null) result.add(meta);
    }
    return result;
  }
}
