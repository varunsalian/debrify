import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/media_server.dart';
import '../models/media_server_watch_state.dart';
import '../models/profiles/profile_policy.dart';
import '../models/torrent.dart';
import 'local_playback_resume_resolver.dart';
import 'media_server_client.dart';
import 'media_server_service.dart';
import 'profiles/profile_async_authorization.dart';
import 'profiles/profile_preferences.dart';
import 'storage_service.dart';

/// Playback-driven sync, not a library crawler or a persistent retry queue.
class MediaServerWatchSync {
  static const preferenceKey = 'media_server_watch_sync_enabled_v1';
  @visibleForTesting
  static MediaServerClient Function() clientFactory = () =>
      MediaServerClient(timeout: const Duration(seconds: 5));

  static Future<bool> enabled() async =>
      (await ProfilePreferences.instance()).getBool(preferenceKey) ?? false;

  static Future<void> setEnabled(bool value) async {
    final capability = await ProfileAsyncAuthorization.capture(
      ProfileFeature.cloud,
    );
    if (capability == null) throw StateError('An active profile is required');
    await capability.runIfCurrent(() async {
      await (await ProfilePreferences.instance()).setBool(preferenceKey, value);
    });
  }

  /// Local reads happen AFTER the network response: a bookmark written while
  /// the request was in flight must not be overwritten by its older snapshot.
  static Future<void> importState(
    MediaServerWatchTarget target,
    Torrent source,
    MediaServerWatchState remote, {
    String? contentTitle,
  }) => target.capability.runIfCurrent(() async {
    final title = contentTitle ?? target.title;
    await target.authorize();
    if (!await enabled()) return;
    final local = target.isMovie
        ? await LocalPlaybackResumeResolver.movie(
            resumeId: source.displayTitle,
            imdbId: target.contentId,
            policy: PlaybackResumePolicy.catalogCanonical,
          )
        : await LocalPlaybackResumeResolver.episode(
            seriesTitle: title,
            season: target.season!,
            episode: target.episode!,
            imdbId: target.contentId,
            policy: PlaybackResumePolicy.catalogCanonical,
          );
    final played = target.isMovie
        ? await StorageService.isMovieFinished(target.contentId)
        : await StorageService.isEpisodeFinished(
            seriesTitle: title,
            season: target.season!,
            episode: target.episode!,
            imdbId: target.contentId,
          );
    if (!remote.shouldImport(
      localUpdatedAtMs: (local?['updatedAt'] as num?)?.toInt(),
      localPlayed: played,
    )) {
      return;
    }
    await target.authorize();
    if (remote.played && !remote.hasPartialBookmark) {
      if (target.isMovie) {
        await StorageService.markMovieAsFinished(target.contentId);
      } else {
        await StorageService.markEpisodeAsFinished(
          seriesTitle: title,
          season: target.season!,
          episode: target.episode!,
          imdbId: target.contentId,
          recoveryUpdatedAtMs: remote.lastPlayedAtMs,
        );
      }
    } else if (remote.durationMs > 0 || remote.hasPartialBookmark) {
      final speed = (local?['speed'] as num?)?.toDouble() ?? 1.0;
      final aspect = local?['aspect'] as String? ?? 'contain';
      if (target.isMovie) {
        await StorageService.saveVideoPlaybackState(
          videoTitle: source.displayTitle,
          videoUrl: source.directUrl ?? '',
          imdbId: target.contentId,
          positionMs: remote.positionMs,
          durationMs: remote.durationMs,
          speed: speed,
          aspect: aspect,
          recoveryUpdatedAtMs: remote.lastPlayedAtMs,
        );
      } else {
        await StorageService.saveSeriesPlaybackState(
          seriesTitle: title,
          season: target.season!,
          episode: target.episode!,
          imdbId: target.contentId,
          positionMs: remote.positionMs,
          durationMs: remote.durationMs,
          speed: speed,
          aspect: aspect,
          recoveryUpdatedAtMs: remote.lastPlayedAtMs,
        );
      }
    }
  });
}

class MediaServerWatchPosition {
  const MediaServerWatchPosition(this.positionMs, this.durationMs, this.paused);
  final int positionMs;
  final int durationMs;
  final bool paused;
}

String _newWatchSessionId() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// One validated server item. Only the latest pending observation is retained;
/// all HTTP writes are ordered, authorized at send time and best effort.
class MediaServerWatchSession {
  MediaServerWatchSession({
    required this.client,
    required this.account,
    required this.itemId,
    required this.mediaSourceId,
    required this.playSessionId,
    required this.authorize,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final MediaServerClient client;
  final MediaServerAccount account;
  final String itemId;
  final String mediaSourceId;
  final String playSessionId;
  final Future<void> Function() authorize;
  final DateTime Function() _now;
  MediaServerWatchPosition? _last;
  MediaServerWatchPosition? _pending;
  DateTime? _lastQueuedAt;
  DateTime? _lastObservedAt;
  Future<void>? _previousSession;
  Future<void>? _draining;
  bool _started = false;
  bool _closed = false;
  bool _complete = false;

  /// Replaying the already-open direct file needs a new check-in identity,
  /// not another import of server progress. Authorization remains revocable.
  MediaServerWatchSession _forReplay() => MediaServerWatchSession(
    client: MediaServerWatchSync.clientFactory(),
    account: account,
    itemId: itemId,
    mediaSourceId: mediaSourceId,
    playSessionId: _newWatchSessionId(),
    authorize: authorize,
    now: _now,
  );

  bool get _hasCompleted => _complete;

  void observe({
    required int positionMs,
    required int durationMs,
    required bool playing,
    bool completed = false,
  }) {
    if (_closed || durationMs <= 0 || positionMs < 0) return;
    // A paused load or an unlanded resume is not a playback event.
    if (_last == null && (!playing || positionMs == 0)) return;
    final next = MediaServerWatchPosition(
      positionMs.clamp(0, durationMs),
      durationMs,
      !playing,
    );
    final previous = _last;
    _last = next;
    _complete |= completed && positionMs >= durationMs * 0.9;
    final now = _now();
    final observationElapsed = _lastObservedAt == null
        ? 0
        : now.difference(_lastObservedAt!).inMilliseconds;
    _lastObservedAt = now;
    final elapsed = _lastQueuedAt == null
        ? 10000
        : now.difference(_lastQueuedAt!).inMilliseconds;
    final interacted =
        previous != null &&
        (previous.paused != next.paused ||
            (next.positionMs - previous.positionMs).abs() >
                max(5000, observationElapsed * 4));
    if (elapsed < 10000 && !interacted && !completed) return;
    _lastQueuedAt = now;
    _pending = next;
    unawaited(_pump());
  }

  Future<void> _report(String action, MediaServerWatchPosition value) =>
      client.reportWatchProgress(
        account,
        itemId: itemId,
        mediaSourceId: mediaSourceId,
        playSessionId: playSessionId,
        action: action,
        positionMs: value.positionMs,
        paused: value.paused,
        authorize: authorize,
      );

  Future<void> _pump() => _draining ??= _drain().whenComplete(() {
    _draining = null;
  });

  Future<void> _drain() async {
    try {
      await _previousSession;
      while (_pending != null) {
        final next = _pending!;
        _pending = null;
        await _report(_started ? 'progress' : 'start', next);
        _started = true;
      }
      if (_closed && _started && _last != null) {
        await _report('stop', _last!);
        if (_complete) {
          await client.markWatched(account, itemId, authorize: authorize);
        }
      }
    } catch (_) {
      // No credential-bearing exception logging; no replay after revocation,
      // profile switches or player exit. The next live tick may retry.
      _pending = null;
    } finally {
      if (_closed) client.close();
    }
  }

  Future<void> close() {
    if (_closed) return _draining ?? Future<void>.value();
    _closed = true;
    _pending = _last;
    return _pump();
  }
}

/// Owned by a player launch. Unvalidated candidates can be read but never
/// report progress. A source switch closes the previous item's session.
class MediaServerWatchController {
  final _prepared = <Torrent, MediaServerWatchSession?>{};
  final _preparing = <Torrent, Future<void>>{};
  Torrent? _activeSource;
  MediaServerWatchSession? _active;
  MediaServerWatchSession? _replayTemplate;
  MediaServerWatchTarget? _lastCommittedTarget;
  bool _closed = false;
  Future<void> _retiring = Future<void>.value();

  bool get isActive => !_closed && (_active != null || _replayTemplate != null);

  static bool isServerSource(Torrent? source) =>
      source != null && MediaServerService.watchTargetFor(source) != null;

  Future<void> prepare(
    Torrent? source, {
    bool importResume = true,
    String? contentTitle,
  }) async {
    if (_closed || source == null || _prepared.containsKey(source)) return;
    if (identical(source, _activeSource) && _replayTemplate != null) return;
    await (_preparing[source] ??= _prepare(source, importResume, contentTitle));
  }

  Future<void> _prepare(
    Torrent source,
    bool importResume,
    String? contentTitle,
  ) async {
    final target = MediaServerService.watchTargetFor(source);
    if (target == null) return;
    MediaServerClient? client;
    try {
      Future<void> authorize() => target.capability.runIfCurrent(() async {
        await target.authorize();
        if (!await MediaServerWatchSync.enabled()) {
          throw StateError('Server watch sync is disabled');
        }
      });
      await authorize();
      client = MediaServerWatchSync.clientFactory();
      final reads = await Future.wait<Object?>([
        client.watchState(target.account, target.itemId, authorize: authorize),
        client.watchSessionId(
          target.account,
          target.itemId,
          authorize: authorize,
        ),
      ]);
      final remote = reads[0] as MediaServerWatchState;
      final sessionId = reads[1] as String?;
      if (_closed) {
        client.close();
        return;
      }
      final previous = _lastCommittedTarget;
      final switchingSameContent =
          previous != null &&
          previous.contentId == target.contentId &&
          previous.isMovie == target.isMovie &&
          previous.season == target.season &&
          previous.episode == target.episode;
      if (importResume && !switchingSameContent) {
        await MediaServerWatchSync.importState(
          target,
          source,
          remote,
          contentTitle: contentTitle,
        );
      }
      await authorize();
      if (_closed) {
        client.close();
        return;
      }
      _prepared[source] = MediaServerWatchSession(
        client: client,
        account: target.account,
        itemId: target.itemId,
        mediaSourceId: target.mediaSourceId,
        playSessionId: sessionId ?? _newWatchSessionId(),
        authorize: authorize,
      );
    } catch (_) {
      client?.close();
      _prepared[source] = null;
    }
  }

  void commit(Torrent? source) {
    if (_closed || identical(source, _activeSource)) return;
    final previous = _active;
    final previousSource = _activeSource;
    _activeSource = source;
    _active = _prepared[source];
    _replayTemplate = null;
    if (source != null) {
      _lastCommittedTarget = MediaServerService.watchTargetFor(source);
    }
    if (previousSource != null) {
      _prepared.remove(previousSource);
      _preparing.remove(previousSource);
    }
    if (previous != null) {
      _retiring = Future.wait<void>([_retiring, previous.close()]).then((_) {});
    }
    // An outgoing stop must land before an incoming start, especially when
    // switching versions of the same library item on a slow connection.
    _active?._previousSession = _retiring;
  }

  void observe(
    Torrent? source, {
    required int positionMs,
    required int durationMs,
    required bool playing,
    bool completed = false,
    int? season,
    int? episode,
  }) {
    if (_closed || source == null || !identical(source, _activeSource)) return;
    final target = MediaServerService.watchTargetFor(source);
    if (target == null ||
        (!target.isMovie &&
            (season != target.season || episode != target.episode))) {
      return;
    }
    final replay = _replayTemplate;
    if (replay != null) {
      // A repeated EOF or a paused seek isn't a new viewing. A real replay
      // starts only after playback resumes below the end of the same item.
      if (completed ||
          !playing ||
          durationMs <= 0 ||
          positionMs < 0 ||
          positionMs >= durationMs) {
        return;
      }
      _active = replay._forReplay().._previousSession = _retiring;
      _prepared[source] = _active;
      _replayTemplate = null;
    }
    final active = _active;
    active?.observe(
      positionMs: positionMs,
      durationMs: durationMs,
      playing: playing,
      completed: completed,
    );
    if (active != null && active._hasCompleted) {
      // EOF is a boundary even if the player route/activity stays open. Keep
      // only a replay template; no subsequent position can mutate this stop.
      _active = null;
      _prepared.remove(source);
      _preparing.remove(source);
      _replayTemplate = active;
      _retiring = Future.wait<void>([_retiring, active.close()]).then((_) {});
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await Future.wait([
      _retiring,
      ..._prepared.values.whereType<MediaServerWatchSession>().map(
        (session) => session.close(),
      ),
    ]);
    _prepared.clear();
    _active = null;
    _replayTemplate = null;
  }
}
