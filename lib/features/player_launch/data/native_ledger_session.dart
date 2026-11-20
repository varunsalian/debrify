import 'dart:async';

import 'package:debrify/features/player_launch/data/android_tv_playback_payload.dart';
import 'package:debrify/services/ledger/ledger_api.dart';
import 'package:debrify/services/ledger/ledger_service.dart';
import 'package:flutter/foundation.dart';

/// What a native session scrobbles to Ledger: built from the launch payload.
@immutable
class NativeLedgerTarget {
  const NativeLedgerTarget({
    required this.enabled,
    required this.imdbId,
    required this.isSeries,
  });

  final bool enabled;
  final String? imdbId;
  final bool isSeries;
}

/// Ledger scrobbling for the Android TV native player. Ledger follows
/// Trakt's model (START and PAUSE save a resume point, STOP past the watched
/// percent records a play), so this is the same state machine as the Trakt
/// block in `NativeProgressHandler`, with its own state: trackers never share
/// dedup guards or heartbeats.
final class NativeLedgerSession {
  NativeLedgerSession._();

  static String? lastScrobbleAction;
  static double lastKnownProgress = 0.0;
  static int? lastKnownSeason;
  static int? lastKnownEpisode;
  static Timer? heartbeatTimer;

  @visibleForTesting
  static LedgerService? debugService;
  static LedgerService get _service => debugService ?? LedgerService.instance;

  /// The account's watched percent: a STOP at or past it records a play.
  /// Read once per session (the default until it arrives).
  static double _finishPercent = LedgerService.defaultFinishPercent.toDouble();
  static bool _finishRequested = false;
  static int _generation = 0;

  /// The position the server last received, so an exit after a paused seek
  /// can still save where the user actually stopped.
  static double? _lastSentProgress;

  /// Clears all state for a fresh native session.
  static void reset() {
    _generation++;
    _finishPercent = LedgerService.defaultFinishPercent.toDouble();
    _finishRequested = false;
    _lastSentProgress = null;
    heartbeatTimer?.cancel();
    heartbeatTimer = null;
    lastScrobbleAction = null;
    lastKnownProgress = 0.0;
    lastKnownSeason = null;
    lastKnownEpisode = null;
  }

  static void _send(
    LedgerScrobbleAction action,
    String imdbId,
    double progress,
    int? season,
    int? episode,
  ) {
    _lastSentProgress = progress;
    unawaited(
      _service.scrobble(
        action,
        imdbId,
        progress,
        season: season,
        episode: episode,
      ),
    );
  }

  static void _stopHeartbeat() {
    heartbeatTimer?.cancel();
    heartbeatTimer = null;
  }

  /// Adapts a native progress ping (the map Kotlin sends) for [onProgress].
  static void onNativeProgress(
    AndroidTvPlaybackPayload payload,
    Map<String, dynamic> progress,
  ) {
    final positionMs = (progress['positionMs'] ?? 0) as int;
    final durationMs = (progress['durationMs'] ?? 0) as int;
    if (durationMs <= 0) return;
    final series = payload.trackingContentType == 'series';
    onProgress(
      _target(payload),
      progress: (positionMs / durationMs * 100).clamp(0.0, 100.0),
      // Buffering still counts as playing (ExoPlayer reports isPlaying=false
      // while it buffers), as for Trakt.
      isPlaying: progress['isPlaying'] == true || progress['isBuffering'] == true,
      completed: progress['completed'] == true,
      // Ignored for non-series: avoids filename false positives ("5.1").
      season: series ? progress['season'] as int? : null,
      episode: series ? progress['episode'] as int? : null,
    );
  }

  /// The native player closed.
  static void onNativeExit(AndroidTvPlaybackPayload payload) => onExit(_target(payload));

  static NativeLedgerTarget _target(AndroidTvPlaybackPayload payload) => NativeLedgerTarget(
    enabled: payload.ledgerScrobble,
    imdbId: payload.imdbId,
    isSeries: payload.trackingContentType == 'series',
  );

  /// One native progress ping. [season]/[episode] are only meaningful for
  /// series (callers pass null otherwise).
  static void onProgress(
    NativeLedgerTarget target, {
    required double progress,
    required bool isPlaying,
    required bool completed,
    required int? season,
    required int? episode,
  }) {
    if (!target.enabled || target.imdbId == null) return;
    if (target.isSeries && (season == null || episode == null)) return;
    final imdbId = target.imdbId!;
    if (!_finishRequested) {
      _finishRequested = true;
      final generation = _generation;
      unawaited(
        _service.finishPercent().then((percent) {
          if (generation == _generation) _finishPercent = percent.toDouble();
        }),
      );
    }

    // Episode switch: finalise the previous episode first.
    if (lastKnownSeason != null &&
        lastKnownEpisode != null &&
        (season != lastKnownSeason || episode != lastKnownEpisode) &&
        lastScrobbleAction != 'stop') {
      _stopHeartbeat();
      _send(
        LedgerScrobbleAction.stop,
        imdbId,
        lastKnownProgress,
        lastKnownSeason,
        lastKnownEpisode,
      );
      lastScrobbleAction = 'stop';
    }
    lastKnownProgress = progress;
    lastKnownSeason = season;
    lastKnownEpisode = episode;
    // Seeked back under 80% after a stop: a new session may start.
    if (lastScrobbleAction == 'stop' && isPlaying && progress < _finishPercent && !completed) {
      lastScrobbleAction = null;
    }
    if (completed && lastScrobbleAction != 'stop') {
      lastScrobbleAction = 'stop';
      _stopHeartbeat();
      _send(LedgerScrobbleAction.stop, imdbId, progress, season, episode);
    } else if (isPlaying && lastScrobbleAction != 'start' && lastScrobbleAction != 'stop') {
      if (progress >= _finishPercent) {
        lastScrobbleAction = 'stop';
        _send(LedgerScrobbleAction.stop, imdbId, progress, season, episode);
      } else {
        lastScrobbleAction = 'start';
        _send(LedgerScrobbleAction.start, imdbId, progress, season, episode);
        _startHeartbeat(imdbId);
      }
    } else if (!isPlaying &&
        !completed &&
        lastScrobbleAction != null &&
        lastScrobbleAction != 'pause' &&
        lastScrobbleAction != 'stop') {
      _stopHeartbeat();
      if (progress >= _finishPercent) {
        lastScrobbleAction = 'stop';
        _send(LedgerScrobbleAction.stop, imdbId, progress, season, episode);
      } else {
        lastScrobbleAction = 'pause';
        _send(LedgerScrobbleAction.pause, imdbId, progress, season, episode);
      }
    }
  }

  static void _startHeartbeat(String imdbId) {
    _stopHeartbeat();
    heartbeatTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      if (lastKnownProgress >= _finishPercent) {
        lastScrobbleAction = 'stop';
        _send(
          LedgerScrobbleAction.stop,
          imdbId,
          lastKnownProgress,
          lastKnownSeason,
          lastKnownEpisode,
        );
        _stopHeartbeat();
        return;
      }
      // Bypasses dedup on purpose: refreshes the saved resume point.
      lastScrobbleAction = 'start';
      _send(
        LedgerScrobbleAction.start,
        imdbId,
        lastKnownProgress,
        lastKnownSeason,
        lastKnownEpisode,
      );
    });
  }

  /// The player closed. A live session is stopped at its last position. A
  /// paused one already saved its point, unless the user seeked while paused:
  /// then the new position is saved (or, past the watched percent, the play
  /// is recorded). An unresolved series is never finalised as a movie.
  static void onExit(NativeLedgerTarget target) {
    _stopHeartbeat();
    final unresolvedSeries =
        target.isSeries && (lastKnownSeason == null || lastKnownEpisode == null);
    final moved = _lastSentProgress == null || (lastKnownProgress - _lastSentProgress!).abs() >= 1;
    if (target.enabled &&
        target.imdbId != null &&
        lastScrobbleAction != null &&
        lastScrobbleAction != 'stop' &&
        (lastScrobbleAction != 'pause' || moved) &&
        !unresolvedSeries) {
      _send(
        lastScrobbleAction == 'pause' && lastKnownProgress < _finishPercent
            ? LedgerScrobbleAction.pause
            : LedgerScrobbleAction.stop,
        target.imdbId!,
        lastKnownProgress,
        lastKnownSeason,
        lastKnownEpisode,
      );
    }
    reset();
  }
}
