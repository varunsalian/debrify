import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/services/android_renderer_startup_fallback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('arms only for unvalidated Android phone direct surface', () {
    bool shouldArm({
      bool android = true,
      bool tv = false,
      AndroidVideoRendererMode mode = AndroidVideoRendererMode.directSurface,
      bool validated = false,
      bool inProgress = false,
    }) {
      return AndroidRendererStartupFallback.shouldArm(
        isAndroid: android,
        isAndroidTv: tv,
        mode: mode,
        alreadyValidated: validated,
        fallbackInProgress: inProgress,
      );
    }

    expect(shouldArm(), isTrue);
    expect(shouldArm(android: false), isFalse);
    expect(shouldArm(tv: true), isFalse);
    expect(shouldArm(mode: AndroidVideoRendererMode.automatic), isFalse);
    expect(shouldArm(validated: true), isFalse);
    expect(shouldArm(inProgress: true), isFalse);
  });

  test('requires the exact direct surface output', () {
    expect(
      AndroidRendererStartupFallback.isExpectedOutput('mediacodec_embed'),
      isTrue,
    );
    expect(
      AndroidRendererStartupFallback.isExpectedOutput(' MEDIACODEC_EMBED '),
      isTrue,
    );
    expect(AndroidRendererStartupFallback.isExpectedOutput('gpu'), isFalse);
    expect(AndroidRendererStartupFallback.isExpectedOutput('null'), isFalse);
  });

  test('renderer errors trigger but network errors do not', () {
    for (final error in <String>[
      'MediaCodec failed to configure',
      'Could not open codec.',
      'Failed to configure codec',
      'Video output initialization failed',
      'Video Surface could not be attached',
    ]) {
      expect(
        AndroidRendererStartupFallback.isRendererFailure(error),
        isTrue,
        reason: error,
      );
    }

    for (final error in <String>[
      'HTTP 403 Forbidden',
      'Connection timed out',
      'Could not resolve host',
      'manifest download failed',
      'buffering',
    ]) {
      expect(
        AndroidRendererStartupFallback.isRendererFailure(error),
        isFalse,
        reason: error,
      );
    }
  });
}
