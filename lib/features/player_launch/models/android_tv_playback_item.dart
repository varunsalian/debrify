class AndroidTvPlaybackItem {
  final String id;
  final String title;
  final String url;
  final Map<String, String>? httpHeaders;
  final String? hdVideoUrl;
  final String? audioUrl;
  final int index;
  final int? season;
  final int? episode;
  final String? artwork;
  final String? description;
  final int? sizeBytes;
  final int resumePositionMs;
  final int durationMs;
  final int updatedAt;
  final String? resumeId;
  final String? provider;
  // Cross-device progress for this episode (0-100), or null. The legacy field
  // name is retained for the Kotlin payload, but the value is the furthest of
  // Trakt, Simkl, and MDBList.
  final double? traktProgressPercent;
  final bool watched;
  final bool allowLocalProgressDisplay;

  const AndroidTvPlaybackItem({
    required this.id,
    required this.title,
    required this.url,
    this.httpHeaders,
    this.hdVideoUrl,
    this.audioUrl,
    required this.index,
    required this.season,
    required this.episode,
    required this.artwork,
    required this.description,
    required this.sizeBytes,
    required this.resumePositionMs,
    required this.durationMs,
    required this.updatedAt,
    required this.resumeId,
    required this.provider,
    this.traktProgressPercent,
    this.watched = false,
    this.allowLocalProgressDisplay = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'httpHeaders': httpHeaders ?? const <String, String>{},
      if (hdVideoUrl != null) 'hdVideoUrl': hdVideoUrl,
      if (audioUrl != null) 'audioUrl': audioUrl,
      'index': index,
      'season': season,
      'episode': episode,
      'artwork': artwork,
      'description': description,
      'sizeBytes': sizeBytes,
      'resumePositionMs': resumePositionMs,
      'durationMs': durationMs,
      'updatedAt': updatedAt,
      'resumeId': resumeId,
      'provider': provider,
      if (traktProgressPercent != null) 'traktProgressPercent': traktProgressPercent,
      'watched': watched,
      'allowLocalProgressDisplay': allowLocalProgressDisplay,
    };
  }
}

class AndroidTvSeriesSeason {
  final int seasonNumber;
  final List<AndroidTvSeriesEpisode> episodes;

  const AndroidTvSeriesSeason({
    required this.seasonNumber,
    required this.episodes,
  });

  Map<String, dynamic> toMap() {
    return {
      'seasonNumber': seasonNumber,
      'episodes': episodes.map((e) => e.toMap()).toList(),
    };
  }
}

class AndroidTvCollectionGroup {
  final String name;
  final List<int> fileIndices;

  const AndroidTvCollectionGroup({
    required this.name,
    required this.fileIndices,
  });

  Map<String, dynamic> toMap() {
    return {'name': name, 'fileIndices': fileIndices};
  }
}

class AndroidTvSeriesEpisode {
  final String title;
  final int? season;
  final int? episode;
  final String? description;
  final String? artwork;

  const AndroidTvSeriesEpisode({
    required this.title,
    required this.season,
    required this.episode,
    required this.description,
    required this.artwork,
  });

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'season': season,
      'episode': episode,
      'description': description,
      'artwork': artwork,
    };
  }
}
