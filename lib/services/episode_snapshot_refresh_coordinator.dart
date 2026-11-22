import 'dart:async';

// Moved unchanged from episode_tracker_snapshot_service.dart.

class _EpisodeSnapshotCacheEntry {
  final DateTime expiresAt;
  final Map<String, double> value;

  const _EpisodeSnapshotCacheEntry({
    required this.expiresAt,
    required this.value,
  });
}

class _EpisodeSnapshotFlight {
  final Future<Map<String, double>?> future;
  final bool forced;

  const _EpisodeSnapshotFlight(this.future, {required this.forced});
}

/// Small process cache for guide refreshes. Keys include the complete profile
/// scope identity, provider, operation, and IMDb id; a result warmed by one
/// profile/session can therefore never be returned to another.
class EpisodeSnapshotRefreshCoordinator {
  static const int _maxEntries = 128;
  final Map<String, _EpisodeSnapshotCacheEntry> _cache = {};
  final Map<String, _EpisodeSnapshotFlight> _inFlight = {};
  final Map<String, Future<Map<String, double>?>> _queuedForced = {};
  final Map<String, Future<void>> _serialTails = {};

  Future<Map<String, double>?> run({
    required String key,
    required Duration ttl,
    required bool force,
    required Future<Map<String, double>?> Function() load,
  }) {
    final queued = _queuedForced[key];
    if (queued != null) return queued;

    final active = _inFlight[key];
    if (active != null) {
      if (!force || active.forced) return active.future;

      // A forced refresh represents a post-mutation freshness boundary. If a
      // normal refresh was already running before that mutation, joining it
      // could publish stale data. Queue exactly one forced follow-up instead.
      late final Future<Map<String, double>?> followUp;
      followUp = () async {
        try {
          await active.future;
        } catch (_) {
          // The forced attempt is still required after a failed prior read.
        }
        try {
          return await _start(key: key, ttl: ttl, forced: true, load: load);
        } finally {
          if (identical(_queuedForced[key], followUp)) {
            _queuedForced.remove(key);
          }
        }
      }();
      _queuedForced[key] = followUp;
      return followUp;
    }

    final now = DateTime.now();
    _prune(now);
    final cached = _cache[key];
    if (!force && cached != null && now.isBefore(cached.expiresAt)) {
      return Future<Map<String, double>?>.value(cached.value);
    }
    return _start(key: key, ttl: ttl, forced: force, load: load);
  }

  Future<Map<String, double>?> _start({
    required String key,
    required Duration ttl,
    required bool forced,
    required Future<Map<String, double>?> Function() load,
  }) {
    late final Future<Map<String, double>?> future;
    future = () async {
      try {
        final loaded = await load();
        if (loaded == null) return null;
        final stable = Map<String, double>.unmodifiable(loaded);
        if (ttl > Duration.zero) {
          _cache[key] = _EpisodeSnapshotCacheEntry(
            expiresAt: DateTime.now().add(ttl),
            value: stable,
          );
          _trimToLimit();
        }
        return stable;
      } finally {
        if (identical(_inFlight[key]?.future, future)) {
          _inFlight.remove(key);
        }
      }
    }();
    _inFlight[key] = _EpisodeSnapshotFlight(future, forced: forced);
    return future;
  }

  void invalidate(String key) {
    _cache.remove(key);
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
    _queuedForced.clear();
    _serialTails.clear();
  }

  /// Run operations that replace the same persisted snapshot in invocation
  /// order. MDBList's playback seed is read/modify/write while full history is
  /// replace-all; serializing the whole operations prevents a slow seed from
  /// overwriting a newer history refresh with state it read beforehand.
  Future<T> serialize<T>(String key, Future<T> Function() operation) {
    final previous = _serialTails[key] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = release.future;
    _serialTails[key] = tail;

    return () async {
      await previous;
      try {
        return await operation();
      } finally {
        release.complete();
        if (identical(_serialTails[key], tail)) {
          _serialTails.remove(key);
        }
      }
    }();
  }

  void _prune(DateTime now) {
    _cache.removeWhere((_, entry) => !now.isBefore(entry.expiresAt));
  }

  void _trimToLimit() {
    while (_cache.length > _maxEntries) {
      String? oldestKey;
      DateTime? oldestExpiry;
      for (final entry in _cache.entries) {
        if (oldestExpiry == null ||
            entry.value.expiresAt.isBefore(oldestExpiry)) {
          oldestKey = entry.key;
          oldestExpiry = entry.value.expiresAt;
        }
      }
      if (oldestKey == null) return;
      _cache.remove(oldestKey);
    }
  }
}
