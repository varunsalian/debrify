import 'mdblist_service.dart';

/// The Rotten Tomatoes Tomatometer (critics, 0–100) for a title, read from
/// MDBList's title record. Needs the profile's MDBList key; without one the
/// request fails locally and the badge simply doesn't appear.
///
/// Uses [MdblistService.resolveImdb], whose result is cached and shared with
/// the detail page's MDBList status read, so a title costs at most one
/// request per cache window.
class MdblistRottenTomatoes {
  MdblistRottenTomatoes._();

  static Future<int?> fetch(String? imdbId, String type) async {
    if (imdbId == null || !imdbId.startsWith('tt')) return null;
    // Other types ('anime', 'tv', …) can't be mapped to MDBList's movie/show
    // lookup with confidence; guessing would cost a second request.
    if (type != 'movie' && type != 'series') return null;
    try {
      final result = await MdblistService.instance.resolveImdb(imdbId, type);
      return result.isSuccess ? criticsScore(result.data) : null;
    } catch (_) {
      return null;
    }
  }

  /// The `tomatoes` entry of the record's `ratings`, which MDBList sends as a
  /// list of `{source, value, score}`. A missing score is null, not zero:
  /// 0% is a real Tomatometer reading.
  static int? criticsScore(Map<String, dynamic>? title) {
    final ratings = title?['ratings'];
    if (ratings is! List) return null;
    for (final entry in ratings) {
      if (entry is! Map || entry['source'] != 'tomatoes') continue;
      final raw = entry['value'] ?? entry['score'];
      final value = raw is num ? raw : num.tryParse(raw?.toString() ?? '');
      if (value == null || value < 0 || value > 100) return null;
      return value.round();
    }
    return null;
  }
}
