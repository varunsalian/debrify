import 'dart:async';

import 'package:flutter/foundation.dart';

/// The small portion of playback state that changes continuously while a
/// video is running.
///
/// Keeping it outside VideoPlayerScreen's State prevents a position event from
/// rebuilding the video surface, overlays, guides and every hidden control.
@immutable
class PlaybackUiClockValue {
  const PlaybackUiClockValue({
    required this.position,
    required this.duration,
    required this.generation,
  });

  const PlaybackUiClockValue.zero()
    : position = Duration.zero,
      duration = Duration.zero,
      generation = 0;

  final Duration position;
  final Duration duration;
  final int generation;

  PlaybackUiClockValue copyWith({
    Duration? position,
    Duration? duration,
    int? generation,
  }) {
    return PlaybackUiClockValue(
      position: position ?? this.position,
      duration: duration ?? this.duration,
      generation: generation ?? this.generation,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlaybackUiClockValue &&
        other.position == position &&
        other.duration == duration &&
        other.generation == generation;
  }

  @override
  int get hashCode => Object.hash(position, duration, generation);
}

/// Publishes a throttled clock to the progress/time widgets while retaining
/// the raw position internally.
///
/// [updatePosition] may be called at mpv's native event rate. Subscribers see
/// at most one position update per [interval] during continuous playback. No
/// timer or notification remains active while the controls are hidden.
class PlaybackUiClockController extends ValueNotifier<PlaybackUiClockValue> {
  PlaybackUiClockController({
    this.interval = const Duration(milliseconds: 250),
    bool visible = true,
  }) : assert(interval > Duration.zero),
       _visible = visible,
       super(const PlaybackUiClockValue.zero());

  final Duration interval;

  bool _visible;
  Timer? _windowTimer;
  bool _positionDirty = false;
  Duration _rawPosition = Duration.zero;
  Duration _rawDuration = Duration.zero;
  int _generation = 0;

  bool get visible => _visible;
  int get generation => _generation;
  Duration get rawPosition => _rawPosition;
  Duration get rawDuration => _rawDuration;

  /// Starts a new media clock before the corresponding player open.
  ///
  /// Callers may retain the returned generation and pass it back with an async
  /// update. An update from an older media item is ignored.
  int beginMedia() {
    _generation++;
    _rawPosition = Duration.zero;
    _rawDuration = Duration.zero;
    _positionDirty = false;
    _windowTimer?.cancel();
    _windowTimer = null;
    if (_visible) _publishAndOpenWindow();
    return _generation;
  }

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _positionDirty = false;
    _windowTimer?.cancel();
    _windowTimer = null;
    if (visible) _publishAndOpenWindow();
  }

  void updatePosition(
    Duration position, {
    int? generation,
    bool immediate = false,
  }) {
    if (generation != null && generation != _generation) return;
    _rawPosition = position;
    if (!_visible) return;

    if (immediate) {
      _positionDirty = false;
      _windowTimer?.cancel();
      _windowTimer = null;
      _publishAndOpenWindow();
      return;
    }

    if (_windowTimer == null) {
      _publishAndOpenWindow();
    } else {
      _positionDirty = true;
    }
  }

  /// Duration changes are rare item-level events, so they publish immediately
  /// instead of waiting behind the position throttle.
  void updateDuration(Duration duration, {int? generation}) {
    if (generation != null && generation != _generation) return;
    _rawDuration = duration;
    if (!_visible) return;
    _positionDirty = false;
    _windowTimer?.cancel();
    _windowTimer = null;
    _publishAndOpenWindow();
  }

  void _publishAndOpenWindow() {
    value = PlaybackUiClockValue(
      position: _rawPosition,
      duration: _rawDuration,
      generation: _generation,
    );
    _windowTimer = Timer(interval, _onWindowElapsed);
  }

  void _onWindowElapsed() {
    _windowTimer = null;
    if (!_visible || !_positionDirty) return;
    _positionDirty = false;
    _publishAndOpenWindow();
  }

  @override
  void dispose() {
    _windowTimer?.cancel();
    _windowTimer = null;
    super.dispose();
  }
}
