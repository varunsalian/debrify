import 'package:media_kit/media_kit.dart' as mk;

abstract interface class VpStartPositionHost {
  Duration get duration;
  mk.Player get player;
  double? get startAtPercent;
  bool get startFromRandom;
  Duration? randomStartOffset(Duration duration);
  Duration? percentStartOffset(Duration duration);
  Future<void> maybeRestoreResume({bool verifyLanding});
  Future<void> seekForResume(int targetMs, {bool verifyLanding});
}

/// Applies a launch's first position: random start takes precedence over
/// resume, then startAtPercent. Remote opens can answer the startup seek with
/// a restart at 0, so every seek that protects a position verifies its landing.
/// [deferPercent] leaves an explicit percent to a caller that seeks it later.
Future<void> applyInitialStartPosition(
  VpStartPositionHost host, {
  bool deferPercent = false,
}) async {
  if (host.startFromRandom) {
    final offset = host.randomStartOffset(host.duration);
    if (offset != null) {
      // A random start has no bookmark to protect and no "correct" position
      // to verify against, so a plain seek is enough.
      await host.player.seek(offset);
    } else {
      await host.maybeRestoreResume(verifyLanding: true);
    }
  } else if (host.startAtPercent != null) {
    final offset = deferPercent ? null : host.percentStartOffset(host.duration);
    if (offset != null) {
      await host.seekForResume(offset.inMilliseconds, verifyLanding: true);
    }
  } else {
    await host.maybeRestoreResume(verifyLanding: true);
  }
}
