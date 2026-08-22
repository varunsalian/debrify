import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'media_kit_audio_feature_tap.dart';
import 'subtitle_aligner.dart';
import 'subtitle_cue_parser.dart';

enum SubtitleAutoSyncNoticeKind { listening, synced, resynced, failed }

class SubtitleAutoSyncNotice {
  final SubtitleAutoSyncNoticeKind kind;
  final String message;

  const SubtitleAutoSyncNotice(this.kind, this.message);
}

class _AlignRequest {
  final List<AudioFeatureSegment> segments;
  final List<SubtitleCueSpan> cues;
  final bool tiered;
  final bool residual;

  const _AlignRequest({
    required this.segments,
    required this.cues,
    this.tiered = false,
    this.residual = false,
  });
}

SubtitleAlignResult _alignInBackground(_AlignRequest request) {
  if (request.tiered) {
    return SubtitleAligner.alignTiered(request.segments, request.cues);
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
  return SubtitleAligner.align(request.segments, request.cues);
}

/// Owns the hands-free attempt ladder for one MediaKit player instance.
///
/// All playback-facing operations fail closed: if the passive filter cannot
/// be installed, metadata stops, parsing fails, or the player is being torn
/// down, the controller abandons auto-sync and never changes subtitle delay.
class MediaKitSubtitleAutoSync {
  MediaKitSubtitleAutoSync({
    required mk.NativePlayer player,
    required this.enabled,
    required this.currentPositionMs,
    required this.isPlaying,
    required this.currentOffsetMs,
    required this.applyOffsetMs,
    required this.onNotice,
    bool passthroughEnabled = false,
  }) : _passthroughEnabled = passthroughEnabled,
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
    bool passthroughEnabled = false,
  }) : _passthroughEnabled = passthroughEnabled,
       _tap = tap;

  static const List<int> _ladderSeconds = <int>[20, 45, 90, 180];

  final bool enabled;
  final int Function() currentPositionMs;
  final bool Function() isPlaying;
  final int Function() currentOffsetMs;
  final Future<void> Function(int offsetMs) applyOffsetMs;
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
  int? _appliedOffsetMs;
  String? _subtitlePath;
  List<SubtitleCueSpan> _cues = const <SubtitleCueSpan>[];
  Timer? _ladderTimer;
  Timer? _verifyTimer;
  Future<void> _lifecycle = Future<void>.value();

  bool get available => enabled && !_passthroughEnabled && _tap.installed;
  bool get running => _running;

  Future<void> activateSubtitle(String path) {
    final generation = ++_generation;
    return _enqueueLifecycle(() => _activateSubtitle(path, generation));
  }

  Future<void> _activateSubtitle(String path, int generation) async {
    await _stopCapture(clearSubtitle: false);
    if (_disposed || generation != _generation) return;
    _subtitlePath = path;
    _cues = const <SubtitleCueSpan>[];
    _appliedOffsetMs = null;
    _verifyMisses = 0;
    if (!enabled || _passthroughEnabled) return;

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
    final installed = await _tap.install();
    if (!installed) return;
    if (_disposed || generation != _generation) {
      await _tap.uninstall();
      return;
    }
    _tap.reset(anchorMs: currentPositionMs());
    _startLadder();
  }

  Future<void> deactivateSubtitle() {
    _generation++;
    return _enqueueLifecycle(() => _stopCapture(clearSubtitle: true));
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
    _alignmentRun++;
    _running = false;
    _ladderDone = true;
    _ladderTimer?.cancel();
    _verifyTimer?.cancel();
    _appliedOffsetMs = null;
    _verifyMisses = 0;
    unawaited(
      _enqueueLifecycle(() async {
        if (_disposed || generation != _generation || !available) return;
        await _tap.resetForAudioTrack(anchorMs: currentPositionMs());
        if (_disposed || generation != _generation || !available) return;
        _startLadder();
      }),
    );
  }

  /// Manual timing always wins. A value equal to our own applied offset is the
  /// settings callback reflecting our write and leaves verification armed.
  void manualOffsetChanged(int offsetMs) {
    final applied = _appliedOffsetMs;
    if (applied != null && offsetMs == applied) return;
    _generation++;
    _alignmentRun++;
    _running = false;
    _ladderDone = true;
    _ladderTimer?.cancel();
    _verifyTimer?.cancel();
    _appliedOffsetMs = null;
  }

  Future<void> runNow() => _runAlignment(auto: false);

  void _startLadder() {
    _ladderTimer?.cancel();
    _verifyTimer?.cancel();
    _ladderIndex = 0;
    _ladderDone = false;
    _ladderTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (_ladderDone || _disposed || _subtitlePath == null) return;
      if (_running || currentOffsetMs() != 0) return;
      if (_ladderIndex >= _ladderSeconds.length) return;
      if (_tap.anchoredDurationMs < _ladderSeconds[_ladderIndex] * 1000) {
        return;
      }
      _ladderIndex++;
      unawaited(_runAlignment(auto: true));
    });
  }

  Future<void> _runAlignment({required bool auto}) async {
    if (_disposed || _running || !available || _cues.isEmpty) return;
    final path = _subtitlePath;
    if (path == null) return;
    final generation = _generation;
    final run = ++_alignmentRun;
    final segments = _tap.snapshot();
    _running = true;
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
        path != _subtitlePath) {
      return;
    }

    switch (result) {
      case SubtitleAlignSynced():
        _ladderDone = true;
        _ladderTimer?.cancel();
        await applyOffsetMs(result.offsetMs);
        if (_disposed || generation != _generation) return;
        _appliedOffsetMs = result.offsetMs;
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
        onNotice(
          const SubtitleAutoSyncNotice(
            SubtitleAutoSyncNoticeKind.failed,
            'Subtitle timing drifts through this video. Try another track.',
          ),
        );
      case SubtitleAlignNoMatch() || SubtitleAlignNotEnoughAudio():
        if (!auto || _ladderIndex >= _ladderSeconds.length) {
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

  void _scheduleVerification({bool initial = false}) {
    _verifyTimer?.cancel();
    _verifyTimer = Timer(Duration(seconds: initial ? 90 : 120), _verify);
  }

  Future<void> _verify() async {
    final applied = _appliedOffsetMs;
    final path = _subtitlePath;
    if (_disposed ||
        applied == null ||
        path == null ||
        _running ||
        !available ||
        !isPlaying()) {
      if (!_disposed && applied != null) _scheduleVerification();
      return;
    }
    if (currentOffsetMs() != applied) {
      manualOffsetChanged(currentOffsetMs());
      return;
    }
    final position = currentPositionMs();
    final windowStart = position - 360000;
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
      final centered = <SubtitleCueSpan>[
        for (final cue in _cues)
          SubtitleCueSpan(cue.startMs + applied, cue.endMs + applied, cue.text),
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
        path != _subtitlePath) {
      if (!_disposed &&
          generation == _generation &&
          path == _subtitlePath &&
          _appliedOffsetMs == applied) {
        _scheduleVerification();
      }
      return;
    }

    if (result case SubtitleAlignSynced()) {
      _verifyMisses = 0;
      if (result.offsetMs.abs() > 400) {
        final next = applied + result.offsetMs;
        await applyOffsetMs(next);
        if (_disposed || generation != _generation) return;
        _appliedOffsetMs = next;
        onNotice(
          SubtitleAutoSyncNotice(
            SubtitleAutoSyncNoticeKind.resynced,
            'Subtitles re-synced ${_formatOffset(next)}',
          ),
        );
      }
    } else if (result is SubtitleAlignNoMatch) {
      _verifyMisses++;
    }
    _scheduleVerification();
  }

  Future<void> _stopCapture({required bool clearSubtitle}) async {
    _ladderTimer?.cancel();
    _verifyTimer?.cancel();
    _ladderTimer = null;
    _verifyTimer = null;
    _ladderDone = true;
    _alignmentRun++;
    _running = false;
    _appliedOffsetMs = null;
    _verifyMisses = 0;
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
