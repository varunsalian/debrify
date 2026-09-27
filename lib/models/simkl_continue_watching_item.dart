import 'stremio_addon.dart';

/// One Simkl "continue watching" entry: a paused movie, the paused episode of a
/// show, OR an "up next" entry (the next unwatched episode of a show you're
/// watching but haven't paused). Wraps a [StremioMeta] (for row rendering) plus
/// the resume detail the CW row needs. Parallel to TraktContinueWatchingItem;
/// deliberately not shared (Simkl stays independent of Trakt — see
/// the SimklService class documentation).
class SimklContinueWatchingItem {
  final StremioMeta meta;

  /// Paused progress, 0–100 (Simkl's scale). In (0,100) for a paused entry;
  /// NULL for an "up next" entry (the next episode hasn't been started, so
  /// there's no resume position and the card shows no progress bar).
  final double? progress;

  /// Season/episode — of the paused episode, or the next-to-watch episode for
  /// an up-next entry (null for movies).
  final int? season;
  final int? episode;

  /// Recency epoch ms for newest-first ordering: `paused_at` for a paused entry,
  /// `last_watched_at` for an up-next entry (null if unparseable/absent).
  final int? pausedAtMs;

  final bool isMovie;

  /// True when this is an "up next" series entry (no paused session — derived
  /// from the show's `next_to_watch`). Used to keep the explicit
  /// "Remove from Continue Watching" action off it (nothing to delete).
  final bool isUpNext;

  const SimklContinueWatchingItem({
    required this.meta,
    required this.progress,
    required this.season,
    required this.episode,
    required this.pausedAtMs,
    required this.isMovie,
    this.isUpNext = false,
  });

  String get id => meta.progressId ?? meta.id;
  bool get isSeries => !isMovie;
}
