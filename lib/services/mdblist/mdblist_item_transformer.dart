import '../../models/stremio_addon.dart';

/// Transforms MDBList list items into [StremioMeta] objects.
///
/// MDBList's `/lists/{id}/items` returns entries shaped like
/// `{ "title": "...", "imdb_id": "tt...", "mediatype": "movie"|"show",
/// "release_year": 2021, ... }`. Crucially they carry **no artwork**, so —
/// exactly like [TraktItemTransformer] — poster/background URLs are derived
/// from the IMDb id via Stremio's metahub CDN. Items without a valid IMDb id
/// are dropped (they can't be resolved or given art).
class MdblistItemTransformer {
  MdblistItemTransformer._();

  static StremioMeta? transformItem(Map<String, dynamic> raw) {
    final imdbId = raw['imdb_id'] as String?;
    if (imdbId == null || !imdbId.startsWith('tt')) return null;

    final rawType = (raw['mediatype'] as String?)?.toLowerCase();
    final internalType =
        (rawType == 'show' || rawType == 'series' || rawType == 'tv')
        ? 'series'
        : 'movie';

    String? year;
    final ry = raw['release_year'];
    if (ry is int) {
      year = ry.toString();
    } else if (ry is String && ry.isNotEmpty) {
      year = ry;
    }

    // No artwork in the payload — generate from the IMDb id via metahub, the
    // same fallback the Trakt transformer uses.
    final poster = 'https://images.metahub.space/poster/medium/$imdbId/img';
    final background =
        'https://images.metahub.space/background/medium/$imdbId/img';

    return StremioMeta(
      id: imdbId,
      imdbId: imdbId,
      type: internalType,
      name: raw['title'] as String? ?? 'Unknown',
      poster: poster,
      background: background,
      year: year,
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
}
