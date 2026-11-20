import 'ledger_media.dart';

/// A saved resume point (`/v1/me/playback`).
class LedgerPlayback {
  const LedgerPlayback({
    required this.id,
    required this.item,
    required this.progress,
    this.updatedAt,
  });

  final String id;
  final LedgerMedia item;

  /// Percent watched, 0–100.
  final double progress;
  final DateTime? updatedAt;

  static LedgerPlayback? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = ledgerString(json['id']);
    final item = LedgerMedia.fromJson(json['item']);
    final progress = ledgerPercent(json['progress']);
    if (id == null || item == null || progress == null) return null;
    return LedgerPlayback(
      id: id,
      item: item,
      progress: progress,
      updatedAt: ledgerTime(json['updateTime']),
    );
  }
}

enum LedgerUpNextReason { resume, next, unknown }

/// One Continue Watching entry (`/v1/me/up-next`): a movie or episode to
/// resume, or a show's next unwatched episode.
class LedgerUpNextEntry {
  const LedgerUpNextEntry({
    required this.item,
    required this.reason,
    this.progress,
    this.playbackId,
    this.lastActivityAt,
    this.airedEpisodes,
    this.completedEpisodes,
  });

  final LedgerMedia item;
  final LedgerUpNextReason reason;
  final double? progress;
  final String? playbackId;
  final DateTime? lastActivityAt;
  final int? airedEpisodes;
  final int? completedEpisodes;

  static LedgerUpNextEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final item = LedgerMedia.fromJson(json['item']);
    if (item == null) return null;
    return LedgerUpNextEntry(
      item: item,
      reason: switch (json['reason']) {
        'UP_NEXT_REASON_RESUME' => LedgerUpNextReason.resume,
        'UP_NEXT_REASON_NEXT' => LedgerUpNextReason.next,
        _ => LedgerUpNextReason.unknown,
      },
      progress: ledgerPercent(json['progress']),
      playbackId: ledgerString(json['playbackId']),
      lastActivityAt: ledgerTime(json['lastActivityAt']),
      airedEpisodes: ledgerNonNegativeInt(json['aired']),
      completedEpisodes: ledgerNonNegativeInt(json['completed']),
    );
  }
}

/// A watched episode inside [LedgerWatchedShow].
class LedgerWatchedEpisode {
  const LedgerWatchedEpisode({
    required this.season,
    required this.episode,
    this.plays = 1,
    this.lastWatchedAt,
  });

  final int season;
  final int episode;
  final int plays;
  final DateTime? lastWatchedAt;
}

/// A watched movie or show (`/v1/me/watched`). Shows list their watched
/// episodes when requested with `includeEpisodes`.
class LedgerWatchedItem {
  const LedgerWatchedItem({
    required this.item,
    this.plays = 0,
    this.lastWatchedAt,
    this.episodeCount,
    this.episodes = const <LedgerWatchedEpisode>[],
  });

  final LedgerMedia item;
  final int plays;
  final DateTime? lastWatchedAt;
  final int? episodeCount;
  final List<LedgerWatchedEpisode> episodes;

  static LedgerWatchedItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final item = LedgerMedia.fromJson(json['item']);
    if (item == null) return null;
    final episodes = <LedgerWatchedEpisode>[];
    final seasons = json['seasons'];
    if (seasons is List) {
      for (final season in seasons.whereType<Map>()) {
        final seasonNumber = ledgerNonNegativeInt(season['number']);
        final list = season['episodes'];
        if (seasonNumber == null || list is! List) continue;
        for (final episode in list.whereType<Map>()) {
          final number = ledgerPositiveInt(episode['number']);
          if (number == null) continue;
          episodes.add(
            LedgerWatchedEpisode(
              season: seasonNumber,
              episode: number,
              plays: ledgerPositiveInt(episode['plays']) ?? 1,
              lastWatchedAt: ledgerTime(episode['lastWatchedAt']),
            ),
          );
        }
      }
    }
    return LedgerWatchedItem(
      item: item,
      plays: ledgerNonNegativeInt(json['plays']) ?? 0,
      lastWatchedAt: ledgerTime(json['lastWatchedAt']),
      episodeCount: ledgerNonNegativeInt(json['episodes']),
      episodes: List.unmodifiable(episodes),
    );
  }
}

/// One episode row of a show's progress (`/v1/me/progress/shows/{id}`).
class LedgerEpisodeProgress {
  const LedgerEpisodeProgress({
    required this.season,
    required this.episode,
    required this.completed,
    this.name,
    this.aired,
    this.plays = 0,
    this.lastWatchedAt,
    this.progress,
  });

  final int season;
  final int episode;
  final bool completed;
  final String? name;
  final String? aired;
  final int plays;
  final DateTime? lastWatchedAt;

  /// In-progress percent, null when there is no resume point.
  final double? progress;
}

class LedgerShowProgress {
  const LedgerShowProgress({
    required this.show,
    required this.episodes,
    this.airedEpisodes = 0,
    this.completedEpisodes = 0,
    this.lastWatchedAt,
  });

  final LedgerMedia show;
  final List<LedgerEpisodeProgress> episodes;
  final int airedEpisodes;
  final int completedEpisodes;
  final DateTime? lastWatchedAt;

  static LedgerShowProgress? fromJson(Object? json) {
    if (json is! Map) return null;
    final show = LedgerMedia.fromJson(json['show']);
    if (show == null) return null;
    final episodes = <LedgerEpisodeProgress>[];
    final seasons = json['seasons'];
    if (seasons is List) {
      for (final season in seasons.whereType<Map>()) {
        final seasonNumber = ledgerNonNegativeInt(season['number']);
        final list = season['episodes'];
        if (seasonNumber == null || list is! List) continue;
        for (final episode in list.whereType<Map>()) {
          final number = ledgerPositiveInt(episode['number']);
          if (number == null) continue;
          final progress = ledgerPercent(episode['progress']);
          episodes.add(
            LedgerEpisodeProgress(
              season: seasonNumber,
              episode: number,
              completed: episode['completed'] == true,
              name: ledgerString(episode['name']),
              aired: ledgerString(episode['aired']),
              plays: ledgerNonNegativeInt(episode['plays']) ?? 0,
              lastWatchedAt: ledgerTime(episode['lastWatchedAt']),
              progress: progress == null || progress <= 0 ? null : progress,
            ),
          );
        }
      }
    }
    return LedgerShowProgress(
      show: show,
      episodes: List.unmodifiable(episodes),
      airedEpisodes: ledgerNonNegativeInt(json['aired']) ?? 0,
      completedEpisodes: ledgerNonNegativeInt(json['completed']) ?? 0,
      lastWatchedAt: ledgerTime(json['lastWatchedAt']),
    );
  }
}

/// A watchlist row (`/v1/me/watchlist`).
class LedgerListedItem {
  const LedgerListedItem({required this.item, this.listedAt});

  final LedgerMedia item;
  final DateTime? listedAt;

  static LedgerListedItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final item = LedgerMedia.fromJson(json['item']);
    if (item == null) return null;
    return LedgerListedItem(item: item, listedAt: ledgerTime(json['listedAt']));
  }
}

/// A user's custom list (`/v1/me/lists`).
class LedgerUserList {
  const LedgerUserList({
    required this.id,
    required this.name,
    this.description,
    this.itemCount = 0,
  });

  final String id;
  final String name;
  final String? description;
  final int itemCount;

  static LedgerUserList? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = ledgerString(json['id']);
    final name = ledgerString(json['name']);
    if (id == null || name == null) return null;
    return LedgerUserList(
      id: id,
      name: name,
      description: ledgerString(json['description']),
      itemCount: ledgerNonNegativeInt(json['itemCount']) ?? 0,
    );
  }
}

/// The user's relationship to one title (`/v1/me/status`).
class LedgerItemStatus {
  const LedgerItemStatus({
    this.plays = 0,
    this.lastWatchedAt,
    this.playbackProgress,
    this.rating,
    this.watchlistedAt,
  });

  final int plays;
  final DateTime? lastWatchedAt;
  final double? playbackProgress;

  /// 1–10, null when unrated.
  final int? rating;
  final DateTime? watchlistedAt;

  bool get watched => plays > 0;
  bool get onWatchlist => watchlistedAt != null;

  static LedgerItemStatus fromJson(Object? json) {
    if (json is! Map) return const LedgerItemStatus();
    final playback = json['playback'];
    return LedgerItemStatus(
      plays: ledgerNonNegativeInt(json['plays']) ?? 0,
      lastWatchedAt: ledgerTime(json['lastWatchedAt']),
      playbackProgress: playback is Map
          ? ledgerPercent(playback['progress'])
          : null,
      rating: ledgerPositiveInt(json['rating']),
      watchlistedAt: ledgerTime(json['watchlistedAt']),
    );
  }
}

/// An upcoming episode (`/v1/me/calendar`).
class LedgerCalendarEntry {
  const LedgerCalendarEntry({required this.date, required this.item});

  /// YYYY-MM-DD, UTC.
  final String date;
  final LedgerMedia item;

  static LedgerCalendarEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final date = ledgerString(json['date']);
    final item = LedgerMedia.fromJson(json['item']);
    if (date == null || item == null) return null;
    return LedgerCalendarEntry(date: date, item: item);
  }
}

/// The result of a scrobble call.
class LedgerScrobbleResult {
  const LedgerScrobbleResult({this.watched = false});

  /// True when a STOP recorded a play.
  final bool watched;
}

/// The server-side Trakt/Simkl import link (`/v1/me/trackers`).
class LedgerLinkedTracker {
  const LedgerLinkedTracker({
    required this.provider,
    required this.displayName,
    required this.connected,
    this.remoteUsername,
    this.lastImportState,
    this.lastImportFinishedAt,
  });

  final String provider;
  final String displayName;
  final bool connected;
  final String? remoteUsername;
  final String? lastImportState;
  final DateTime? lastImportFinishedAt;

  static LedgerLinkedTracker? fromJson(Object? json) {
    if (json is! Map) return null;
    final provider = ledgerString(json['provider']);
    if (provider == null) return null;
    final lastImport = json['lastImport'];
    return LedgerLinkedTracker(
      provider: provider,
      displayName: ledgerString(json['displayName']) ?? provider,
      connected: json['connected'] == true,
      remoteUsername: ledgerString(json['remoteUsername']),
      lastImportState: lastImport is Map
          ? ledgerString(lastImport['state'])
          : null,
      lastImportFinishedAt: lastImport is Map
          ? ledgerTime(lastImport['finishTime'])
          : null,
    );
  }
}
