/// Maps remote commands onto the player.
library;

import 'package:debrify/features/now_playing/models/now_playing_models.dart';

/// What the player exposes to remote commands; null callbacks are unsupported
/// commands.
final class NowPlayingTarget {
  const NowPlayingTarget({
    required this.play,
    required this.pause,
    required this.seek,
    required this.position,
    required this.duration,
    this.next,
    this.previous,
  });

  final Future<void> Function() play;
  final Future<void> Function() pause;

  /// Seeks to an absolute position, already clamped by the caller.
  final Future<void> Function(Duration) seek;

  final Duration Function() position;
  final Duration Function() duration;

  /// Null when there is nothing else in the queue.
  final Future<void> Function()? next;
  final Future<void> Function()? previous;
}

/// How far skipForward / skipBackward move.
const nowPlayingSkip = Duration(seconds: 15);

/// Handles [command] against [target].
///
/// play/pause call through; toggle pauses when [isPlaying] and plays
/// otherwise; skipForward/skipBackward seek by [nowPlayingSkip] from
/// `position()`, clamped to `duration()`; seekTo seeks to the given position
/// clamped the same way; when `duration()` is zero (live stream, unknown
/// length) skips and seeks are ignored; next/previous call through when
/// non-null, otherwise ignored.
Future<void> handleNowPlayingCommand(
  NowPlayingCommand command,
  NowPlayingTarget target, {
  required bool isPlaying,
}) async {
  switch (command.type) {
    case NowPlayingCommandType.play:
      await target.play();
    case NowPlayingCommandType.pause:
      await target.pause();
    case NowPlayingCommandType.toggle:
      if (isPlaying) {
        await target.pause();
      } else {
        await target.play();
      }
    case NowPlayingCommandType.skipForward:
      await _seekBy(target, nowPlayingSkip);
    case NowPlayingCommandType.skipBackward:
      await _seekBy(target, -nowPlayingSkip);
    case NowPlayingCommandType.seekTo:
      final to = command.position;
      if (to == null) return;
      final length = target.duration();
      if (length == Duration.zero) return;
      await target.seek(_clamp(to, length));
    case NowPlayingCommandType.next:
      await target.next?.call();
    case NowPlayingCommandType.previous:
      await target.previous?.call();
  }
}

Future<void> _seekBy(NowPlayingTarget target, Duration delta) async {
  final length = target.duration();
  if (length == Duration.zero) return;
  await target.seek(_clamp(target.position() + delta, length));
}

Duration _clamp(Duration to, Duration length) {
  if (to < Duration.zero) return Duration.zero;
  return to > length ? length : to;
}
