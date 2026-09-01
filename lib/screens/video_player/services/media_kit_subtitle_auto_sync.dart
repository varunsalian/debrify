import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'media_kit_audio_feature_tap.dart';
import 'subtitle_aligner.dart';
import 'subtitle_cue_parser.dart';

enum SubtitleAutoSyncNoticeKind {
  /// A fresh listening window opened (subtitle activated / track restart).
  listening,

  /// An alignment pass started for the current window.
  checking,

  /// An alignment pass ended without a verdict; the window continues. Kept
  /// distinct from [listening] so hosts never mistake a checking-revert for
  /// a new window (or vice versa — a subtitle switch mid-checking must
  /// restart the countdown, not inherit the old one).
  stillListening,
  synced,
  resynced,
  failed,
}

class SubtitleAutoSyncNotice {
  final SubtitleAutoSyncNoticeKind kind;
  final String message;

  const SubtitleAutoSyncNotice(this.kind, this.message);
}

/// What the controller has applied to the player for the active subtitle:
/// display time = file time × [scale] + [offsetMs].
typedef SubtitleSyncApplied = ({int offsetMs, double scale});

class _AlignRequest {
  final List<AudioFeatureSegment> segments;
  final List<SubtitleCueSpan> cues;
  final bool tiered;
  final bool residual;
  final bool drift;

  const _AlignRequest({
    required this.segments,
    required this.cues,
    this.tiered = false,
    this.residual = false,
    this.drift = false,
  });
}

SubtitleAlignResult _alignInBackground(_AlignRequest request) {
  if (request.tiered) {
    return SubtitleAligner.alignTiered(request.segments, request.cues);
  }
  if (request.drift) {
    // Full tier, every framerate hypothesis, whole history, original cues.
    return SubtitleAligner.align(request.segments, request.cues);
  }
  if (request.residual) {
    return SubtitleAligner.align(
      request.segments,
      request.cues,
      searchWindowMs: 10000,
      minimumAudioMs: 25000,
      minimumCueOverlapFrames: SubtitleAligner.narrowMinCueOverlapFrames,
      minimumCues: SubtitleAligner.narrowMinCues,
      minimumZPeak: SubtitleAligner.narrowMinZPeak,
      minimumPsr: SubtitleAligner.narrowMinPsr,
      scaleCandidates: const <double>[1],
    );
  }
  // Escalated verify: full width, but offset-only — the scale (if any) was
  // decided at sync time and a residual pass must not re-litigate it from a
  // six-minute window.
  return SubtitleAligner.align(
    request.segments,
    request.cues,
    scaleCandidates: const <double>[1],
  );
}

/// Owns the hands-free attempt ladder for one MediaKit player instance.
///
/// All playback-facing operations fail closed: if the passive filter cannot
/// be installed, metadata stops, parsing fails, or the player is being torn
/// down, the controller abandons auto-sync and never changes subtitle timing.
///
/// The audio feature history belongs to the CONTENT, not to the subtitle:
/// switching subtitle files keeps everything the tap has heard, so a second
/// subtitle picked ten minutes in is judged against ten minutes of audio the
/// moment it loads instead of waiting for a fresh listen. Only
/// [contentChanged] (or an audio-track switch) discards history.
class MediaKitSubtitleAutoSync {
  MediaKitSubtitleAutoSync({
    required mk.NativePlayer player,
    required this.enabled,
    required this.currentPositionMs,
    required this.isPlaying,
    required this.currentOffsetMs,
    required this.applyOffsetMs,
    required this.onNotice,
    Future<void> Function(double scale)? applyScale,
    bool passthroughEnabled = false,
  }) : _passthroughEnabled = passthroughEnabled,
       applyScale = applyScale ?? _noScale,
       _tap = MediaKitAudioFeatureTap(
         player: player,
         currentPositionMs: currentPositionMs,
       );

  @visibleForTesting
  MediaKitSubtitleAutoSync.forTesting({
    required MediaKitAudioFeatureTap tap,
    required this.enabled,
    required this.currentPositionMs,
    required this.isPlaying,
    required this.currentOffsetMs,
    required this.applyOffsetMs,
    required this.onNotice,
    Future<void> Function(double scale)? applyScale,
    bool passthroughEnabled = false,
  }) : _passthroughEnabled = passthroughEnabled,
       applyScale = applyScale ?? _noScale,
       _tap = tap;

  static Future<void> _noScale(double scale) async {}

  /// Anchored-audio rungs. Denser than the original 20/45/90/180 so the
  /// first honest verdict lands as early as the gates allow: a pass costs a
  /// few FFTs of a ~8k grid, and the z ≥ 8 narrow gate makes extra looks
  /// statistically free.
  static const List<int> ladderSeconds = <int>[30, 45, 60, 90, 120, 180];

  /// The ladder polls anchored audio this often. It only decides whether a
  /// rung is reachable, so a tight cadence costs nothing and removes up to
  /// eight seconds of dead wait from every rung.
  static const Duration ladderTick = Duration(seconds: 2);

  /// First verification after a sync. Short on purpose: a narrow-tier sync
  /// from twenty seconds of audio should be re-checked against the next
  /// stretch of dialogue soon, not a minute and a half later.
  static const Duration firstVerifyDelay = Duration(seconds: 45);
  static const Duration verifyInterval = Duration(seconds: 120);

  /// Consecutive verify passes that had the audio and the cues to judge yet
  /// found no peak — including the full-width escalation after two — before
  /// the applied sync is WITHDRAWN and the ladder searches again. A sync the
  /// film keeps refusing to confirm is not one to keep; withdrawing costs a
  /// re-search over far more audio than the original pass ever had.
  static const int verifyVetoMisses = 3;

  /// Cues that must fall inside the six-minute verify window for a pass to
  /// be judged at all (and so for a miss to count).
  static const int verifyMinCues = 12;

  /// Residual corrections in the same direction before the controller stops
  /// chasing the drift and measures it: a framerate mismatch shows up as a
  /// sync that keeps needing the same push, and one full-width pass with the
  /// scale hypotheses over the whole history settles it for good.
  static const int driftEscalationResyncs = 2;

  final bool enabled;
  final int Function() currentPositionMs;
  final bool Function() isPlaying;
  final int Function() currentOffsetMs;
  final Future<void> Function(int offsetMs) applyOffsetMs;
  final Future<void> Function(double scale) applyScale;
  final void Function(SubtitleAutoSyncNotice notice) onNotice;

  final MediaKitAudioFeatureTap _tap;
  bool _passthroughEnabled;
  bool _disposed = false;
  bool _running = false;
  bool _ladderDone = true;
  int _ladderIndex = 0;
  int _generation = 0;
  int _alignmentRun = 0;
  int _verifyMisses = 0;
  int _resyncCount = 0;
  int _lastResidualSign = 0;
  SubtitleSyncApplied? _applied;
  String? _subtitlePath;
  List<SubtitleCueSpan> _cues = const <SubtitleCueSpan>[];
  Timer? _ladderTimer;
  Timer? _verifyTimer;
  Future<void> _lifecycle = Future<void>.value();

  bool get available => enabled && !_passthroughEnabled && _tap.installed;
  bool get running => _running;

  /// What this controller last applied for the active subtitle, or null.
  SubtitleSyncApplied? get applied => _applied;

  @visibleForTesting
  int get ladderIndex => _ladderIndex;

  @visibleForTesting
  bool get ladderArmed => !_ladderDone;

  /// [restored] is a sync the host re-applied from memory before calling:
  /// the controller adopts it as its own (so verification guards it and a
  /// later settings echo is recognised) instead of starting a fresh search.
  Future<void> activateSubtitle(String path, {SubtitleSyncApplied? restored}) {
    final generation = ++_generation;
    return _enqueueLifecycle(
      () => _activateSubtitle(path, generation, restored: restored),
    );
  }

  Future<void> _activateSubtitle(
    String path,
    int generation, {
    SubtitleSyncApplied? restored,
  }) async {
    _cancelPasses();
    if (_disposed || generation != _generation) return;
    _subtitlePath = path;
    _cues = const <SubtitleCueSpan>[];
    if (!enabled || _passthroughEnabled) {
      debugPrint(
        'SubtitleAutoSync: activate skipped — enabled=$enabled '
        'passthrough=$_passthroughEnabled',
      );
      return;
    }
    debugPrint('SubtitleAutoSync: activating for $path');

    final parsed = await SubtitleCueParser.parseFile(path);
    if (_disposed || generation != _generation || _subtitlePath != path) return;
    _cues = <SubtitleCueSpan>[
      for (final cue in parsed)
        SubtitleCueSpan(cue.startMs, cue.endMs, cue.text),
    ];
    if (_cues.isEmpty) {
      debugPrint('SubtitleAutoSync: no parseable cues in $path');
      return;
    }
    debugPrint('SubtitleAutoSync: parsed ${_cues.length} cues');

    if (_tap.installed && !_tap.reliable) {
      // The transport condemned itself for the previous subtitle. Its
      // history is worthless; give this subtitle a clean transport rather
      // than a guaranteed decline.
      debugPrint('SubtitleAutoSync: tap was unreliable — reinstalling');
      await _tap.uninstall();
      if (_disposed || generation != _generation) return;
    }
    if (!_tap.installed) {
      final installed = await _tap.install();
      if (!installed) {
        debugPrint(
          'SubtitleAutoSync: tap install failed — auto-sync abandoned',
        );
        return;
      }
      if (_disposed || generation != _generation) {
        await _tap.uninstall();
        return;
      }
      _tap.reset(anchorMs: currentPositionMs());
    } else {
      debugPrint(
        'SubtitleAutoSync: reusing '
        '${(_tap.anchoredDurationMs / 1000).toStringAsFixed(1)}s of '
        'audio already heard',
      );
    }
    // A pre-existing manual/remembered offset gates every ladder tick, so a
    // countdown would promise work that never runs. The ladder still arms —
    // it starts attempting if the offset later returns to zero.
    if (restored != null) {
      debugPrint(
        'SubtitleAutoSync: adopted restored sync ${restored.offsetMs}ms '
        '×${restored.scale.toStringAsFixed(5)} — verifying, not searching',
      );
      _applied = restored;
      _scheduleVerification(initial: true);
      return;
    }
    if (currentOffsetMs() == 0) {
      _notifyListening();
    } else {
      debugPrint(
        'SubtitleAutoSync: listening suppressed — stored offset '
        '${currentOffsetMs()}ms gates the ladder',
      );
    }
    _startLadder();
  }

  void _notifyListening() {
    onNotice(
      const SubtitleAutoSyncNotice(
        SubtitleAutoSyncNoticeKind.listening,
        'Trying to sync subtitles…',
      ),
    );
  }

  /// Synchronous cut-off for a subtitle that is being replaced: nothing
  /// computed for it may land after this returns. Hosts call it BEFORE any
  /// asynchronous work (a memory recall) that precedes [activateSubtitle],
  /// so no stale verdict can reach the player during that gap.
  void abandonSubtitle() {
    _generation++;
    _cancelPasses();
  }

  /// The subtitle went away. Passes stop; the tap stays installed and keeps
  /// listening so the next subtitle — often picked seconds later because
  /// this one was wrong — is judged at once against everything heard.
  Future<void> deactivateSubtitle() {
    _generation++;
    return _enqueueLifecycle(() async {
      _cancelPasses();
      _subtitlePath = null;
      _cues = const <SubtitleCueSpan>[];
    });
  }

  /// A different media item is playing. Feature history from the previous
  /// one would mis-anchor or mis-match anything on the new timeline.
  Future<void> contentChanged() {
    _generation++;
    return _enqueueLifecycle(() async {
      _cancelPasses();
      _subtitlePath = null;
      _cues = const <SubtitleCueSpan>[];
      _tap.reset(anchorMs: currentPositionMs());
    });
  }

  void observePosition(int positionMs) {
    if (_tap.observePosition(positionMs)) {
      // Never apply a calculation made from the pre-seek snapshot. The sync
      // itself is global, so the subtitle session and verification stay live.
      _alignmentRun++;
      _running = false;
    }
  }

  Future<void> setPassthroughEnabled(bool enabled) {
    if (_passthroughEnabled == enabled) return Future<void>.value();
    _passthroughEnabled = enabled;
    final generation = ++_generation;
    return _enqueueLifecycle(() async {
      if (enabled) {
        await _stopCapture(clearSubtitle: false);
        return;
      }
      final path = _subtitlePath;
      if (path != null && this.enabled && !_disposed) {
        await _activateSubtitle(path, generation);
      }
    });
  }

  void audioTrackChanged() {
    if (!available || _subtitlePath == null) return;
    final generation = ++_generation;
    _cancelPasses();
    unawaited(
      _enqueueLifecycle(() async {
        if (_disposed || generation != _generation || !available) return;
        await _tap.resetForAudioTrack(anchorMs: currentPositionMs());
        if (_disposed || generation != _generation || !available) return;
        // Same contract as activation: the restarted listen announces itself
        // so a much later verdict never appears without context.
        if (currentOffsetMs() == 0) _notifyListening();
        _startLadder();
      }),
    );
  }

  /// Manual timing always wins. A value equal to our own applied offset is the
  /// settings callback reflecting our write and leaves verification armed.
  void manualOffsetChanged(int offsetMs) {
    final applied = _applied;
    if (applied != null && offsetMs == applied.offsetMs) return;
    _generation++;
    _cancelPasses();
  }

  Future<void> runNow() => _runAlignment(auto: false);

  /// Stop every pending or in-flight pass and forget what was applied. Does
  /// not touch the tap: history is the content's, not the subtitle's.
  void _cancelPasses() {
    _ladderTimer?.cancel();
    _verifyTimer?.cancel();
    _ladderTimer = null;
    _verifyTimer = null;
    _ladderDone = true;
    _alignmentRun++;
    _running = false;
    _applied = null;
    _verifyMisses = 0;
    _resyncCount = 0;
    _lastResidualSign = 0;
  }

  void _startLadder() {
    _ladderTimer?.cancel();
    _verifyTimer?.cancel();
    _ladderIndex = 0;
    _ladderDone = false;
    // First look right away: with history on hand (subtitle switch, audio
    // heard before the subtitle loaded) there is nothing to wait for.
    _ladderTickNow();
    if (_ladderDone) return;
    _ladderTimer = Timer.periodic(ladderTick, (_) => _ladderTickNow());
  }

  void _ladderTickNow() {
    if (_ladderDone || _disposed || _subtitlePath == null) return;
    if (_running || currentOffsetMs() != 0) return;
    // Below the offset gate on purpose: a manually-offset session never
    // announced auto-sync, so it must not surface a failure for it either.
    if (!_tap.reliable) {
      // The transport demonstrably lost audio; any alignment would be
      // against a time-warped feature timeline. Decline for good.
      _ladderDone = true;
      _ladderTimer?.cancel();
      onNotice(
        const SubtitleAutoSyncNotice(
          SubtitleAutoSyncNoticeKind.failed,
          'Couldn’t analyze this stream’s audio reliably.',
        ),
      );
      return;
    }
    if (_ladderIndex >= ladderSeconds.length) return;
    final anchoredMs = _tap.anchoredDurationMs;
    if (anchoredMs < ladderSeconds[_ladderIndex] * 1000) return;
    // Audio may already cover several rungs (a subtitle switched late in
    // the film): take the highest rung the history satisfies so the first
    // attempt is the strongest one available, not the weakest.
    while (_ladderIndex < ladderSeconds.length &&
        anchoredMs >= ladderSeconds[_ladderIndex] * 1000) {
      _ladderIndex++;
    }
    debugPrint(
      'SubtitleAutoSync: ladder attempt $_ladderIndex/${ladderSeconds.length} '
      'with ${(anchoredMs / 1000).toStringAsFixed(1)}s anchored',
    );
    unawaited(_runAlignment(auto: true));
  }

  Future<void> _runAlignment({required bool auto}) async {
    if (_disposed || _running || !available || _cues.isEmpty) return;
    if (!_tap.reliable) return;
    final path = _subtitlePath;
    if (path == null) return;
    final generation = _generation;
    final run = ++_alignmentRun;
    final segments = _tap.snapshot();
    _running = true;
    onNotice(
      const SubtitleAutoSyncNotice(
        SubtitleAutoSyncNoticeKind.checking,
        'Checking subtitle timing…',
      ),
    );
    SubtitleAlignResult result;
    try {
      result = await compute(
        _alignInBackground,
        _AlignRequest(segments: segments, cues: _cues, tiered: true),
      );
    } catch (error) {
      debugPrint('SubtitleAutoSync: alignment failed: $error');
      result = const SubtitleAlignNoMatch(analyzedSec: 0);
    } finally {
      if (run == _alignmentRun) _running = false;
    }
    if (_disposed ||
        generation != _generation ||
        run != _alignmentRun ||
        path != _subtitlePath ||
        // The tap may have been distrusted while the isolate computed; a
        // verdict from a just-distrusted timeline must never be applied.
        !_tap.reliable) {
      return;
    }

    switch (result) {
      case SubtitleAlignSynced():
        _ladderDone = true;
        _ladderTimer?.cancel();
        debugPrint(
          'SubtitleAutoSync: synced ${result.offsetMs}ms '
          '(z ${result.zPeak.toStringAsFixed(1)}, psr '
          '${result.confidence.toStringAsFixed(1)}, ${result.analyzedSec}s)',
        );
        await _applySync(offsetMs: result.offsetMs, scale: 1);
        if (_disposed || generation != _generation) return;
        onNotice(
          SubtitleAutoSyncNotice(
            SubtitleAutoSyncNoticeKind.synced,
            'Subtitles synced ${_formatOffset(result.offsetMs)}',
          ),
        );
        _scheduleVerification(initial: true);
      case SubtitleAlignDrift():
        _ladderDone = true;
        _ladderTimer?.cancel();
        debugPrint(
          'SubtitleAutoSync: drift corrected ×'
          '${result.scale.toStringAsFixed(5)} ${result.offsetMs}ms '
          '(z ${result.zPeak.toStringAsFixed(1)}, ${result.analyzedSec}s)',
        );
        await _applySync(offsetMs: result.offsetMs, scale: result.scale);
        if (_disposed || generation != _generation) return;
        onNotice(
          SubtitleAutoSyncNotice(
            SubtitleAutoSyncNoticeKind.synced,
            'Subtitles synced ${_formatOffset(result.offsetMs)} '
            '(framerate drift corrected)',
          ),
        );
        _scheduleVerification(initial: true);
      case SubtitleAlignNoMatch() || SubtitleAlignNotEnoughAudio():
        if (auto && _ladderIndex < ladderSeconds.length) {
          // Intermediate rung declined silently: hand the UI back its
          // listening face so "checking" reverts when the pass truly ended.
          onNotice(
            const SubtitleAutoSyncNotice(
              SubtitleAutoSyncNoticeKind.stillListening,
              'No verdict yet; still listening.',
            ),
          );
        }
        if (!auto || _ladderIndex >= ladderSeconds.length) {
          _ladderDone = true;
          _ladderTimer?.cancel();
          onNotice(
            SubtitleAutoSyncNotice(
              SubtitleAutoSyncNoticeKind.failed,
              auto
                  ? 'Couldn’t sync automatically. Try another subtitle or adjust timing.'
                  : 'No confident match yet. Keep watching, then try again.',
            ),
          );
        }
    }
  }

  /// Scale first, then offset: the offset callback is the one whose settings
  /// echo reaches [manualOffsetChanged], and [_applied] must already describe
  /// the full transform by then so the echo is recognised as our own.
  ///
  /// Both host callbacks await preference writes, so a subtitle switch can
  /// land between them; each is guarded so a stale half-transform is never
  /// written under the next subtitle's identity. Returns false if abandoned.
  Future<bool> _applySync({required int offsetMs, required double scale}) async {
    final generation = _generation;
    _applied = (offsetMs: offsetMs, scale: scale);
    _verifyMisses = 0;
    await applyScale(scale);
    if (_disposed || generation != _generation) return false;
    await applyOffsetMs(offsetMs);
    return !_disposed && generation == _generation;
  }

  void _scheduleVerification({bool initial = false}) {
    _verifyTimer?.cancel();
    _verifyTimer = Timer(initial ? firstVerifyDelay : verifyInterval, _verify);
  }

  /// Runs one verification pass now (tests drive the timer-less path).
  @visibleForTesting
  Future<void> verifyNow() => _verify();

  Future<void> _verify() async {
    final applied = _applied;
    final path = _subtitlePath;
    // An unreliable tap ends verification outright: residuals computed from
    // a distorted timeline would "correct" a good offset into a bad one.
    if (!_tap.reliable) return;
    if (_disposed ||
        applied == null ||
        path == null ||
        _running ||
        !available ||
        !isPlaying()) {
      if (!_disposed && applied != null) _scheduleVerification();
      return;
    }
    if (currentOffsetMs() != applied.offsetMs) {
      manualOffsetChanged(currentOffsetMs());
      return;
    }
    final position = currentPositionMs();
    final windowStart = position - 360000;
    // A window the subtitle itself says is dialogue-free (credits, a
    // montage, a long action beat) cannot confirm OR refute anything; it
    // must not count towards the veto. Judged on the cues as displayed.
    var cuesInWindow = 0;
    for (final cue in _cues) {
      final start = (cue.startMs * applied.scale).round() + applied.offsetMs;
      if (start >= windowStart && start <= position + 10000) cuesInWindow++;
    }
    if (cuesInWindow < verifyMinCues) {
      debugPrint(
        'SubtitleAutoSync: verify skipped — $cuesInWindow cues in window',
      );
      _scheduleVerification();
      return;
    }
    final recent = _tap
        .snapshot()
        .where((segment) {
          return segment.anchorMs + segment.durationMs >= windowStart &&
              segment.anchorMs <= position + 10000;
        })
        .toList(growable: false);
    final recentDuration = recent.fold<double>(
      0,
      (sum, segment) => sum + segment.durationMs,
    );
    if (recentDuration < 30000) {
      _scheduleVerification();
      return;
    }

    final generation = _generation;
    final run = ++_alignmentRun;
    _running = true;
    SubtitleAlignResult result;
    try {
      // Cues ride in pre-transformed by what is applied, so a still-correct
      // sync correlates at lag 0 and any confident peak IS the residual.
      final centered = <SubtitleCueSpan>[
        for (final cue in _cues)
          SubtitleCueSpan(
            (cue.startMs * applied.scale).round() + applied.offsetMs,
            (cue.endMs * applied.scale).round() + applied.offsetMs,
            cue.text,
          ),
      ];
      result = await compute(
        _alignInBackground,
        _AlignRequest(
          segments: recent,
          cues: centered,
          residual: _verifyMisses < 2,
        ),
      );
    } catch (error) {
      debugPrint('SubtitleAutoSync: verification failed: $error');
      result = const SubtitleAlignNoMatch(analyzedSec: 0);
    } finally {
      if (run == _alignmentRun) _running = false;
    }
    if (_disposed ||
        generation != _generation ||
        run != _alignmentRun ||
        path != _subtitlePath ||
        // Distrusted mid-compute: discard the residual and stop verifying —
        // "correcting" a good offset from a distorted timeline is the one
        // failure the feature must never have.
        !_tap.reliable) {
      if (!_disposed &&
          _tap.reliable &&
          generation == _generation &&
          path == _subtitlePath &&
          _applied == applied) {
        _scheduleVerification();
      }
      return;
    }

    if (result case SubtitleAlignSynced()) {
      _verifyMisses = 0;
      if (result.offsetMs.abs() > 400) {
        final next = applied.offsetMs + result.offsetMs;
        final sign = result.offsetMs.sign;
        _resyncCount = sign == _lastResidualSign ? _resyncCount + 1 : 1;
        _lastResidualSign = sign;
        debugPrint(
          'SubtitleAutoSync: verify re-synced ${applied.offsetMs} -> $next '
          '(residual ${result.offsetMs}ms, z ${result.zPeak.toStringAsFixed(1)}, '
          'same-direction run $_resyncCount)',
        );
        await _applySync(offsetMs: next, scale: applied.scale);
        if (_disposed || generation != _generation) return;
        onNotice(
          SubtitleAutoSyncNotice(
            SubtitleAutoSyncNoticeKind.resynced,
            'Subtitles re-synced ${_formatOffset(next)}',
          ),
        );
        if (_resyncCount >= driftEscalationResyncs && applied.scale == 1) {
          await _escalateToDrift(generation, path);
          if (_disposed || generation != _generation) return;
        }
      } else {
        _resyncCount = 0;
        _lastResidualSign = 0;
        debugPrint(
          'SubtitleAutoSync: verify confirmed ${applied.offsetMs}ms '
          '(residual ${result.offsetMs}ms)',
        );
      }
    } else if (result is SubtitleAlignNoMatch) {
      _verifyMisses++;
      debugPrint(
        'SubtitleAutoSync: verify miss $_verifyMisses '
        '(best ${result.bestOffsetMs}ms z ${result.bestZ.toStringAsFixed(1)})',
      );
      if (_verifyMisses >= verifyVetoMisses) {
        await _reauditSync(generation, path, applied);
        return;
      }
    }
    _scheduleVerification();
  }

  /// The recent windows have refused to confirm the applied sync often
  /// enough. Before taking anything back, re-judge it from the WHOLE
  /// history (far more audio than the pass that produced it): the same
  /// verdict keeps it — quietly, so a scored stretch never makes a correct
  /// sync flicker — a different confident verdict replaces it, and only no
  /// verdict at all withdraws it and re-arms the ladder.
  Future<void> _reauditSync(
    int generation,
    String path,
    SubtitleSyncApplied applied,
  ) async {
    if (_running) {
      _scheduleVerification();
      return;
    }
    debugPrint('SubtitleAutoSync: re-auditing after $_verifyMisses misses');
    final run = ++_alignmentRun;
    _running = true;
    SubtitleAlignResult result;
    try {
      result = await compute(
        _alignInBackground,
        _AlignRequest(segments: _tap.snapshot(), cues: _cues, tiered: true),
      );
    } catch (error) {
      debugPrint('SubtitleAutoSync: re-audit failed: $error');
      result = const SubtitleAlignNoMatch(analyzedSec: 0);
    } finally {
      if (run == _alignmentRun) _running = false;
    }
    if (_disposed ||
        generation != _generation ||
        run != _alignmentRun ||
        path != _subtitlePath ||
        !_tap.reliable ||
        _applied != applied) {
      return;
    }
    _verifyMisses = 0;
    _resyncCount = 0;
    _lastResidualSign = 0;
    switch (result) {
      case SubtitleAlignSynced()
          when applied.scale == 1 &&
              (result.offsetMs - applied.offsetMs).abs() <= 400:
        debugPrint('SubtitleAutoSync: re-audit confirmed ${applied.offsetMs}ms');
        _scheduleVerification();
      case SubtitleAlignSynced():
        debugPrint(
          'SubtitleAutoSync: re-audit moved ${applied.offsetMs} -> '
          '${result.offsetMs}ms',
        );
        await _applySync(offsetMs: result.offsetMs, scale: 1);
        if (_disposed || generation != _generation) return;
        onNotice(
          SubtitleAutoSyncNotice(
            SubtitleAutoSyncNoticeKind.resynced,
            'Subtitles re-synced ${_formatOffset(result.offsetMs)}',
          ),
        );
        _scheduleVerification();
      case SubtitleAlignDrift():
        await _applySync(offsetMs: result.offsetMs, scale: result.scale);
        if (_disposed || generation != _generation) return;
        onNotice(
          SubtitleAutoSyncNotice(
            SubtitleAutoSyncNoticeKind.resynced,
            'Subtitles re-synced ${_formatOffset(result.offsetMs)} '
            '(framerate drift corrected)',
          ),
        );
        _scheduleVerification();
      case SubtitleAlignNoMatch() || SubtitleAlignNotEnoughAudio():
        debugPrint('SubtitleAutoSync: sync withdrawn — re-audit found nothing');
        await _applySync(offsetMs: 0, scale: 1);
        if (_disposed || generation != _generation || path != _subtitlePath) {
          return;
        }
        _applied = null;
        _startLadder();
    }
  }

  /// Two same-direction corrections in a row: measure the drift over the
  /// whole history instead of chasing it. Applies only a confident
  /// framerate verdict; a plain-offset answer changes nothing (the residual
  /// pass already keeps the offset right).
  Future<void> _escalateToDrift(int generation, String path) async {
    final applied = _applied;
    if (applied == null || _running) return;
    final segments = _tap.snapshot();
    var spanStart = 1 << 62;
    var spanEnd = -(1 << 62);
    for (final segment in segments) {
      spanStart = math.min(spanStart, segment.anchorMs);
      spanEnd = math.max(
        spanEnd,
        segment.anchorMs + segment.durationMs.round(),
      );
    }
    if (segments.isEmpty || spanEnd - spanStart < SubtitleAligner.driftMinSpanMs) {
      debugPrint('SubtitleAutoSync: drift check skipped — span too short');
      return;
    }
    final run = ++_alignmentRun;
    _running = true;
    SubtitleAlignResult result;
    try {
      result = await compute(
        _alignInBackground,
        _AlignRequest(segments: segments, cues: _cues, drift: true),
      );
    } catch (error) {
      debugPrint('SubtitleAutoSync: drift check failed: $error');
      result = const SubtitleAlignNoMatch(analyzedSec: 0);
    } finally {
      if (run == _alignmentRun) _running = false;
    }
    if (_disposed ||
        generation != _generation ||
        run != _alignmentRun ||
        path != _subtitlePath ||
        !_tap.reliable ||
        _applied == null) {
      return;
    }
    if (result case SubtitleAlignDrift()) {
      debugPrint(
        'SubtitleAutoSync: drift measured ×${result.scale.toStringAsFixed(5)} '
        '${result.offsetMs}ms (z ${result.zPeak.toStringAsFixed(1)})',
      );
      await _applySync(offsetMs: result.offsetMs, scale: result.scale);
      if (_disposed || generation != _generation) return;
      _resyncCount = 0;
      _lastResidualSign = 0;
      onNotice(
        SubtitleAutoSyncNotice(
          SubtitleAutoSyncNoticeKind.resynced,
          'Subtitles re-synced ${_formatOffset(result.offsetMs)} '
          '(framerate drift corrected)',
        ),
      );
    } else {
      debugPrint('SubtitleAutoSync: drift check found no framerate mismatch');
    }
  }

  Future<void> _stopCapture({required bool clearSubtitle}) async {
    _cancelPasses();
    await _tap.uninstall();
    _tap.reset();
    if (clearSubtitle) {
      _subtitlePath = null;
      _cues = const <SubtitleCueSpan>[];
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    await _enqueueLifecycle(() => _stopCapture(clearSubtitle: true));
    await _tap.dispose();
  }

  Future<void> _enqueueLifecycle(Future<void> Function() operation) {
    final next = _lifecycle.then((_) async {
      try {
        await operation();
      } catch (error, stackTrace) {
        debugPrint('SubtitleAutoSync: lifecycle operation failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    });
    _lifecycle = next;
    return next;
  }

  static String _formatOffset(int milliseconds) {
    final sign = milliseconds >= 0 ? '+' : '−';
    return '$sign${(milliseconds.abs() / 1000).toStringAsFixed(1)}s';
  }
}
