enum MdblistResultKind {
  success,
  partial,
  disabled,
  unauthenticated,
  denied,
  notFound,
  conflict,
  rateLimited,
  transientFailure,
  malformedResponse,
}

class MdblistResult<T> {
  final MdblistResultKind kind;
  final T? data;
  final int? statusCode;
  final Duration? retryAfter;
  final Map<String, String>? headers;

  const MdblistResult._(
    this.kind, {
    this.data,
    this.statusCode,
    this.retryAfter,
    this.headers,
  });

  const MdblistResult.success(
    T data, {
    int? statusCode,
    Map<String, String>? headers,
  }) : this._(
         MdblistResultKind.success,
         data: data,
         statusCode: statusCode,
         headers: headers,
       );

  const MdblistResult.partial(
    T data, {
    int? statusCode,
    Map<String, String>? headers,
  }) : this._(
         MdblistResultKind.partial,
         data: data,
         statusCode: statusCode,
         headers: headers,
       );

  const MdblistResult.failure(
    MdblistResultKind kind, {
    int? statusCode,
    Duration? retryAfter,
    Map<String, String>? headers,
  }) : this._(
         kind,
         statusCode: statusCode,
         retryAfter: retryAfter,
         headers: headers,
       );

  bool get isSuccess => kind == MdblistResultKind.success;
  bool get isUsable => isSuccess || kind == MdblistResultKind.partial;
  bool get isComplete => isSuccess;
}

class MdblistMediaIds {
  final String? imdb;
  final int? tmdb;
  final int? tvdb;
  final String? mdblist;

  const MdblistMediaIds({this.imdb, this.tmdb, this.tvdb, this.mdblist});

  factory MdblistMediaIds.fromJson(Map<String, dynamic>? json) {
    int? integer(Object? value) => value is num
        ? value.toInt()
        : value is String
        ? int.tryParse(value)
        : null;

    return MdblistMediaIds(
      imdb: json?['imdb']?.toString(),
      tmdb: integer(json?['tmdb']),
      tvdb: integer(json?['tvdb']),
      mdblist: json?['mdblist']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if (imdb != null && imdb!.isNotEmpty) 'imdb': imdb,
    if (tmdb != null) 'tmdb': tmdb,
    if (tvdb != null) 'tvdb': tvdb,
    if (mdblist != null && mdblist!.isNotEmpty) 'mdblist': mdblist,
  };

  bool get isEmpty => toJson().isEmpty;
}

class MdblistScrobbleTarget {
  final MdblistMediaIds ids;
  final int? season;
  final int? episode;

  const MdblistScrobbleTarget.movie(this.ids) : season = null, episode = null;

  const MdblistScrobbleTarget.episode(
    this.ids, {
    required int this.season,
    required int this.episode,
  });

  bool get isEpisode => season != null || episode != null;
  bool get isValid =>
      !ids.isEmpty && (!isEpisode || (season != null && episode != null));

  Map<String, dynamic>? payload(double progress) {
    if (!isValid) return null;
    // MDBList rejects scrobble progress with more than two decimal places.
    // Keep this guard at the payload boundary so direct service callers are as
    // safe as the higher-level playback session.
    final normalizedProgress = double.parse(
      progress.clamp(0, 100).toStringAsFixed(2),
    );
    return {
      if (!isEpisode) 'movie': {'ids': ids.toJson()},
      if (isEpisode)
        'show': {'ids': ids.toJson(), 'season': season, 'episode': episode},
      'progress': normalizedProgress,
    };
  }
}

double? mdblistDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

DateTime? mdblistDateTime(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

class MdblistTitleStatus {
  final Object id;
  final bool watched;
  final int? rating;
  final bool collected;
  final bool inWatchlist;
  final bool? inProgress;
  final bool? completed;

  /// Null means the dropped snapshot could not be read; never treat that as a
  /// confirmed active/not-dropped state.
  final bool? dropped;
  final int? watchedEpisodeCount;
  final int? totalEpisodesAired;

  const MdblistTitleStatus({
    required this.id,
    this.watched = false,
    this.rating,
    this.collected = false,
    this.inWatchlist = false,
    this.inProgress,
    this.completed,
    this.dropped,
    this.watchedEpisodeCount,
    this.totalEpisodesAired,
  });

  factory MdblistTitleStatus.fromJson(Map<String, dynamic> json) =>
      MdblistTitleStatus(
        id: json['id'] ?? '',
        watched: json['watched'] == true,
        rating: (json['rating'] as num?)?.toInt(),
        collected: json['collected'] == true,
        inWatchlist: json['watchlist'] == true,
        inProgress: json['inprogress'] as bool?,
        completed: json['completed'] as bool?,
        dropped: json.containsKey('dropped') ? json['dropped'] == true : null,
        watchedEpisodeCount: (json['watched_episode_count'] as num?)?.toInt(),
        totalEpisodesAired: (json['total_episodes_aired'] as num?)?.toInt(),
      );

  MdblistTitleStatus copyWith({bool? dropped}) => MdblistTitleStatus(
    id: id,
    watched: watched,
    rating: rating,
    collected: collected,
    inWatchlist: inWatchlist,
    inProgress: inProgress,
    completed: completed,
    dropped: dropped,
    watchedEpisodeCount: watchedEpisodeCount,
    totalEpisodesAired: totalEpisodesAired,
  );
}

class MdblistPlaybackSession {
  final int id;
  final double progress;
  final DateTime? pausedAt;
  final DateTime? updatedAt;
  final int runtimeMinutes;
  final bool isEpisode;
  final String? imdbId;
  final int? season;
  final int? episode;
  final Map<String, dynamic> raw;

  const MdblistPlaybackSession({
    required this.id,
    required this.progress,
    required this.isEpisode,
    required this.raw,
    this.pausedAt,
    this.updatedAt,
    this.runtimeMinutes = 0,
    this.imdbId,
    this.season,
    this.episode,
  });

  bool get isResumable => progress > 0 && progress < 80;

  factory MdblistPlaybackSession.fromJson(Map<String, dynamic> json) {
    final episodeJson = json['episode'] is Map<String, dynamic>
        ? json['episode'] as Map<String, dynamic>
        : null;
    final showJson = json['show'] is Map<String, dynamic>
        ? json['show'] as Map<String, dynamic>
        : null;
    final movieJson = json['movie'] is Map<String, dynamic>
        ? json['movie'] as Map<String, dynamic>
        : null;
    String? imdbFrom(Map<String, dynamic>? value) {
      final ids = value?['ids'];
      return ids is Map
          ? ids['imdb']?.toString()
          : value?['imdb_id']?.toString();
    }

    int? integer(Object? value) => value is num
        ? value.toInt()
        : value is String
        ? int.tryParse(value)
        : null;
    final isEpisode = json['type'] == 'episode' || episodeJson != null;
    return MdblistPlaybackSession(
      id: integer(json['id']) ?? -1,
      progress: mdblistDouble(json['progress']) ?? 0,
      pausedAt: mdblistDateTime(json['paused_at']),
      updatedAt: mdblistDateTime(json['updated_at']),
      runtimeMinutes: integer(json['runtime']) ?? 0,
      isEpisode: isEpisode,
      imdbId: isEpisode ? imdbFrom(showJson) : imdbFrom(movieJson),
      season: integer(episodeJson?['season'] ?? episodeJson?['season_number']),
      episode: integer(episodeJson?['number'] ?? episodeJson?['episode']),
      raw: json,
    );
  }
}
