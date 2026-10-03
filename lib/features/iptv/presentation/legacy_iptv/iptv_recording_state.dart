import 'dart:async';

class IptvRecordingState {
  /// playlist.id → catalog channel count for the rail; recomputed whenever
  /// the playlist set reloads. Sync, indexed DB reads — no scans, no network.
  Map<String, int> sourceCounts = const {};

  /// Upcoming scheduled recordings, for the rail's Scheduled badge.
  int scheduledCount = 0;

  /// Number shown beside the virtual Continue Watching destination in the
  /// Spotlight source rail. Loaded with the same store read that decides
  /// whether the destination exists.
  int continueWatchingCount = 0;

  /// Whether this platform can record at all (engine on Android 10+, the
  /// desktop capture elsewhere) — gates the stage's Record/REC affordances.
  bool pageCanRecord = false;

  Timer? sourceCountsDebounce;

  /// Live ANDROID engine captures by url (url → taskId), so the stage's
  /// Record button can read Stop for a channel that's being recorded — same
  /// contract the desktop side already has. Kept fresh by the focus-debounced
  /// query below plus optimistic updates on start/stop.
  final Map<String, String> androidRecordingsByUrl = {};

  Timer? androidRecStateDebounce;
}
