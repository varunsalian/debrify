class Torrent {
  final int rowid;
  final String infohash;
  final String name;
  final int sizeBytes;
  final int createdUnix;
  final int seeders;
  final int leechers;
  final int completed;
  final int scrapedDate;
  final String? category; // Optional: PirateBay category (5xx = NSFW)
  final String source;

  // Coverage detection fields
  final String? coverageType; // 'completeSeries', 'multiSeasonPack', 'seasonPack', 'singleEpisode'
  final int? startSeason;
  final int? endSeason;
  final int? seasonNumber;
  final String? transformedTitle; // The improved, user-friendly title
  final String? episodeIdentifier; // e.g., "S01E01" for what's being played

  Torrent({
    required this.rowid,
    required this.infohash,
    required this.name,
    required this.sizeBytes,
    required this.createdUnix,
    required this.seeders,
    required this.leechers,
    required this.completed,
    required this.scrapedDate,
    this.category,
    String? source,
    this.coverageType,
    this.startSeason,
    this.endSeason,
    this.seasonNumber,
    this.transformedTitle,
    this.episodeIdentifier,
  }) : source = (source ?? '').trim().toLowerCase();

  factory Torrent.fromJson(
    Map<String, dynamic> json, {
    String? source,
  }) {
    final dynamic rawSource =
        json['source'] ?? json['provider'] ?? json['engine'] ?? source;
    return Torrent(
      rowid: json['rowid'] ?? 0,
      infohash: json['infohash'] ?? '',
      name: json['name'] ?? '',
      sizeBytes: json['size_bytes'] ?? 0,
      createdUnix: json['created_unix'] ?? 0,
      seeders: json['seeders'] ?? 0,
      leechers: json['leechers'] ?? 0,
      completed: json['completed'] ?? 0,
      scrapedDate: json['scraped_date'] ?? 0,
      category: json['category']?.toString(),
      source: rawSource?.toString(),
      coverageType: json['coverage_type']?.toString(),
      startSeason: json['start_season'] as int?,
      endSeason: json['end_season'] as int?,
      seasonNumber: json['season_number'] as int?,
      transformedTitle: json['transformed_title']?.toString(),
      episodeIdentifier: json['episode_identifier']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rowid': rowid,
      'infohash': infohash,
      'name': name,
      'size_bytes': sizeBytes,
      'created_unix': createdUnix,
      'seeders': seeders,
      'leechers': leechers,
      'completed': completed,
      'scraped_date': scrapedDate,
      if (category != null) 'category': category,
      if (source.isNotEmpty) 'source': source,
      if (coverageType != null) 'coverage_type': coverageType,
      if (startSeason != null) 'start_season': startSeason,
      if (endSeason != null) 'end_season': endSeason,
      if (seasonNumber != null) 'season_number': seasonNumber,
      if (transformedTitle != null) 'transformed_title': transformedTitle,
      if (episodeIdentifier != null) 'episode_identifier': episodeIdentifier,
    };
  }

  /// Get the display title - uses transformed title if available, otherwise falls back to name
  String get displayTitle => transformedTitle ?? name;

  /// Get coverage type as enum (for sorting)
  int get coveragePriority {
    switch (coverageType) {
      case 'completeSeries':
        return 0;
      case 'multiSeasonPack':
        return 1;
      case 'seasonPack':
        return 2;
      case 'singleEpisode':
        return 3;
      default:
        return 3; // Treat unknown as single episode
    }
  }
}
