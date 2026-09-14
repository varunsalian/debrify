import 'dart:async';
import 'package:flutter/widgets.dart';
import 'trailer_engine.dart';

/// Serializes ambient decoders, including Exo (whose hardware codec pool is
/// separate from media_kit's VideoOutputLease). A successor waits for native
/// disposal and any open that was still creating an orphaned native player.
class SerializedTrailerEngine implements TrailerEngine {
  SerializedTrailerEngine._(this._engine, this._released);
  final TrailerEngine _engine;
  final Completer<void> _released;
  static Completer<void>? _holder;
  Future<void>? _opening;
  Future<void>? _disposal;

  static Future<TrailerEngine?> create(
    Future<TrailerEngine> Function() factory,
    bool Function() isCurrent,
  ) async {
    while (_holder != null) {
      await _holder!.future;
      if (!isCurrent()) return null;
    }
    if (!isCurrent()) return null;
    final held = Completer<void>();
    _holder = held;
    try {
      return SerializedTrailerEngine._(await factory(), held);
    } catch (_) {
      if (identical(_holder, held)) _holder = null;
      held.complete();
      rethrow;
    }
  }

  @override
  bool get rendersUnderlay => _engine.rendersUnderlay;
  @override
  Stream<bool> get playingStream => _engine.playingStream;
  @override
  Stream<Duration> get positionStream => _engine.positionStream;
  @override
  Stream<Duration> get durationStream => _engine.durationStream;
  @override
  Stream<void> get errorStream => _engine.errorStream;
  @override
  Future<void> get firstFrameRendered => _engine.firstFrameRendered;
  @override
  Future<void> open({
    required String videoUrl,
    String? audioUrl,
    required double volume,
    required bool loop,
    Map<String, String>? httpHeaders,
  }) {
    return _opening = _engine.open(
      videoUrl: videoUrl,
      audioUrl: audioUrl,
      volume: volume,
      loop: loop,
      httpHeaders: httpHeaders,
    );
  }

  @override
  Future<void> setVolume(double volume) => _engine.setVolume(volume);
  @override
  Future<void> seek(Duration position) => _engine.seek(position);
  @override
  Future<void> play() => _engine.play();
  @override
  Future<void> pause() => _engine.pause();
  @override
  void detach() => _engine.detach();
  @override
  Widget buildVideo({required BoxFit fit, bool revealed = true}) =>
      _engine.buildVideo(fit: fit, revealed: revealed);
  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _engine.detach();
    try {
      // Start release immediately; open may require disposal to unblock.
      final disposing = _engine.dispose();
      await Future.wait<void>([
        disposing,
        if (_opening != null) _opening!.catchError((Object _) {}),
      ]);
    } finally {
      if (identical(_holder, _released)) _holder = null;
      if (!_released.isCompleted) _released.complete();
    }
  }
}
