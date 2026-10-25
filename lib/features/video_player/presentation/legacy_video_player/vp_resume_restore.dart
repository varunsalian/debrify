import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/constants/timing_constants.dart';
import 'package:debrify/screens/video_player/utils/aspect_mode_utils.dart';
import 'package:debrify/services/resume_write_guard.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:debrify/utils/episode_progress_merge.dart';

abstract interface class VpResumeRestoreHost {
  bool get allowResumeForManualSelection;
  Duration get duration;
  String? get effectiveContentImdbId;
  bool get isAutoAdvancing;
  set isAutoAdvancing(bool v);
  bool get isManualEpisodeSelection;
  mk.Player get player;
  int get resumeVerifyEpoch;
  ResumeWriteGuard get resumeWriteGuard;
  bool get screenDisposed;
  Future<void> waitForDuration();
  Future<Map<String, dynamic>?> getEnhancedPlaybackState();
  String get resumeKey;
  bool get mounted;
  double? get traktProgressPercent;
  double? get mdblistProgressPercent;
  double? get simklProgressPercent;
  bool get launchTraktPercentSpent;
  set launchTraktPercentSpent(bool v);
  bool get launchSimklPercentSpent;
  set launchSimklPercentSpent(bool v);
  bool get launchMdblistPercentSpent;
  set launchMdblistPercentSpent(bool v);
  String? get currentLocalMovieImdbId;
  set playbackSpeed(double v);
  set aspectMode(AspectMode v);
  Future<double?> currentEpisodeTraktPercent({bool forGuide = false});
  Future<double?> currentEpisodeSimklPercent({bool forGuide = false});
  Future<double?> currentEpisodeMdblistPercent({bool forGuide = false});
  Future<void> applyAspectVideoZoom();
  Future<Map<String, dynamic>?> readLocalResume({
    required String? contentId,
    required String resumeKey,
    required Future<Map<String, dynamic>?> Function() enhanced,
  });
}

class VpResumeRestore {
  VpResumeRestore(this._host);
  final VpResumeRestoreHost _host;

  /// [preferLocalResume]: a source switch landed on the SAME content and
  /// checkpointed the live position — resume exactly there (any position, even
  /// past the 90% cutoff, matching the native TV player) and skip Trakt.
  /// Threaded as a parameter, not ambient state, so an early return or throw
  /// anywhere in the load path can never leak it into a later load.
  ///
  /// [verifyLanding]: this is the initial open, where the startup gate commits
  /// a candidate after ~40ms of decoded media and the seek can be answered with
  /// a stream restart. Confirm the seek took and re-issue once. See
  /// [seekForResume].
  Future<void> maybeRestoreResume({
    bool preferLocalResume = false,
    bool verifyLanding = false,
  }) async {
    // Every item load lands here, so this is where a previous item's unlanded
    // resume target stops applying — including on the paths below that return
    // without arming a new one (auto-advance, manual episode pick).
    _host.resumeWriteGuard.clear();
    // If this is auto-advancing, don't restore position
    if (_host.isAutoAdvancing) {
      _host.isAutoAdvancing = false; // Reset the flag
      return;
    }

    // If this is a manual episode selection, only restore if we have saved progress
    if (_host.isManualEpisodeSelection &&
        !_host.allowResumeForManualSelection) {
      // Don't reset _isManualEpisodeSelection here - let it be reset after a delay
      return;
    }
    final trackingPolicy = (await TrackingSourcePolicy.load()).forContent(
      _host.effectiveContentImdbId,
    );
    // The launched item's widget percent is a first-load-only signal; capture it
    // before marking it spent so it can't apply to a later switched-to episode.
    final firstLoad = !_host.launchTraktPercentSpent;
    _host.launchTraktPercentSpent = true;
    final simklFirstLoad = !_host.launchSimklPercentSpent;
    _host.launchSimklPercentSpent = true;
    final mdblistFirstLoad = !_host.launchMdblistPercentSpent;
    _host.launchMdblistPercentSpent = true;

    await _host.waitForDuration();
    final dur = _host.duration;

    // Trakt candidate (cross-device %), skipped for a source switch. Launched
    // item uses the widget percent (first load); a switched item uses its own
    // per-episode store percent. The widget percent is an EXPLICIT promise —
    // the details-screen Resume button advertised this position — so when
    // seekable it wins outright below (never silently overridden by local).
    double? traktPct;
    double? traktProviderPct;
    double? simklProviderPct;
    double? mdblistProviderPct;
    var explicitLaunch = false;
    if (!preferLocalResume &&
        trackingPolicy.progressFrom(TrackingSource.trakt)) {
      final launchPct = firstLoad ? _host.traktProgressPercent : null;
      if (launchPct != null) {
        traktPct = launchPct;
        traktProviderPct = launchPct;
        explicitLaunch = true;
      } else {
        traktPct = await _host.currentEpisodeTraktPercent();
        traktProviderPct = traktPct;
      }
    }
    if (!preferLocalResume &&
        trackingPolicy.progressFrom(TrackingSource.mdblist)) {
      final explicitMdblistPct = mdblistFirstLoad
          ? _host.mdblistProgressPercent
          : null;
      final mdblistPct =
          explicitMdblistPct ?? await _host.currentEpisodeMdblistPercent();
      mdblistProviderPct = mdblistPct;
      if (mdblistPct != null && (traktPct == null || mdblistPct > traktPct)) {
        traktPct = mdblistPct;
        explicitLaunch = explicitMdblistPct != null;
      }
    }
    // Simkl candidate: the explicit launch promise on first load, otherwise
    // this episode's launch-time snapshot. Folded into the same candidate as
    // Trakt so the furthest remote progress wins.
    if (!preferLocalResume &&
        trackingPolicy.progressFrom(TrackingSource.simkl)) {
      final explicitSimklPct = simklFirstLoad
          ? _host.simklProgressPercent
          : null;
      final simklPct =
          explicitSimklPct ?? await _host.currentEpisodeSimklPercent();
      simklProviderPct = simklPct;
      if (simklPct != null && (traktPct == null || simklPct > traktPct)) {
        traktPct = simklPct;
        explicitLaunch = explicitSimklPct != null;
      }
    }
    final int traktMs =
        (traktPct != null &&
            traktPct > 0 &&
            traktPct < 100 &&
            dur > Duration.zero)
        ? (dur.inMilliseconds * traktPct / 100).floor()
        : 0;

    // Local candidate + speed/aspect restore (enhanced state preferred, else the
    // legacy resume store). Speed/aspect are restored regardless of the seek.
    int localMs = 0;
    final allowLocalResume =
        preferLocalResume || trackingPolicy.progressFrom(TrackingSource.local);
    final localMovieImdbId = _host.currentLocalMovieImdbId;
    final locallyFinishedMovie =
        !preferLocalResume &&
        localMovieImdbId != null &&
        await MovieProgressStorage.isMovieFinished(localMovieImdbId);
    // Speed/aspect are device prefs riding in the resume record — restore
    // them in EVERY progress mode; only the POSITION is a policy-gated
    // resume candidate.
    final state = locallyFinishedMovie
        ? null
        : await _host.readLocalResume(
            contentId: _host.effectiveContentImdbId,
            resumeKey: _host.resumeKey,
            enhanced: _host.getEnhancedPlaybackState,
          );
    if (state != null) {
      if (allowLocalResume) {
        localMs = (state['positionMs'] ?? 0) as int;
      }
      final speed = (state['speed'] ?? 1.0) as double;
      final aspect = (state['aspect'] ?? 'contain') as String;
      if (speed != 1.0) {
        await _host.player.setRate(speed);
        _host.playbackSpeed = speed;
      }
      _host.aspectMode = AspectModeUtils.stringToAspectMode(aspect);
      await _host.applyAspectVideoZoom();
    }

    if (dur <= Duration.zero) return;

    // Source switch on the same content: come back EXACTLY where you were —
    // no resumable-window gating (you might be 93% in, mid-credits), matching
    // the native TV player's source-switch semantics.
    if (preferLocalResume) {
      if (localMs > 0 && localMs < dur.inMilliseconds) {
        await seekForResume(localMs, verifyLanding: verifyLanding);
      }
      return;
    }

    final loMs =
        VideoPlayerTimingConstants.minimumPlaybackPosition.inMilliseconds;
    final hiMs = (dur.inMilliseconds * 0.9).floor();
    // Legacy builds persisted Trakt watched history as if it were a local
    // completion. A current partial Trakt session is a rewatch, so that stale
    // completed position must not force a fresh start. Keep this migration
    // in-memory; the old record has no provenance and may be genuine local
    // history. Independent Simkl/MDBList completion still wins.
    if (localMs >= hiMs) {
      // The rewatch detector consumes the same policy-masked inputs as guide
      // rendering (ticks AND partials both follow the Progress source since
      // 2026-08-27) — a non-selected provider's session can't un-tick local
      // completion.
      traktProviderPct ??= await _host.currentEpisodeTraktPercent(
        forGuide: true,
      );
      simklProviderPct ??= await _host.currentEpisodeSimklPercent(
        forGuide: true,
      );
      mdblistProviderPct ??= await _host.currentEpisodeMdblistPercent(
        forGuide: true,
      );
      if (hasActiveTraktEpisodeRewatch(
        traktPercent: traktProviderPct,
        simklPercent: simklProviderPct,
        mdblistPercent: mdblistProviderPct,
      )) {
        localMs = 0;
      }
    }
    // The details-screen Resume promised THIS position — honour it outright when
    // seekable (matching the pre-rework launched-item behaviour), even over a
    // deeper/stale local. An unseekable promise falls through to furthest-wins.
    if (explicitLaunch && traktMs > loMs && traktMs < hiMs) {
      debugPrint('Resume: explicit tracker percent -> ${traktMs}ms');
      await seekForResume(traktMs, verifyLanding: verifyLanding);
      return;
    }
    // FURTHEST-WATCHED WINS: seek the deeper of the local position and the Trakt
    // percent, provided it's in the resumable window (past the first 2s, before
    // the last 10%). If neither qualifies, start fresh.
    // Locally FINISHED (past the 90% cutoff on this device): start fresh, and
    // never let a shallower/stale Trakt percent yank a restarted episode into
    // its middle — local IS the furthest position, it's just not seekable.
    if (localMs >= hiMs && localMs > 0) return;
    final traktCand = (traktMs > loMs && traktMs < hiMs) ? traktMs : 0;
    final localCand = (localMs > loMs && localMs < hiMs) ? localMs : 0;
    final target = traktCand > localCand ? traktCand : localCand;
    if (target > 0) {
      debugPrint(
        'Resume: furthest of remote=${traktMs}ms local=${localMs}ms -> ${target}ms',
      );
      await seekForResume(target, verifyLanding: verifyLanding);
    }
  }

  /// Single exit for every resume seek: arms the write guard so a seek that
  /// never lands cannot have its own bookmark overwritten, and — on the startup
  /// path only — confirms the position actually moved.
  ///
  /// [verifyLanding] is opt-in because only the startup path seeks into a
  /// stream the gate committed after ~40ms of decoded media. mpv can answer
  /// that seek by restarting the remote stream at 0 (observed on a debrid link
  /// via the pinned-source ladder), which leaves playback at the beginning with
  /// no error to react to. Re-issuing once, after the stream has warmed up,
  /// recovers it. Mid-session seeks (source switch, episode change) already run
  /// against a settled stream and keep their existing single-shot behaviour.
  Future<void> seekForResume(int targetMs, {bool verifyLanding = false}) async {
    // Never GUARD a near-finished target (≥80% of a known duration — the
    // trackers' stop-scrobble threshold, below the 90% local finished cutoff):
    // substituting one would scrobble a watched mark and store a finished-
    // looking position for content that may be playing at 0:00. The seek
    // itself still happens; such a start just plays unguarded.
    final durMs = _host.duration.inMilliseconds;
    final nearFinished = durMs > 0 && targetMs >= (durMs * 0.8).floor();
    if (nearFinished) {
      _host.resumeWriteGuard.clear();
    } else {
      _host.resumeWriteGuard.arm(targetMs);
    }
    final target = Duration(milliseconds: targetMs);
    await _host.player.seek(target);
    // Without an armed guard the verifier would abort on its first check.
    if (!verifyLanding || nearFinished) return;
    // Deliberately NOT awaited: the caller is the startup chain, and the
    // "Checking stream…" gate does not come down until it returns. Blocking
    // here would hold that overlay over the video for the whole verification
    // window on exactly the runs that already went wrong.
    unawaited(verifyResumeLanding(targetMs, _host.resumeVerifyEpoch));
  }

  /// Confirms a startup resume seek took, re-issuing it once if it did not.
  ///
  /// Aborts the moment its media stops being current — [epoch] changed (item
  /// change, source switch), the guard stopped pointing at [targetMs] (user
  /// seek), or the position reached the target — so a late retry can never
  /// yank playback away from where the user put it or seek a replacement
  /// stream it was never watching.
  Future<void> verifyResumeLanding(int targetMs, int epoch) async {
    // A viewer who sees playback start from 0 decides "broken" within a couple
    // of seconds — a single retry after 5s (the first version of this) lost
    // the race against the user's own quit on the observed phone repro. Check
    // early and re-issue up to three times: the first retry catches the common
    // case (mpv restarted a barely-warmed debrid stream at 0), the later ones
    // land on a progressively warmer stream. Every cycle keeps the same abort
    // conditions, so a user seek, item change, or dispose stops it instantly.
    const waits = [
      Duration(milliseconds: 1500),
      Duration(milliseconds: 1500),
      Duration(seconds: 3),
    ];
    for (var attempt = 0; attempt < waits.length; attempt++) {
      if (await resumeSeekLanded(targetMs, epoch, timeout: waits[attempt])) {
        return;
      }
      if (!_host.mounted || _host.screenDisposed) return;
      if (epoch != _host.resumeVerifyEpoch) return;
      if (_host.resumeWriteGuard.pendingTargetMs != targetMs) return;
      debugPrint(
        'Resume: seek did not land '
        '(position=${_host.player.state.position.inMilliseconds}ms '
        'target=${targetMs}ms) — re-issuing (${attempt + 1}/${waits.length})',
      );
      await _host.player.seek(Duration(milliseconds: targetMs));
    }
    if (await resumeSeekLanded(targetMs, epoch)) return;
    // Still adrift: leave playback where it is rather than fighting the stream.
    // The write guard keeps the stored resume point intact either way.
    debugPrint(
      'Resume: seek still unlanded after retries — leaving playback in place',
    );
  }

  /// Polls for the resume target within a bounded window. Landing is judged
  /// with the same tolerance the write guard uses, since a seek resolves to the
  /// nearest keyframe rather than the exact millisecond.
  ///
  /// Returns true for "stop verifying", which covers landing as well as the
  /// cases where the target stopped being ours: the screen went away, the
  /// epoch moved on, the user seeked, or another item loaded.
  Future<bool> resumeSeekLanded(
    int targetMs,
    int epoch, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    const interval = Duration(milliseconds: 200);
    // mpv can MASK a seek: it reports the target position for a moment, then
    // a cold debrid stream answers the actual seek by restarting at 0 — the
    // observed "seekbar at halfway for a few ms" phone repro. A single
    // position reading is therefore worthless as landing proof: require the
    // position to still be at the target after a beat, or keep watching.
    const confirmDelay = Duration(milliseconds: 800);
    bool atTarget() =>
        _host.player.state.position.inMilliseconds >=
        targetMs - _host.resumeWriteGuard.toleranceMs;
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!_host.mounted || _host.screenDisposed) return true;
      if (epoch != _host.resumeVerifyEpoch) return true;
      if (_host.resumeWriteGuard.pendingTargetMs != targetMs) return true;
      if (atTarget()) {
        await Future<void>.delayed(confirmDelay);
        if (!_host.mounted || _host.screenDisposed) return true;
        if (epoch != _host.resumeVerifyEpoch) return true;
        if (_host.resumeWriteGuard.pendingTargetMs != targetMs) return true;
        if (atTarget()) return true;
        debugPrint(
          'Resume: landing was transient (masked seek unwound to '
          '${_host.player.state.position.inMilliseconds}ms) — still watching',
        );
        continue;
      }
      await Future<void>.delayed(interval);
    }
    return false;
  }
}
