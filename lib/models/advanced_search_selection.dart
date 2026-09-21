import 'custom_series_identity.dart';

class AdvancedSearchSelection {
  final bool initialContinuousShuffle;
  final String imdbId;
  final bool isSeries;
  final String title;
  final String? year;
  final int? season;
  final int? episode;

  /// Content type for Stremio streams: 'movie', 'series', 'tv', 'channel', etc.
  final String? contentType;

  /// Poster image URL from catalog
  final String? posterUrl;

  /// Exact Stremio identity for an episode supplied by a custom addon catalog.
  ///
  /// Cinemeta happens to use `<meta id>:<season>:<episode>`, but the Stremio
  /// protocol allows every video in a series meta response to have an arbitrary
  /// ID. Keep the origin configuration, parent meta ID, and video ID together
  /// so playback never has to guess that ID from season/episode coordinates.
  final String? stremioAddonId;
  final String? stremioAddonKey;
  final String? stremioCatalogId;
  final String? stremioVideoId;

  /// Trakt watch progress (0-100) for resuming playback from Trakt
  final double? traktProgressPercent;

  /// Whether this selection originated from Trakt (continue watching, watchlist, etc.)
  final bool traktSource;

  /// Simkl watch progress (0-100) — parallel to [traktProgressPercent].
  final double? simklProgressPercent;

  /// Whether this selection's resume position came from Simkl.
  final bool simklSource;
  final double? mdblistProgressPercent;
  final bool mdblistSource;

  /// True only when built by [EpisodesScreen]'s episode "Browse/Sources" tap.
  /// Lets the host return to the episode list (not the catalog grid) when the
  /// user backs out of the resulting torrent search. Intrinsic to this one
  /// selection, so it can't go stale or be confused with the Trakt inline
  /// episode browser (which leaves this false).
  final bool fromCatalogEpisodeDrillDown;

  /// True only when built by the catalog [CatalogItemDetailScreen]'s
  /// "Sources/Browse" tap for a movie / no-meta series. Lets the host return
  /// to that detail screen (not the catalog grid) when the user backs out of
  /// the resulting torrent search. Intrinsic to this one selection, so it
  /// can't go stale; mutually exclusive with [fromCatalogEpisodeDrillDown].
  final bool fromCatalogItemDetail;

  const AdvancedSearchSelection({
    this.initialContinuousShuffle = false,
    required this.imdbId,
    required this.isSeries,
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.contentType,
    this.posterUrl,
    this.stremioAddonId,
    this.stremioAddonKey,
    this.stremioCatalogId,
    this.stremioVideoId,
    this.traktProgressPercent,
    this.traktSource = false,
    this.simklProgressPercent,
    this.simklSource = false,
    this.mdblistProgressPercent,
    this.mdblistSource = false,
    this.fromCatalogEpisodeDrillDown = false,
    this.fromCatalogItemDetail = false,
  });

  /// Whether this is a non-IMDB content type (TV channel, etc.)
  bool get isNonImdb =>
      contentType != null && contentType != 'movie' && contentType != 'series';

  /// A copy of this selection scoped to [season] (null = whole series) with
  /// the episode cleared — a season-pack search scope (the Sources screen's
  /// Season chip). Kept in the model so a newly added field is carried here
  /// too instead of being silently dropped by an out-of-date inline copy.
  AdvancedSearchSelection scopedToSeason(int? season) =>
      AdvancedSearchSelection(
        initialContinuousShuffle: initialContinuousShuffle,
        imdbId: imdbId,
        isSeries: isSeries,
        title: title,
        year: year,
        season: season,
        episode: null,
        contentType: contentType,
        posterUrl: posterUrl,
        stremioAddonId: stremioAddonId,
        stremioAddonKey: stremioAddonKey,
        stremioCatalogId: stremioCatalogId,
        // A whole-season search is not the episode represented by this ID.
        stremioVideoId: null,
        traktProgressPercent: traktProgressPercent,
        traktSource: traktSource,
        simklProgressPercent: simklProgressPercent,
        simklSource: simklSource,
        mdblistProgressPercent: mdblistProgressPercent,
        mdblistSource: mdblistSource,
        fromCatalogEpisodeDrillDown: fromCatalogEpisodeDrillDown,
        fromCatalogItemDetail: fromCatalogItemDetail,
      );

  bool get hasStremioEpisodeIdentity =>
      stremioAddonKey?.trim().isNotEmpty == true &&
      stremioCatalogId?.trim().isNotEmpty == true;

  AdvancedSearchSelection withStremioEpisodeIdentity({
    required String addonId,
    required String addonKey,
    required String catalogId,
    required String videoId,
  }) => AdvancedSearchSelection(
    initialContinuousShuffle: initialContinuousShuffle,
    imdbId: CustomSeriesIdentity.parse(imdbId)?.catalogId == catalogId
        ? imdbId : CustomSeriesIdentity(addonKey, catalogId).id,
    isSeries: isSeries,
    title: title,
    year: year,
    season: season,
    episode: episode,
    contentType: contentType,
    posterUrl: posterUrl,
    stremioAddonId: addonId,
    stremioAddonKey: addonKey,
    stremioCatalogId: catalogId,
    stremioVideoId: videoId,
    traktSource: false,
    simklSource: false,
    mdblistSource: false,
    fromCatalogEpisodeDrillDown: fromCatalogEpisodeDrillDown,
    fromCatalogItemDetail: fromCatalogItemDetail,
  );

  String get displayQuery {
    if (!isSeries || season == null || episode == null) {
      return title;
    }
    final seasonLabel = season!.toString().padLeft(2, '0');
    final episodeLabel = episode!.toString().padLeft(2, '0');
    return '$title S${seasonLabel}E$episodeLabel';
  }

  String get formattedLabel {
    final buffer = StringBuffer(title);
    if (year != null && year!.trim().isNotEmpty) {
      buffer.write(' (${year!.trim()})');
    }
    if (isSeries && season != null && episode != null) {
      final seasonLabel = season!.toString().padLeft(2, '0');
      final episodeLabel = episode!.toString().padLeft(2, '0');
      buffer.write(' • S${seasonLabel}E$episodeLabel');
    }
    return buffer.toString();
  }
}

class ImdbTitleResult {
  final String imdbId;
  final String title;
  final String? year;
  final String? posterUrl;

  /// Content type for Stremio streams: 'movie', 'series', 'tv', 'channel', etc.
  /// Defaults to null for backward compatibility (treated as movie/series based on isSeries flag)
  final String? contentType;

  const ImdbTitleResult({
    required this.imdbId,
    required this.title,
    this.year,
    this.posterUrl,
    this.contentType,
  });

  /// Whether this is a non-IMDB content type (TV channel, etc.)
  bool get isNonImdb =>
      contentType != null && contentType != 'movie' && contentType != 'series';

  factory ImdbTitleResult.fromJson(Map<String, dynamic> json) {
    final id = (json['#IMDB_ID'] ?? '').toString();
    final title = (json['#TITLE'] ?? '').toString();
    return ImdbTitleResult(
      imdbId: id,
      title: title,
      year: json['#YEAR']?.toString(),
      posterUrl: json['#IMG_POSTER']?.toString(),
    );
  }

  /// Create from StremioMeta (supports any content type)
  factory ImdbTitleResult.fromStremioMeta(dynamic meta) {
    return ImdbTitleResult(
      imdbId: meta.id ?? '',
      title: meta.name ?? '',
      year: meta.year?.toString(),
      posterUrl: meta.poster,
      contentType: meta.type,
    );
  }
}
