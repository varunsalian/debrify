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

  /// Parse a raw Simkl public-calendar item (from
  /// `data.simkl.in/calendar/{tv,anime}.json`) into the same shape, so the
  /// calendar screen can render Trakt and Simkl entries identically. Returns
  /// `null` when an essential field is missing OR the item has no `tt…` IMDb id
  /// — the app is IMDb-keyed, so a Simkl-only id can't be matched to the user's
  /// library or handed to the detail page. Simkl's calendar carries no episode
  /// title/overview/runtime, so those stay null; `showTraktId` is null too
  /// (only used for Trakt de-dup). Shape (per Simkl docs / live response):
  /// `{ title, poster, date (ISO w/ tz offset), release_date, ids: { imdb,
  /// simkl_id, ... }, episode: { season, episode } }`.
  static TraktCalendarEntry? fromSimklCalendarJson(Map<String, dynamic> json) {
    final dateStr = json['date'] as String?;
    if (dateStr == null || dateStr.length < 10) return null;

    // Simkl's `date` is a nominal calendar-day marker (midnight US-Eastern,
    // e.g. `2026-07-22T00:00:00-04:00`), NOT a real air instant. Re-localizing
    // it (toLocal) would shift the day one earlier for everyone west of Eastern
    // — a US-Pacific user would see a July-22 episode under July 21. So bucket
    // by the DATE COMPONENT: anchor a LOCAL midnight on that Y-M-D, so
    // getRange's local-day grouping lands on the day Simkl intended for every
    // timezone. (Trakt's `first_aired` IS a true UTC instant, so its parser
    // above correctly re-localizes; only Simkl's nominal marker needs this.)
    final airedYear = int.tryParse(dateStr.substring(0, 4));
    final airedMonth = int.tryParse(dateStr.substring(5, 7));
    final airedDay = int.tryParse(dateStr.substring(8, 10));
    if (airedYear == null || airedMonth == null || airedDay == null) return null;
    final airedLocal = DateTime(airedYear, airedMonth, airedDay);
    final firstAiredUtc = airedLocal.toUtc();

    final title = json['title'] as String?;
    if (title == null || title.isEmpty) return null;

    final episode = json['episode'];
    if (episode is! Map) return null;
    final seasonRaw = episode['season'];
    final numberRaw = episode['episode'];
    if (seasonRaw is! int || numberRaw is! int) return null;

    final ids = json['ids'];
    final imdb = ids is Map ? ids['imdb'] as String? : null;
    if (imdb == null || !imdb.startsWith('tt')) return null;

    int? showYear;
    final releaseDate = json['release_date'];
    if (releaseDate is String && releaseDate.length >= 4) {
      showYear = int.tryParse(releaseDate.substring(0, 4));
    }

    return TraktCalendarEntry(
      firstAiredUtc: firstAiredUtc,
      firstAiredLocal: airedLocal,
      showTitle: title,
      showYear: showYear,
      showImdbId: imdb,
      showTraktId: null,
      seasonNumber: seasonRaw,
      episodeNumber: numberRaw,
      episodeTitle: null,
      episodeOverview: null,
      runtimeMinutes: null,
      posterUrl: 'https://images.metahub.space/poster/medium/$imdb/img',
    );
  }
}
