import 'dart:async';
import 'package:media_kit/media_kit.dart' as mk;

class VpSubtitleApplyAttempt {
  final int generation;
  final mk.SubtitleTrack requested;
  final mk.SubtitleTrack previous;
  final String source;
  final String? previousStremioId;
  final String? previousExternalPath;
  bool failed = false;
  bool handled = false;
  bool successReturned = false;
  bool persisted = false;
  String? persistedAudioId;
  Completer<void>? persistenceDone;

  VpSubtitleApplyAttempt({
    required this.generation,
    required this.requested,
    required this.previous,
    required this.source,
    required this.previousStremioId,
    required this.previousExternalPath,
  });
}
