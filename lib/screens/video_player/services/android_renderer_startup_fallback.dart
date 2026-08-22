import '../../../models/android_video_renderer_mode.dart';

/// Pure policy for the Android phone/tablet renderer startup guard.
///
/// The player screen owns timing and player recreation. Keeping the decisions
/// here makes it possible to test that network failures never change renderers
/// while MediaCodec/surface failures do.
abstract final class AndroidRendererStartupFallback {
  static const String directSurfaceOutput = 'mediacodec_embed';
  static const String directMediaCodecOutput = 'gpu';

  static bool shouldArm({
    required bool isAndroid,
    required bool isAndroidTv,
    required AndroidVideoRendererMode mode,
    required bool alreadyValidated,
    required bool fallbackInProgress,
  }) {
    return isAndroid &&
        !isAndroidTv &&
        mode != AndroidVideoRendererMode.automatic &&
        !alreadyValidated &&
        !fallbackInProgress;
  }

  static bool isExpectedOutput({
    required AndroidVideoRendererMode mode,
    required String value,
  }) {
    final expected = switch (mode) {
      AndroidVideoRendererMode.directMediaCodec => directMediaCodecOutput,
      AndroidVideoRendererMode.directSurface => directSurfaceOutput,
      AndroidVideoRendererMode.automatic => null,
    };
    return expected != null && value.trim().toLowerCase() == expected;
  }

  /// Only errors that identify the video decoder/output path may trigger the
  /// compatibility restart. HTTP, DNS, manifest and generic buffering errors
  /// deliberately remain on the current renderer.
  static bool isRendererFailure(String error) {
    final value = error.toLowerCase();
    return value.contains('mediacodec') ||
        value.contains('gpu context') ||
        value.contains('render context') ||
        value.contains('video output') ||
        value.contains('video-output') ||
        value.contains('could not open codec') ||
        value.contains('failed to configure codec') ||
        value.contains('surface') && value.contains('video');
  }
}
