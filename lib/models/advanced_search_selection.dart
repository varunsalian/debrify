class AdvancedSearchSelection {
  final String imdbId;
  final bool isSeries;
  final String title;
  final String? year;
  final int? season;
  final int? episode;
  /// Content type for Stremio streams: 'movie', 'series', 'tv', 'channel', etc.
  final String? contentType;

  const AdvancedSearchSelection({
    required this.imdbId,
    required this.isSeries,
    required this.title,
    this.year,
    this.season,
    this.episode,
    this.contentType,
  });

  /// Whether this is a non-IMDB content type (TV channel, etc.)
  bool get isNonImdb => contentType != null && contentType != 'movie' && contentType != 'series';

  String get displayQuery {
    if (!isSeries || season == null || episode == null) {
      return title;
    }
    final seasonLabel = season!.toString().padLeft(2, '0');
    final episodeLabel = episode!.toString().padLeft(2, '0');
    return '$title S${seasonLabel}E${episodeLabel}';
  }

  String get formattedLabel {
    final buffer = StringBuffer(title);
    if (year != null && year!.trim().isNotEmpty) {
      buffer.write(' (${year!.trim()})');
    }
    if (isSeries && season != null && episode != null) {
      final seasonLabel = season!.toString().padLeft(2, '0');
      final episodeLabel = episode!.toString().padLeft(2, '0');
      buffer.write(' • S${seasonLabel}E${episodeLabel}');
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
  bool get isNonImdb => contentType != null && contentType != 'movie' && contentType != 'series';

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
