/// Data passed to the platform's now-playing surface, and the commands that
/// come back from it. Pure data: no plugin or platform imports.
library;

import 'package:flutter/foundation.dart';

/// A snapshot of playback, shaped for the system media UI.
@immutable
final class NowPlayingInfo {
  const NowPlayingInfo({
    required this.title,
    this.subtitle,
    required this.duration,
    required this.position,
    required this.playing,
    this.rate = 1.0,
    this.isLive = false,
    this.canGoNext = false,
    this.canGoPrevious = false,
  });

  final String title;
  final String? subtitle;

  /// Length of the item; [Duration.zero] for live or unknown-length streams.
  final Duration duration;
  final Duration position;
  final bool playing;

  /// Playback multiplier (1.0 normal, 1.5 fast-forward, ...).
  final double rate;
  final bool isLive;
  final bool canGoNext;
  final bool canGoPrevious;

  /// Rate the system should extrapolate with: [rate] while playing, 0 while
  /// paused.
  double get effectiveRate => playing ? rate : 0;

  /// The wire format sent to the platform side. `rate` carries
  /// [effectiveRate] so a paused item never extrapolates forward.
  Map<String, Object?> toMap() => {
    'title': title,
    'subtitle': subtitle,
    'durationMs': duration.inMilliseconds,
    'positionMs': position.inMilliseconds,
    'playing': playing,
    'rate': effectiveRate,
    'isLive': isLive,
    'canGoNext': canGoNext,
    'canGoPrevious': canGoPrevious,
  };

  @override
  bool operator ==(Object other) =>
      other is NowPlayingInfo &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.duration == duration &&
      other.position == position &&
      other.playing == playing &&
      other.rate == rate &&
      other.isLive == isLive &&
      other.canGoNext == canGoNext &&
      other.canGoPrevious == canGoPrevious;

  @override
  int get hashCode => Object.hash(
    title,
    subtitle,
    duration,
    position,
    playing,
    rate,
    isLive,
    canGoNext,
    canGoPrevious,
  );
}

/// Remote-control style commands raised by the platform.
enum NowPlayingCommandType {
  play,
  pause,
  toggle,
  skipForward,
  skipBackward,
  seekTo,
  next,
  previous,
}

/// A command received from the platform side.
@immutable
final class NowPlayingCommand {
  const NowPlayingCommand(this.type, {this.position});

  final NowPlayingCommandType type;

  /// Only set for [NowPlayingCommandType.seekTo].
  final Duration? position;

  static const _names = {
    'play': NowPlayingCommandType.play,
    'pause': NowPlayingCommandType.pause,
    'toggle': NowPlayingCommandType.toggle,
    'skipForward': NowPlayingCommandType.skipForward,
    'skipBackward': NowPlayingCommandType.skipBackward,
    'seekTo': NowPlayingCommandType.seekTo,
    'next': NowPlayingCommandType.next,
    'previous': NowPlayingCommandType.previous,
  };

  /// Parses {'type': 'play'|..., 'positionMs': int?}; null for unknown or
  /// malformed input or a seekTo without a non-negative positionMs.
  static NowPlayingCommand? fromMap(Object? map) {
    if (map is! Map) return null;
    final type = _names[map['type']];
    if (type == null) return null;
    if (type == NowPlayingCommandType.seekTo) {
      final ms = map['positionMs'];
      if (ms is! int || ms < 0) return null;
      return NowPlayingCommand(type, position: Duration(milliseconds: ms));
    }
    return NowPlayingCommand(type);
  }

  @override
  bool operator ==(Object other) =>
      other is NowPlayingCommand &&
      other.type == type &&
      other.position == position;

  @override
  int get hashCode => Object.hash(type, position);
}
