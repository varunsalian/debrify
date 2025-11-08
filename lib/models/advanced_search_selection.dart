class AdvancedSearchSelection {
  final String imdbId;
  final bool isSeries;
  final String title;
  final String? year;
  final int? season;
  final int? episode;

  const AdvancedSearchSelection({
    required this.imdbId,
    required this.isSeries,
    required this.title,
    this.year,
    this.season,
    this.episode,
  });

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

  const ImdbTitleResult({
    required this.imdbId,
    required this.title,
    this.year,
    this.posterUrl,
  });

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
}
