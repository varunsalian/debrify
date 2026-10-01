import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter/foundation.dart';

final class LocalCompletionStorage {
  const LocalCompletionStorage._();

  /// Local movie, episode, and derived-series completion invalidation.
  static final ValueNotifier<int> localCompletionRevision = ValueNotifier(0);
  static const String localSeriesCompletionStateKey = 'local_series_completion_v1';
  static const String localSeriesCalendarCheckedAtKey = 'local_series_completion_calendar_checked_at_v1';
  static const String localSeriesCalendarAttemptedAtKey = 'local_series_completion_calendar_attempted_at_v1';
  static const String _movieCompletionThresholdKey = 'movie_completion_threshold';
  static const String _episodeCompletionThresholdKey = 'episode_completion_threshold';

  /// Completion thresholds selectable in Settings → Playback. A lower bound
  /// avoids treating a brief accidental play as watched; 100% lets users
  /// require playback to reach the end.
  static const List<int> localCompletionThresholdOptions = <int>[
    50,
    60,
    70,
    75,
    80,
    85,
    90,
    95,
    100,
  ];
  static const int defaultLocalCompletionThreshold = 80;

  static int _normalizeLocalCompletionThreshold(int value) {
    return localCompletionThresholdOptions.contains(value) ? value : defaultLocalCompletionThreshold;
  }

  /// Percentage of a movie that must be watched before the local player marks
  /// it complete. Tracker-backed sessions retain Trakt/Simkl's own semantics.
  static Future<int> getMovieCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_movieCompletionThresholdKey) ?? defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setMovieCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _movieCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }

  /// Percentage of an episode that must be watched before the local player
  /// marks it complete. Kept separate from movies because users commonly want
  /// a different rule for episode credits.
  static Future<int> getEpisodeCompletionThreshold() async {
    final prefs = await ProfilePreferences.instance();
    return _normalizeLocalCompletionThreshold(
      prefs.getInt(_episodeCompletionThresholdKey) ?? defaultLocalCompletionThreshold,
    );
  }

  static Future<void> setEpisodeCompletionThreshold(int value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(
      _episodeCompletionThresholdKey,
      _normalizeLocalCompletionThreshold(value),
    );
  }
}
