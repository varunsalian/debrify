/// Pushes player state to the system now-playing surface only when it would
/// look different there.
library;

import 'dart:async';

import 'package:debrify/features/now_playing/models/now_playing_models.dart';

/// Where a [NowPlayingPublisher] sends its updates.
abstract interface class NowPlayingSink {
  Future<void> update(NowPlayingInfo info);

  Future<void> clear();
}

/// How far the extrapolated position may drift before the system is told.
const _repositionTolerance = Duration(seconds: 2);

final class NowPlayingPublisher {
  NowPlayingPublisher(this._sink, {DateTime Function() clock = DateTime.now})
    : _clock = clock;

  final NowPlayingSink _sink;
  final DateTime Function() _clock;

  NowPlayingInfo? _last;
  DateTime? _lastPush;

  /// Reports [info], pushing it only when the system's view would change.
  ///
  /// Pushes when: nothing was pushed yet (or after [clear]); title, subtitle,
  /// duration, isLive, canGoNext or canGoPrevious changed; effectiveRate
  /// changed; or [NowPlayingInfo.position] differs by more than two seconds
  /// from the position the system extrapolates (last pushed position plus
  /// time since that push times the last pushed effectiveRate). Otherwise
  /// does nothing.
  void report(NowPlayingInfo info) {
    final now = _clock();
    if (!_wouldLookDifferent(info, now)) return;
    _last = info;
    _lastPush = now;
    unawaited(_sink.update(info).catchError((Object _) {}));
  }

  /// Clears once if anything was pushed since the last clear; later clears
  /// do nothing.
  void clear() {
    if (_last == null) return;
    _last = null;
    _lastPush = null;
    unawaited(_sink.clear().catchError((Object _) {}));
  }

  bool _wouldLookDifferent(NowPlayingInfo info, DateTime now) {
    final previous = _last;
    final pushedAt = _lastPush;
    if (previous == null || pushedAt == null) return true;
    if (previous.title != info.title ||
        previous.subtitle != info.subtitle ||
        previous.duration != info.duration ||
        previous.isLive != info.isLive ||
        previous.canGoNext != info.canGoNext ||
        previous.canGoPrevious != info.canGoPrevious ||
        previous.effectiveRate != info.effectiveRate) {
      return true;
    }
    final elapsedMicros = now.difference(pushedAt).inMicroseconds;
    final extrapolated =
        previous.position.inMicroseconds +
        (elapsedMicros * previous.effectiveRate).round();
    final drift = info.position.inMicroseconds - extrapolated;
    return drift.abs() > _repositionTolerance.inMicroseconds;
  }
}
