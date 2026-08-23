import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/profiles/profile_policy.dart';
import '../utils/episode_progress_merge.dart';
import 'episode_tracker_snapshot_revision.dart';
import 'mdblist/mdblist_service.dart';
import 'profiles/profile_async_authorization.dart';
import 'simkl/simkl_service.dart';
import 'storage_service.dart';
import 'trakt/trakt_service.dart';

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
class _EpisodeSnapshotRefreshCoordinator {
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

/// Refreshes the replaceable, IMDb-keyed episode snapshots used by player
/// guides. Full history reads belong off the playback launch-critical path.
class EpisodeTrackerSnapshotService {
  const EpisodeTrackerSnapshotService._();

  static const Duration _refreshTtl = Duration(seconds: 30);
  static final _refreshCoordinator = _EpisodeSnapshotRefreshCoordinator();

  static String _refreshKey(
    String provider,
    String imdbId,
    ProfileAsyncAuthorization? authorization, {
    int? snapshotRevision,
  }) {
    final scope = authorization?.scope.cacheKey ?? 'legacy';
    final normalizedImdb = imdbId.trim().toLowerCase();
    final revision = snapshotRevision == null ? '' : ':$snapshotRevision';
    return '$scope:$provider$revision:$normalizedImdb';
  }

  static bool _snapshotRevisionIsCurrent({
    required String provider,
    required String imdbId,
    required int expectedRevision,
  }) =>
      EpisodeTrackerSnapshotRevision.identity(provider, imdbId) ==
      expectedRevision;

  static String _storeWriteKey(
    String provider,
    ProfileAsyncAuthorization? authorization,
  ) {
    final scope = authorization?.scope.cacheKey ?? 'legacy';
    return '$scope:$provider:store-write';
  }

  static Future<T> _runBound<T>(
    ProfileAsyncAuthorization? authorization,
    Future<T> Function() operation,
  ) {
    if (authorization == null) return operation();
    return authorization.runIfCurrent(operation);
  }

  static Map<String, double> _buildTraktSnapshot(
    Set<String> watched,
    Map<String, double> playback,
  ) {
    final snapshot = buildEpisodeTrackerSnapshot(
      watched: watched,
      playback: const {},
    );
    // Preserve the launch behavior this service replaced: an active Trakt
    // playback object represents the current rewatch and therefore overrides
    // older watched history, even at 1–5%. Taking max() here leaves a rewatched
    // episode stuck at 100% and prevents cross-device resume.
    for (final entry in playback.entries) {
      final match = RegExp(r'^(\d+)[_-](\d+)$').firstMatch(entry.key.trim());
      if (match == null || !entry.value.isFinite || entry.value <= 0) continue;
      final key = '${match.group(1)}_${match.group(2)}';
      snapshot[key] = entry.value.clamp(0.0, 100.0).toDouble();
    }
    return snapshot;
  }

  static Future<Map<String, double>?> _refreshTraktSnapshot({
    required String key,
    required String storeWriteKey,
    required bool force,
    Duration ttl = _refreshTtl,
    required Future<Set<String>?> Function() fetchWatched,
    required Future<Map<String, double>?> Function() fetchPlayback,
    required Future<bool> Function() isCurrent,
    required Future<void> Function(Map<String, double>) save,
  }) {
    return _refreshCoordinator.run(
      key: key,
      ttl: ttl,
      force: force,
      load: () async {
        final results = await Future.wait<Object?>([
          fetchWatched(),
          fetchPlayback(),
        ]);
        final watched = results[0] as Set<String>?;
        final playback = results[1] as Map<String, double>?;
        // Either endpoint failing makes the combined snapshot incomplete.
        // Do not save; the profile-scoped last-good value remains authoritative.
        if (watched == null || playback == null) return null;
        final snapshot = _buildTraktSnapshot(watched, playback);
        if (!await isCurrent()) return null;
        // StorageService persists all shows for a provider in one JSON object.
        // Serialize provider-wide writes so two different IMDb refreshes cannot
        // both read the old object and make one another's update disappear.
        await _refreshCoordinator.serialize(
          storeWriteKey,
          () => save(snapshot),
        );
        if (!await isCurrent()) return null;
        return snapshot;
      },
    );
  }

  static Future<Map<String, double>?> refreshTrakt(
    String imdbId, {
    bool force = false,
  }) async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      final trakt = TraktService.instance;
      final storeWriteKey = _storeWriteKey('trakt', authorization);
      final accessToken = await _runBound(
        authorization,
        StorageService.getTraktAccessToken,
      );
      if (accessToken == null || accessToken.isEmpty) {
        // No credential is an authoritative disconnect, not a transient API
        // failure. Clear the provider snapshot so old ticks cannot survive a
        // logout (Trakt auth cleanup intentionally does not touch this store).
        await _refreshCoordinator.serialize(
          storeWriteKey,
          () => _runBound(
            authorization,
            () => StorageService.saveEpisodeTraktProgress(
              imdbId: imdbId,
              percents: const {},
            ),
          ),
        );
        return const {};
      }
      final authenticated = await _runBound(
        authorization,
        trakt.isAuthenticated,
      );
      if (!authenticated) {
        // Authentication can be temporarily unknown while an expired token
        // refresh is failing. Retain stored last-good state, but never serve a
        // process cache hit until authentication succeeds again.
        return null;
      }

      final snapshotRevision = EpisodeTrackerSnapshotRevision.identity(
        'trakt',
        imdbId,
      );
      final key = _refreshKey(
        'trakt',
        imdbId,
        authorization,
        snapshotRevision: snapshotRevision,
      );

      return _refreshTraktSnapshot(
        key: key,
        storeWriteKey: storeWriteKey,
        force: force,
        fetchWatched: () => _runBound(
          authorization,
          () => trakt.fetchWatchedShowEpisodesOrNull(imdbId),
        ),
        fetchPlayback: () => _runBound(
          authorization,
          () => trakt.fetchEpisodePlaybackProgressOrNull(imdbId),
        ),
        isCurrent: () async => _snapshotRevisionIsCurrent(
          provider: 'trakt',
          imdbId: imdbId,
          expectedRevision: snapshotRevision,
        ),
        save: (snapshot) => _runBound(
          authorization,
          () => StorageService.saveEpisodeTraktProgress(
            imdbId: imdbId,
            percents: snapshot,
          ),
        ),
      );
    } catch (error) {
      // Retain the last successful profile-scoped snapshot on every transient,
      // parse, partial-response, or profile-session failure.
      debugPrint('EpisodeTrackerSnapshot: Trakt refresh failed: $error');
      return null;
    }
  }

  @visibleForTesting
  static Map<String, double> debugBuildTraktSnapshot({
    required Set<String> watched,
    required Map<String, double> playback,
  }) => _buildTraktSnapshot(watched, playback);

  /// Behavioral seam for testing failure retention, TTL, force, coalescing,
  /// and scope isolation without real tracker credentials or network traffic.
  @visibleForTesting
  static Future<Map<String, double>?> debugRefreshTrakt({
    required String scopeKey,
    required String imdbId,
    required Future<Set<String>?> Function() fetchWatched,
    required Future<Map<String, double>?> Function() fetchPlayback,
    required Future<void> Function(Map<String, double>) save,
    bool connected = true,
    bool authenticated = true,
    bool force = false,
    Duration ttl = const Duration(seconds: 30),
  }) async {
    final revision = EpisodeTrackerSnapshotRevision.identity('trakt', imdbId);
    final refreshKey =
        'test:$scopeKey:trakt:$revision:${imdbId.trim().toLowerCase()}';
    final storeWriteKey = 'test:$scopeKey:trakt:store-write';
    if (!connected) {
      _refreshCoordinator.invalidate(refreshKey);
      await _refreshCoordinator.serialize(storeWriteKey, () => save(const {}));
      return const {};
    }
    if (!authenticated) return null;
    return _refreshTraktSnapshot(
      key: refreshKey,
      storeWriteKey: storeWriteKey,
      force: force,
      ttl: ttl,
      fetchWatched: fetchWatched,
      fetchPlayback: fetchPlayback,
      isCurrent: () async =>
          revision == EpisodeTrackerSnapshotRevision.identity('trakt', imdbId),
      save: save,
    );
  }

  @visibleForTesting
  static Future<T> debugSerializeSnapshotOperation<T>({
    required String scopeKey,
    required String provider,
    required String imdbId,
    required Future<T> Function() operation,
  }) {
    return _refreshCoordinator.serialize(
      'test:$scopeKey:$provider:${imdbId.trim().toLowerCase()}',
      operation,
    );
  }

  @visibleForTesting
  static void debugResetRefreshState() {
    _refreshCoordinator.clear();
    EpisodeTrackerSnapshotRevision.resetForTesting();
  }

  @visibleForTesting
  static void debugInvalidateTitle(String provider, String imdbId) {
    EpisodeTrackerSnapshotRevision.invalidateTitle(provider, imdbId);
  }

  static Future<Map<String, double>?> refreshSimkl(
    String imdbId, {
    bool force = false,
  }) async {
    ProfileAsyncAuthorization? authorization;
    String? storeWriteKey;
    int? snapshotRevision;
    var authorizationCaptured = false;
    try {
      authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      authorizationCaptured = true;
      final simkl = SimklService.instance;
      storeWriteKey = _storeWriteKey('simkl', authorization);
      final authenticated = await _runBound(
        authorization,
        simkl.isAuthenticated,
      );
      if (!authenticated) {
        await _refreshCoordinator.serialize(
          storeWriteKey,
          () => _runBound(
            authorization,
            () => StorageService.saveEpisodeSimklProgress(
              imdbId: imdbId,
              percents: const {},
            ),
          ),
        );
        return const {};
      }
      final refreshRevision = EpisodeTrackerSnapshotRevision.identity(
        'simkl',
        imdbId,
      );
      snapshotRevision = refreshRevision;
      final key = _refreshKey(
        'simkl',
        imdbId,
        authorization,
        snapshotRevision: refreshRevision,
      );

      return _refreshCoordinator.run(
        key: key,
        ttl: _refreshTtl,
        force: force,
        load: () async {
          final results = await Future.wait<Object?>([
            _runBound(
              authorization,
              () => simkl.fetchWatchedShowEpisodes(imdbId),
            ),
            _runBound(
              authorization,
              () => simkl.fetchEpisodePlaybackProgress(imdbId),
            ),
          ]);
          final snapshot = buildEpisodeTrackerSnapshot(
            watched: results[0] as Set<String>,
            playback: results[1] as Map<String, double>,
          );
          final current = _snapshotRevisionIsCurrent(
            provider: 'simkl',
            imdbId: imdbId,
            expectedRevision: refreshRevision,
          );
          if (!current) return null;
          await _refreshCoordinator.serialize(
            storeWriteKey!,
            () => _runBound(
              authorization,
              () => StorageService.saveEpisodeSimklProgress(
                imdbId: imdbId,
                percents: snapshot,
              ),
            ),
          );
          final stillCurrent = _snapshotRevisionIsCurrent(
            provider: 'simkl',
            imdbId: imdbId,
            expectedRevision: refreshRevision,
          );
          if (!stillCurrent) return null;
          return snapshot;
        },
      );
    } catch (error) {
      // Match the existing Simkl contract: a failed launch refresh must not
      // leave stale remote completion ticks behind.
      final revisionStillCurrent =
          snapshotRevision == null ||
          _snapshotRevisionIsCurrent(
            provider: 'simkl',
            imdbId: imdbId,
            expectedRevision: snapshotRevision,
          );
      if (authorizationCaptured && revisionStillCurrent) {
        try {
          await _refreshCoordinator.serialize(
            storeWriteKey!,
            () => _runBound(
              authorization,
              () => StorageService.saveEpisodeSimklProgress(
                imdbId: imdbId,
                percents: const {},
              ),
            ),
          );
        } catch (_) {
          // A changed/unauthorized profile must not receive the failed job's
          // cleanup publication either.
        }
      }
      debugPrint('EpisodeTrackerSnapshot: Simkl refresh failed: $error');
      return null;
    }
  }

  /// Fast launch seed: refresh active playback while retaining only completed
  /// entries from the last complete MDBList history snapshot. The slower show
  /// history request is performed later by [refreshMdblistHistory].
  static Future<Map<String, double>?> seedMdblistPlayback(
    String imdbId, {
    bool force = false,
  }) async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      final service = MdblistService.instance;
      final enabled = await Future.wait<bool>([
        _runBound(authorization, StorageService.getMdblistSyncCatalogItems),
        _runBound(authorization, service.isAuthenticated),
      ]);
      final operationKey = _refreshKey(
        'mdblist-operation',
        imdbId,
        authorization,
      );
      final storeWriteKey = _storeWriteKey('mdblist', authorization);
      if (!enabled[0] || !enabled[1]) {
        await _refreshCoordinator.serialize(
          operationKey,
          () => _refreshCoordinator.serialize(
            storeWriteKey,
            () => _runBound(
              authorization,
              () => StorageService.saveEpisodeMdblistProgress(
                imdbId: imdbId,
                percents: const {},
              ),
            ),
          ),
        );
        return const {};
      }
      final snapshotRevision = EpisodeTrackerSnapshotRevision.identity(
        'mdblist',
        imdbId,
      );
      final key = _refreshKey(
        'mdblist-playback',
        imdbId,
        authorization,
        snapshotRevision: snapshotRevision,
      );

      // Playback remains fresh on every launch (zero TTL), while concurrent
      // callers share one request. Its read/modify/write is serialized with
      // full-history replacement via [operationKey].
      return _refreshCoordinator.run(
        key: key,
        ttl: Duration.zero,
        force: force,
        load: () => _refreshCoordinator.serialize(operationKey, () async {
          final result = await _runBound(
            authorization,
            service.fetchPlaybackSessions,
          );
          if (!result.isSuccess) return null;
          final previous = await _runBound(
            authorization,
            () => StorageService.getEpisodeMdblistProgress(imdbId: imdbId),
          );
          final snapshot = <String, double>{
            for (final entry in previous.entries)
              if (entry.value >= 95) entry.key: entry.value,
          };
          for (final session in result.data!) {
            if (!session.isEpisode ||
                session.imdbId?.toLowerCase() != imdbId.toLowerCase() ||
                session.season == null ||
                session.episode == null ||
                !session.isResumable) {
              continue;
            }
            snapshot['${session.season}_${session.episode}'] = session.progress;
          }
          final current = _snapshotRevisionIsCurrent(
            provider: 'mdblist',
            imdbId: imdbId,
            expectedRevision: snapshotRevision,
          );
          if (!current) return null;
          await _refreshCoordinator.serialize(
            storeWriteKey,
            () => _runBound(
              authorization,
              () => StorageService.saveEpisodeMdblistProgress(
                imdbId: imdbId,
                percents: snapshot,
              ),
            ),
          );
          final stillCurrent = _snapshotRevisionIsCurrent(
            provider: 'mdblist',
            imdbId: imdbId,
            expectedRevision: snapshotRevision,
          );
          if (!stillCurrent) return null;
          return snapshot;
        }),
      );
    } catch (error) {
      debugPrint(
        'EpisodeTrackerSnapshot: MDBList playback seed failed: $error',
      );
      return null;
    }
  }

  /// Full guide refresh. Only a complete show-history response replaces the
  /// stored truth; partial/truncated reads retain the last complete snapshot.
  static Future<Map<String, double>?> refreshMdblistHistory(
    String imdbId, {
    bool force = false,
  }) async {
    try {
      final authorization = await ProfileAsyncAuthorization.capture(
        ProfileFeature.trackersAndDiscovery,
      );
      final service = MdblistService.instance;
      final enabled = await Future.wait<bool>([
        _runBound(authorization, StorageService.getMdblistSyncCatalogItems),
        _runBound(authorization, service.isAuthenticated),
      ]);
      final operationKey = _refreshKey(
        'mdblist-operation',
        imdbId,
        authorization,
      );
      final storeWriteKey = _storeWriteKey('mdblist', authorization);
      if (!enabled[0] || !enabled[1]) {
        await _refreshCoordinator.serialize(
          operationKey,
          () => _refreshCoordinator.serialize(
            storeWriteKey,
            () => _runBound(
              authorization,
              () => StorageService.saveEpisodeMdblistProgress(
                imdbId: imdbId,
                percents: const {},
              ),
            ),
          ),
        );
        return const {};
      }
      final snapshotRevision = EpisodeTrackerSnapshotRevision.identity(
        'mdblist',
        imdbId,
      );
      final key = _refreshKey(
        'mdblist-history',
        imdbId,
        authorization,
        snapshotRevision: snapshotRevision,
      );

      return _refreshCoordinator.run(
        key: key,
        ttl: _refreshTtl,
        force: force,
        load: () => _refreshCoordinator.serialize(operationKey, () async {
          final result = await _runBound(
            authorization,
            () => service.fetchShowEpisodeProgress(imdbId),
          );
          if (!result.isComplete) return null;
          final snapshot = buildEpisodeTrackerSnapshot(
            watched: const {},
            playback: result.data!,
          );
          final current = _snapshotRevisionIsCurrent(
            provider: 'mdblist',
            imdbId: imdbId,
            expectedRevision: snapshotRevision,
          );
          if (!current) return null;
          await _refreshCoordinator.serialize(
            storeWriteKey,
            () => _runBound(
              authorization,
              () => StorageService.saveEpisodeMdblistProgress(
                imdbId: imdbId,
                percents: snapshot,
              ),
            ),
          );
          final stillCurrent = _snapshotRevisionIsCurrent(
            provider: 'mdblist',
            imdbId: imdbId,
            expectedRevision: snapshotRevision,
          );
          if (!stillCurrent) return null;
          return snapshot;
        }),
      );
    } catch (error) {
      debugPrint(
        'EpisodeTrackerSnapshot: MDBList history refresh failed: $error',
      );
      return null;
    }
  }
}
