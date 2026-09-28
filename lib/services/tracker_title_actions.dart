import '../models/tracking_source.dart';

/// Data commands after any presentation-owned confirmation or selection.
enum TrackerTitleMutation {
  addToWatchlist,
  removeFromWatchlist,
  addToCollection,
  removeFromCollection,
  markWatched,
  markUnwatched,
  rate,
  removeRating,
  addToCustomList,
  moveToWatching,
  moveToOnHold,
  drop,
  restore,
  removeFromList,
}

abstract interface class TrackerTitleActions {
  Future<bool> mutate(
    TrackingSource tracker,
    TrackerTitleMutation mutation,
    String id,
    String type, {
    int? rating,
    String? listId,
    required bool Function() isCurrent,
  });

  Future<List<Map<String, dynamic>>> customLists({
    required bool Function() isCurrent,
  });

  /// Null provider means this device and every connected tracker.
  Future<List<String>> reset(
    String id,
    String title, {
    required bool isMovie,
    TrackingSource? provider,
    required bool Function() isCurrent,
  });
}
