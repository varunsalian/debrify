import 'package:flutter/foundation.dart';

/// One title on a detail page: its IMDb id and `movie` / `series`.
typedef LedgerTitleKey = ({String imdbId, String contentType});

/// What the tracker holds for one title.
@immutable
class LedgerTitleStatus {
  const LedgerTitleStatus({
    this.planned = false,
    this.completed = false,
    this.dropped = false,
    this.started = false,
    this.rating,
  });

  /// On the watchlist.
  final bool planned;

  /// A movie with a play, or a show whose aired episodes all have one.
  final bool completed;
  final bool dropped;

  /// At least one play, completed or not.
  final bool started;

  /// 1–10, null when unrated.
  final int? rating;

  bool get tracked =>
      planned || completed || dropped || started || rating != null;

  /// The single word the detail page's button shows.
  String get label {
    if (dropped) return 'Dropped';
    if (completed) return 'Completed';
    if (planned) return 'Plan to Watch';
    if (started) return 'Watching';
    if (rating != null) return 'Rated';
    return 'Not tracked';
  }
}
