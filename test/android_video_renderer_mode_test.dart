import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('automatic mode preserves media-kit platform defaults', () {
    expect(AndroidVideoRendererMode.automatic.videoOutput, isNull);
    expect(AndroidVideoRendererMode.automatic.hardwareDecoder, isNull);
  });

  test('explicit modes map to their intended mpv properties', () {
    expect(AndroidVideoRendererMode.directMediaCodec.videoOutput, 'gpu');
    expect(
      AndroidVideoRendererMode.directMediaCodec.hardwareDecoder,
      'mediacodec',
    );
    expect(
      AndroidVideoRendererMode.directSurface.videoOutput,
      'mediacodec_embed',
    );
    expect(
      AndroidVideoRendererMode.directSurface.hardwareDecoder,
      'mediacodec',
    );
  });

  test(
    'storage defaults to GPU MediaCodec and round-trips a selected mode',
    () async {
      expect(
        await StorageService.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.directMediaCodec,
      );

      await StorageService.setAndroidVideoRendererMode(
        AndroidVideoRendererMode.directMediaCodec,
      );
      expect(
        await StorageService.getAndroidVideoRendererMode(),
        AndroidVideoRendererMode.directMediaCodec,
      );
    },
  );

  test('migrates the former direct-surface default only once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'android_video_renderer_mode': 'direct_surface',
    });

    expect(
      await StorageService.getAndroidVideoRendererMode(),
      AndroidVideoRendererMode.directMediaCodec,
    );

    await StorageService.setAndroidVideoRendererMode(
      AndroidVideoRendererMode.directSurface,
    );
    expect(
      await StorageService.getAndroidVideoRendererMode(),
      AndroidVideoRendererMode.directSurface,
    );
  });

  test('unknown stored values fall back to automatic', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'android_video_renderer_mode': 'removed_mode',
    });

    expect(
      await StorageService.getAndroidVideoRendererMode(),
      AndroidVideoRendererMode.automatic,
    );
  });
}
