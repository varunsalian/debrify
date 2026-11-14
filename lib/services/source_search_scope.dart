import '../models/custom_series_identity.dart';
import 'diagnostic_log.dart';

/// Which kinds of title can use IMDb-based search, and a privacy-safe record
/// of what one search actually did. Titles, IDs and addon-supplied text are
/// never logged: only fixed labels and counts leave this class.
abstract final class SourceSearchScope {
  // Anime catalogs are series-like. Scrapers still need a real IMDb ID.
  static const Set<String> _imdbContentTypes = {'movie', 'series', 'anime'};
  static const Set<String> _knownContentTypes = {
    ..._imdbContentTypes,
    'tv',
    'channel',
  };
  static const Set<String> _knownIdSchemes = {
    'mal',
    'kitsu',
    'anilist',
    'anidb',
    'tmdb',
    'tvdb',
    'trakt',
  };

  static bool isImdbContent(String? contentType) =>
      contentType == null || _imdbContentTypes.contains(contentType);

  static bool enginesCanRun(
    String imdbId,
    String? contentType,
    String? originVideoId,
  ) =>
      engineSkipReason(
        imdbId: imdbId,
        contentType: contentType,
        originVideoId: originVideoId,
      ) ==
      null;

  /// Why built-in scrapers cannot run for this search, or null when they can.
  static String? engineSkipReason({
    required String imdbId,
    String? contentType,
    String? originVideoId,
  }) {
    if (!isImdbContent(contentType)) return 'skipped_content_type';
    if (!imdbId.startsWith('tt')) return 'skipped_not_imdb';
    if (originVideoId?.trim().isNotEmpty == true) {
      return 'skipped_custom_episode';
    }
    return null;
  }

  static Map<String, Object?> fields({
    required String surface,
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
    String? contentType,
    String? originVideoId,
    bool enginesRequested = true,
    required Map<String, dynamic> result,
  }) {
    final skip = engineSkipReason(
      imdbId: imdbId,
      contentType: contentType,
      originVideoId: originVideoId,
    );
    var scraperResults = 0;
    var addonResults = 0;
    var mediaServerResults = 0;
    final counts = result['engineCounts'];
    if (counts is Map) {
      counts.forEach((key, value) {
        if (value is! int) return;
        final name = key.toString();
        if (name.startsWith('stremio:')) {
          addonResults += value;
        } else if (name.startsWith('mediaserver:')) {
          mediaServerResults += value;
        } else {
          scraperResults += value;
        }
      });
    }
    // Addon-only searches report under their own keys.
    final onlyAddonCounts = result['addonCounts'];
    if (onlyAddonCounts is Map) {
      for (final value in onlyAddonCounts.values) {
        if (value is int) addonResults += value;
      }
    }
    final errors = result['engineErrors'] ?? result['addonErrors'];
    final rows = result['torrents'];
    return <String, Object?>{
      'surface': DiagnosticLabel(surface),
      'search_scope': DiagnosticLabel(
        isMovie
            ? 'movie'
            : episode != null
            ? 'episode'
            : season != null
            ? 'season'
            : 'whole_series',
      ),
      'content_type': DiagnosticLabel(_contentTypeLabel(contentType)),
      'id_kind': DiagnosticLabel(_idKind(imdbId)),
      'scrapers': DiagnosticLabel(
        enginesRequested ? skip ?? 'ran' : 'not_requested',
      ),
      'scraper_results': scraperResults,
      'addon_results': addonResults,
      'media_server_results': mediaServerResults,
      'total_results': rows is List ? rows.length : 0,
      'error_count': errors is Map ? errors.length : 0,
    };
  }

  static void log({
    required String surface,
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
    String? contentType,
    String? originVideoId,
    bool enginesRequested = true,
    required Map<String, dynamic> result,
  }) => DiagnosticLog.instance.recordEvent(
    source: 'source_selection',
    event: 'source_search_scope',
    fields: fields(
      surface: surface,
      imdbId: imdbId,
      isMovie: isMovie,
      season: season,
      episode: episode,
      contentType: contentType,
      originVideoId: originVideoId,
      enginesRequested: enginesRequested,
      result: result,
    ),
  );

  static String _contentTypeLabel(String? contentType) {
    if (contentType == null) return 'unspecified';
    return _knownContentTypes.contains(contentType) ? contentType : 'other';
  }

  static String _idKind(String id) {
    if (id.startsWith('tt')) return 'imdb';
    if (CustomSeriesIdentity.isCustom(id)) return 'custom';
    final scheme = id.split(':').first;
    return _knownIdSchemes.contains(scheme) ? scheme : 'other';
  }
}
