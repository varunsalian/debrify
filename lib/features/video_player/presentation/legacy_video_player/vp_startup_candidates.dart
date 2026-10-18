import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/services/android_renderer_startup_fallback.dart';
import 'package:debrify/services/media_server_watch_sync.dart';
import 'package:debrify/services/source_selection_diagnostics.dart';
import 'package:debrify/services/startup_stream_policy.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpStartupCandidatesHost {
  AndroidVideoRendererMode get androidVideoRendererMode;
  int get currentSourceIndex;
  Torrent? get openedWatchSource;
  mk.Player get player;
  bool get rendererFallbackInProgress;
  bool get rendererValidatedForSession;
  MediaServerWatchController get serverWatch;
  Future<void> openMedia(
    mk.Media media, {
    required bool play,
    bool? desiredPlay,
    bool liveStream = false,
    EpisodePlaybackRequest? request,
    bool Function()? beforeOpen,
    Torrent? source,
    int? preserveStartupEpoch,
  });
  Future<void> Function(Torrent)? get onStremioSourceCommitted;
  bool get isAndroid;
}

class VpStartupCandidates {
  VpStartupCandidates(this._host);
  final VpStartupCandidatesHost _host;

  /// Opens one VOD candidate with the real media-kit player and keeps that
  /// exact player session on success. Unlike the old Dart HEAD probe this has
  /// no validation/playback race: decoded video or advancing position commits
  /// the candidate; an error, open throw, or bounded startup stall rejects it.
  /// Debrid-resolved candidates skip the decode probe. The debrid API minted
  /// (and thereby vouched for) the URL moments ago, so the probe's dead-link
  /// protection is redundant — and its cost is real: committing on the first
  /// decoded frame means the resume seek lands mid-startup-burst at 0, which
  /// mpv on a cold stream answers by restarting (the masked-seek repro).
  /// A plain open instead accepts on duration (header metadata, pre-decode),
  /// so the resume seek folds into startup as "begin here" — the pre-ladder
  /// timing that always worked. Addon direct URLs (the stale-cached-link
  /// class the probe exists for) keep the full validation.
  Future<bool> openStartupDebridDirect(
    String url, {
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final stopwatch = Stopwatch()..start();
    final completer = Completer<bool>();
    var candidateDuration = Duration.zero;
    var bufferedAmount = Duration.zero;
    final sourceFields = startupSourceFields(sourceIndex, source);
    debugPrint(
      '[StartupFailover] event=candidate_open platform=flutter '
      'attempt=$attempt/$maxAttempts $sourceFields route=debrid_direct '
      'timeoutMs=${timeout.inMilliseconds}',
    );
    void finish(bool ok, String reason) {
      if (completer.isCompleted) return;
      debugPrint(
        '[StartupFailover] event=candidate_result platform=flutter '
        'attempt=$attempt/$maxAttempts $sourceFields ok=$ok reason=$reason '
        'elapsedMs=${stopwatch.elapsedMilliseconds} '
        'durationMs=${candidateDuration.inMilliseconds}',
      );
      completer.complete(ok);
    }

    // A dead debrid link (deleted torrent race, expired token) errors or
    // serves something with no parseable duration — either way the ladder
    // advances to the next candidate exactly like a failed probe.
    final subs = <StreamSubscription>[
      _host.player.stream.error.listen((error) {
        if (AndroidRendererStartupFallback.isRendererFailure(error) &&
            AndroidRendererStartupFallback.shouldArm(
              isAndroid: _host.isAndroid,
              isAndroidTv: PlatformUtil.isAndroidTvCached,
              mode: _host.androidVideoRendererMode,
              alreadyValidated: _host.rendererValidatedForSession,
              fallbackInProgress: _host.rendererFallbackInProgress,
            )) {
          // Renderer-bound failure, owned by the renderer fallback — same
          // contract as the probe path (see _tryOpenStartupVod).
          finish(true, 'renderer_fallback_deferred');
          return;
        }
        finish(false, 'player_error');
      }),
      _host.player.stream.duration.listen((value) {
        candidateDuration = value;
        if (value > Duration.zero) finish(true, 'duration_known');
      }),
      // Durationless media (some MPEG-TS/M2TS and non-seekable progressive
      // files) never publishes a duration — accept on decoded, advancing
      // video like the probe would, or the watchdog eventually kills a
      // stream that is visibly playing. Duration almost always arrives
      // first, so this fallback does not delay the common case.
      _host.player.stream.width.listen((width) {
        if ((width ?? 0) > 0 && _host.player.state.position > Duration.zero) {
          finish(true, 'decoded_video');
        }
      }),
      _host.player.stream.position.listen((value) {
        if (value > Duration.zero && (_host.player.state.width ?? 0) > 0) {
          finish(true, 'decoded_video');
        }
      }),
      _host.player.stream.buffer.listen((value) {
        bufferedAmount = value;
      }),
    ];
    try {
      await _host.openMedia(
        mk.Media(url, httpHeaders: httpHeaders),
        play: true,
        source: source,
      );
    } catch (e) {
      debugPrint(
        '[StartupFailover] event=open_exception platform=flutter '
        '$sourceFields exception=${e.runtimeType}',
      );
      finish(false, 'open_exception');
    }
    // Same slow-versus-dead distinction as the probe path: a link whose
    // buffer keeps growing is downloading, not dead — failing it would burn
    // a possibly single-use debrid link. Extend in steps up to the same cap.
    const extendStep = Duration(seconds: 3);
    const maxWait = Duration(seconds: 45);
    var lastBufferMark = Duration.zero;
    var ok = false;
    while (true) {
      final remaining = timeout - stopwatch.elapsed;
      try {
        ok = await completer.future.timeout(
          remaining > Duration.zero ? remaining : extendStep,
        );
        break;
      } on TimeoutException {
        if (bufferedAmount > lastBufferMark && stopwatch.elapsed < maxWait) {
          lastBufferMark = bufferedAmount;
          debugPrint(
            '[StartupFailover] event=watchdog_extend platform=flutter '
            '$sourceFields elapsedMs=${stopwatch.elapsedMilliseconds} '
            'bufferedMs=${bufferedAmount.inMilliseconds}',
          );
          continue;
        }
        finish(false, 'timeout');
        ok = false;
        break;
      }
    }
    for (final sub in subs) {
      unawaited(sub.cancel());
    }
    if (!ok) {
      try {
        await _host.player.stop();
      } catch (_) {}
    }
    return ok;
  }

  Future<bool> tryOpenStartupVod(
    String url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? httpHeaders,
    Torrent? source,
    int? sourceIndex,
    int attempt = 1,
    int maxAttempts = 1,
  }) async {
    final stopwatch = Stopwatch()..start();
    final completer = Completer<bool>();
    var armed = false;
    var videoWidth = 0;
    var position = Duration.zero;
    var candidateDuration = Duration.zero;
    Timer? durationGraceTimer;
    final isAioStreams = StartupStreamPolicy.isAioStreams(
      addonId: source?.stremioAddonId,
      sourceName: source?.source,
      url: url,
    );
    final sourceFields = startupSourceFields(sourceIndex, source);
    debugPrint(
      '[StartupFailover] event=candidate_open platform=flutter '
      'attempt=$attempt/$maxAttempts $sourceFields aio=$isAioStreams '
      'timeoutMs=${timeout.inMilliseconds}',
    );
    void finish(bool ok, String reason) {
      if (completer.isCompleted) return;
      debugPrint(
        '[StartupFailover] event=candidate_result platform=flutter '
        'attempt=$attempt/$maxAttempts $sourceFields ok=$ok reason=$reason '
        'elapsedMs=${stopwatch.elapsedMilliseconds} width=$videoWidth '
        'positionMs=${position.inMilliseconds} '
        'durationMs=${candidateDuration.inMilliseconds}',
      );
      completer.complete(ok);
    }

    void maybeCommit() {
      // Width alone can be parsed from container metadata before a decoder has
      // produced anything. Requiring the media clock to advance as well keeps
      // metadata-only and permanently-buffering candidates behind the gate.
      if (!armed || videoWidth <= 0 || position <= Duration.zero) return;
      if (StartupStreamPolicy.isLikelyAioStreamsErrorSlate(
        addonId: source?.stremioAddonId,
        sourceName: source?.source,
        url: url,
        duration: candidateDuration,
      )) {
        finish(false, 'aiostreams_error_slate');
        return;
      }
      if (isAioStreams && candidateDuration <= Duration.zero) {
        // Progressive sources can publish duration just after playback starts.
        // Give that metadata a bounded chance to expose AIOStreams' short,
        // decodable error slate; unknown-duration real streams still proceed.
        durationGraceTimer ??= Timer(const Duration(seconds: 1), () {
          final isSlate = StartupStreamPolicy.isLikelyAioStreamsErrorSlate(
            addonId: source?.stremioAddonId,
            sourceName: source?.source,
            url: url,
            duration: candidateDuration,
          );
          finish(
            !isSlate,
            isSlate ? 'aiostreams_error_slate' : 'decoded_video',
          );
        });
        return;
      }
      finish(true, 'decoded_video');
    }

    var bufferedAmount = Duration.zero;
    final subs = <StreamSubscription>[
      _host.player.stream.error.listen((error) {
        if (!armed) return;
        // An explicit-renderer startup failure is owned by the renderer
        // fallback (_rendererStartupErrorSub sees this same event): it
        // disposes and rebuilds the player, then reopens THIS media on the
        // automatic renderer. Failing the candidate here would race two
        // opens on one surface — the ladder advancing on a player being
        // disposed — and the failure is renderer-bound, not source-bound,
        // so every other candidate would fail identically anyway. Accept
        // the candidate and let the fallback finish its recovery.
        if (AndroidRendererStartupFallback.isRendererFailure(error) &&
            AndroidRendererStartupFallback.shouldArm(
              isAndroid: _host.isAndroid,
              isAndroidTv: PlatformUtil.isAndroidTvCached,
              mode: _host.androidVideoRendererMode,
              alreadyValidated: _host.rendererValidatedForSession,
              fallbackInProgress: _host.rendererFallbackInProgress,
            )) {
          finish(true, 'renderer_fallback_deferred');
          return;
        }
        finish(false, 'player_error');
      }),
      _host.player.stream.width.listen((width) {
        videoWidth = width ?? 0;
        maybeCommit();
      }),
      _host.player.stream.position.listen((value) {
        position = value;
        maybeCommit();
      }),
      _host.player.stream.duration.listen((value) {
        candidateDuration = value;
        maybeCommit();
      }),
      _host.player.stream.buffer.listen((value) {
        bufferedAmount = value;
      }),
    ];
    try {
      // Arm at the final open boundary, after setup and authorization. Old
      // candidate events during those awaits must not validate this source.
      await _host.openMedia(
        mk.Media(url, httpHeaders: httpHeaders),
        play: true,
        source: source,
        beforeOpen: () {
          armed = true;
          return true;
        },
      );
    } catch (e) {
      // Exception strings from media backends may embed signed stream URLs.
      // The runtime type is enough to distinguish open failures safely.
      debugPrint(
        '[StartupFailover] event=open_exception platform=flutter '
        '$sourceFields exception=${e.runtimeType}',
      );
      finish(false, 'open_exception');
    }
    // The base timeout is for dead sources (no error, no data). A source
    // that is demonstrably still downloading — its buffer keeps growing —
    // is slow, not dead (large 4K remux, cold CDN, slow debrid peering);
    // failing it would burn a possibly single-use link and fall to a
    // lower-ranked source. Extend in short steps while bytes keep arriving,
    // bounded by a hard cap.
    const extendStep = Duration(seconds: 3);
    const maxWait = Duration(seconds: 45);
    var lastBufferMark = Duration.zero;
    var ok = false;
    while (true) {
      final remaining = timeout - stopwatch.elapsed;
      try {
        ok = await completer.future.timeout(
          remaining > Duration.zero ? remaining : extendStep,
        );
        break;
      } on TimeoutException {
        if (bufferedAmount > lastBufferMark && stopwatch.elapsed < maxWait) {
          lastBufferMark = bufferedAmount;
          debugPrint(
            '[StartupFailover] event=watchdog_extend platform=flutter '
            '$sourceFields elapsedMs=${stopwatch.elapsedMilliseconds} '
            'bufferedMs=${bufferedAmount.inMilliseconds}',
          );
          continue;
        }
        finish(false, 'timeout');
        ok = false;
        break;
      }
    }
    durationGraceTimer?.cancel();
    for (final sub in subs) {
      unawaited(sub.cancel());
    }
    if (!ok) {
      try {
        await _host.player.stop();
      } catch (_) {}
    }
    return ok;
  }

  Future<void> commitValidatedStremioSource(Torrent? source) async {
    if (identical(source, _host.openedWatchSource)) {
      _host.serverWatch.commit(source);
    }
    logSourceSelection(
      'player_source_committed',
      source: source,
      index: _host.currentSourceIndex,
      player: 'mpv',
    );
    final commit = _host.onStremioSourceCommitted;
    if (source == null || commit == null) return;
    try {
      await commit(source);
    } catch (error) {
      debugPrint(
        '[StartupFailover] event=binding_commit_failed platform=flutter '
        'exception=${error.runtimeType}',
      );
    }
  }

  String startupSourceFields(int? index, Torrent? source) {
    String safe(String? value) {
      if (value == null || value.isEmpty) return '-';
      final compact = value.replaceAll(RegExp(r'\s+'), ' ');
      return compact.length <= 64 ? compact : compact.substring(0, 64);
    }

    return 'sourceIndex=${index ?? '-'} type=${source?.streamType.name ?? '-'} '
        'addon=${safe(source?.stremioAddonId)} source=${safe(source?.source)}';
  }
}
