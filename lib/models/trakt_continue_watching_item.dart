import 'stremio_addon.dart';

class TraktContinueWatchingItem {
  final StremioMeta meta;
  final String traktContentType;
  final double? progress;
  final int? season;
  final int? episode;
  final int? runtime;
  final List<int> playbackIds;

  /// When Trakt last recorded playback for this item (epoch ms), parsed from the
  /// playback endpoint's `paused_at`. Authoritative Up Next rows map
  /// `last_watched_at` into the same field. Used to order a merged movies+shows
  /// list by "last watched".
  final int? pausedAtMs;

  const TraktContinueWatchingItem({
    required this.meta,
    required this.traktContentType,
    this.progress,
    this.season,
    this.episode,
    this.runtime,
    this.playbackIds = const [],
    this.pausedAtMs,
  });

  String get id => meta.effectiveImdbId ?? meta.id;
  String get title => meta.name;
  String? get year => meta.year;
  String? get posterUrl => meta.poster;
  bool get isSeries => meta.type == 'series';
}
