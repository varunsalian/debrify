/// Domain model for a single Trakt calendar entry (upcoming episode).
///
/// Built from `/calendars/my/shows` responses via [fromTraktJson].
class TraktCalendarEntry {
  /// Air time parsed as UTC from Trakt's `first_aired` ISO-8601 string.
  final DateTime firstAiredUtc;

  /// Air time converted to the device's local timezone.
  /// Used for date bucketing (grouping by "today", "tomorrow", etc).
  final DateTime firstAiredLocal;

  final String showTitle;
  final int? showYear;
  final String? showImdbId;
  final int? showTraktId;
  final int seasonNumber;
  final int episodeNumber;
  final String? episodeTitle;
  final String? episodeOverview;
  final int? runtimeMinutes;

  /// Poster URL, resolved via Stremio metahub fallback when `showImdbId` is present.
  final String? posterUrl;

  const TraktCalendarEntry({
    required this.firstAiredUtc,
    required this.firstAiredLocal,
    required this.showTitle,
    required this.showYear,
    required this.showImdbId,
    required this.showTraktId,
    required this.seasonNumber,
    required this.episodeNumber,
    required this.episodeTitle,
    required this.episodeOverview,
    required this.runtimeMinutes,
    required this.posterUrl,
  });

  /// True when this is episode 1 of season 1 — a brand-new show premiere.
  bool get isNewShow => seasonNumber == 1 && episodeNumber == 1;

  /// True when this is the first episode of any season (includes new shows).
  bool get isSeasonPremiere => episodeNumber == 1;

  /// Parse a raw Trakt calendar item. Returns `null` when any essential field
  /// is missing or malformed — callers should filter nulls.
  static TraktCalendarEntry? fromTraktJson(Map<String, dynamic> json) {
    final firstAiredStr = json['first_aired'] as String?;
    if (firstAiredStr == null || firstAiredStr.isEmpty) return null;

    DateTime firstAiredUtc;
    try {
      final parsed = DateTime.parse(firstAiredStr);
      firstAiredUtc = parsed.isUtc ? parsed : parsed.toUtc();
    } catch (_) {
      return null;
    }

    final show = json['show'] as Map<String, dynamic>?;
    final episode = json['episode'] as Map<String, dynamic>?;
    if (show == null || episode == null) return null;

    final showTitle = show['title'] as String?;
    if (showTitle == null || showTitle.isEmpty) return null;

    final seasonRaw = episode['season'];
    final numberRaw = episode['number'];
    if (seasonRaw is! int || numberRaw is! int) return null;

    final ids = show['ids'] as Map<String, dynamic>? ?? const {};
    final imdb = ids['imdb'] as String?;
    final traktId = ids['trakt'] is int ? ids['trakt'] as int : null;

    String? poster;
    if (imdb != null && imdb.startsWith('tt')) {
      poster = 'https://images.metahub.space/poster/medium/$imdb/img';
    }

    return TraktCalendarEntry(
      firstAiredUtc: firstAiredUtc,
      firstAiredLocal: firstAiredUtc.toLocal(),
      showTitle: showTitle,
      showYear: show['year'] is int ? show['year'] as int : null,
      showImdbId: imdb,
      showTraktId: traktId,
      seasonNumber: seasonRaw,
      episodeNumber: numberRaw,
      episodeTitle: episode['title'] as String?,
      episodeOverview: episode['overview'] as String?,
      runtimeMinutes: episode['runtime'] is int ? episode['runtime'] as int : null,
      posterUrl: poster,
    );
  }
}
