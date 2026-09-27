import 'advanced_search_selection.dart';
import '../services/mdblist/mdblist_models.dart';

class MdblistContinueWatchingItem {
  final AdvancedSearchSelection selection;
  final int? playbackId;
  final bool paused;
  final DateTime? updatedAt;
  final MdblistScrobbleTarget? clearTarget;

  const MdblistContinueWatchingItem({
    required this.selection,
    required this.paused,
    this.playbackId,
    this.updatedAt,
    this.clearTarget,
  });
}

class MdblistContinueWatchingSnapshot {
  final List<MdblistContinueWatchingItem> movies;
  final List<MdblistContinueWatchingItem> shows;

  const MdblistContinueWatchingSnapshot({
    this.movies = const [],
    this.shows = const [],
  });
}
