import '../../models/stremio_addon.dart';

/// Transforms MDBList list items into [StremioMeta] objects.
///
/// MDBList browse endpoints use two compatible-but-different shapes: list and
/// catalog items are usually flat, while sync snapshots wrap the media under
/// `movie` or `show`. This transformer deliberately accepts both so Discover
/// never mistakes a history wrapper for a title or emits episode-only cards.
class MdblistItemTransformer {
  MdblistItemTransformer._();

  static StremioMeta? transformItem(Map<String, dynamic> raw) {
    final nestedMovie = _map(raw['movie']);
    final nestedShow = _map(raw['show']);
    final wrapperType = _string(raw['mediatype'] ?? raw['type'])?.toLowerCase();
    if (nestedMovie == null &&
        nestedShow == null &&
        (raw['episode'] != null ||
            wrapperType == 'episode' ||
            wrapperType == 'season')) {
      return null;
    }
    final media = nestedMovie ?? nestedShow ?? raw;
    final ids = _map(media['ids']) ?? _map(raw['ids']);
    final imdbId = _string(media['imdb_id'] ?? raw['imdb_id'] ?? ids?['imdb']);
    if (imdbId == null || !imdbId.startsWith('tt')) return null;

    final rawType = _string(
      media['mediatype'] ?? media['type'] ?? raw['mediatype'] ?? raw['type'],
    )?.toLowerCase();
    final internalType =
        nestedShow != null ||
            rawType == 'show' ||
            rawType == 'series' ||
            rawType == 'tv'
        ? 'series'
        : 'movie';

    String? year;
    final ry = media['release_year'] ?? media['year'] ?? raw['release_year'];
    if (ry is int) {
      year = ry.toString();
    } else if (ry is String && ry.isNotEmpty) {
      year = ry;
    }

    final poster =
        _string(media['poster'] ?? media['poster_url'] ?? raw['poster']) ??
        'https://images.metahub.space/poster/medium/$imdbId/img';
    final background =
        _string(
          media['background'] ??
              media['backdrop'] ??
              media['backdrop_url'] ??
              raw['background'],
        ) ??
        'https://images.metahub.space/background/medium/$imdbId/img';

    return StremioMeta(
      id: imdbId,
      imdbId: imdbId,
      type: internalType,
      name:
          _string(media['title'] ?? media['name'] ?? raw['title']) ?? 'Unknown',
      poster: poster,
      background: background,
      description: _string(
        media['description'] ?? media['overview'] ?? raw['description'],
      ),
      year: year,
      imdbRating: _imdbRating(media['ratings'] ?? raw['ratings']),
      genres: _genres(media['genre'] ?? media['genres'] ?? raw['genres']),
      runtime: _runtime(media['runtime'] ?? raw['runtime']),
      addedAtMs: _timestamp(raw, media),
    );
  }

  /// Transform a list of MDBList items. Items without valid IMDb ids are skipped.
  static List<StremioMeta> transformItems(List<dynamic> items) {
    final out = <StremioMeta>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final meta = transformItem(raw);
      if (meta != null) out.add(meta);
    }
    return out;
  }

  static Map<String, dynamic>? _map(Object? value) =>
      value is Map<String, dynamic>
      ? value
      : value is Map
      ? Map<String, dynamic>.from(value)
      : null;

  static String? _string(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _imdbRating(Object? ratings) {
    if (ratings is Map) {
      final value = ratings['imdb'] ?? ratings['imdb_rating'];
      if (value is Map) {
        return _double(value['rating'] ?? value['value']);
      }
      return _double(value);
    }
    if (ratings is List) {
      for (final raw in ratings) {
        final rating = _map(raw);
        if (rating == null) continue;
        final source = _string(
          rating['source'] ?? rating['provider'] ?? rating['name'],
        )?.toLowerCase();
        if (source == 'imdb') {
          return _double(
            rating['rating'] ?? rating['value'] ?? rating['score'],
          );
        }
      }
    }
    return null;
  }

  static List<String>? _genres(Object? value) {
    final genres = <String>[];
    if (value is List) {
      for (final raw in value) {
        final genre = raw is Map
            ? _string(raw['name'] ?? raw['slug'])
            : _string(raw);
        if (genre != null) genres.add(genre);
      }
    } else if (value is String) {
      genres.addAll(
        value.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty),
      );
    }
    return genres.isEmpty ? null : genres;
  }

  static String? _runtime(Object? value) {
    if (value is num && value > 0) return '${value.toInt()} min';
    return _string(value);
  }

  static int? _timestamp(
    Map<String, dynamic> wrapper,
    Map<String, dynamic> media,
  ) {
    for (final key in const [
      'last_watched_at',
      'watched_at',
      'rated_at',
      'collected_at',
      'dropped_at',
      'listed_at',
      'watchlist_at',
      'added_at',
      'updated_at',
    ]) {
      final raw = wrapper[key] ?? media[key];
      if (raw is num) return raw.toInt();
      final parsed = raw is String ? DateTime.tryParse(raw) : null;
      if (parsed != null) return parsed.toUtc().millisecondsSinceEpoch;
    }
    return null;
  }

  static double? _double(Object? value) => value is num
      ? value.toDouble()
      : value is String
      ? double.tryParse(value)
      : null;
}
