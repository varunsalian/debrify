import 'dart:io';

import 'package:debrify/screens/video_player/services/renderer_startup_environment.dart';
import 'package:flutter_test/flutter_test.dart';

// Pure seam contract only: no host, terminal, renderer, timers or disposal.
void main() {
  bool? previous;

  setUp(() {
    previous = RendererStartupEnvironment.debugIsAndroid;
  });

  tearDown(() {
    RendererStartupEnvironment.debugIsAndroid = previous;
  });

  test('null reads the actual platform again after an explicit override', () {
    RendererStartupEnvironment.debugIsAndroid = null;
    expect(RendererStartupEnvironment.isAndroid, Platform.isAndroid);
    RendererStartupEnvironment.debugIsAndroid = !Platform.isAndroid;
    expect(RendererStartupEnvironment.isAndroid, !Platform.isAndroid);
    RendererStartupEnvironment.debugIsAndroid = null;
    expect(RendererStartupEnvironment.isAndroid, Platform.isAndroid);
  });

  test('explicit false overrides the platform', () {
    RendererStartupEnvironment.debugIsAndroid = false;
    expect(RendererStartupEnvironment.isAndroid, isFalse);
  });

  test('explicit true overrides the platform', () {
    RendererStartupEnvironment.debugIsAndroid = true;
    expect(RendererStartupEnvironment.isAndroid, isTrue);
  });

  for (final prior in <bool?>[null, false, true]) {
    test('nested finally restores captured $prior after a thrown error', () {
      RendererStartupEnvironment.debugIsAndroid = prior;
      final capturedOuter = RendererStartupEnvironment.debugIsAndroid;
      final sentinel = StateError('fixture body failed');
      bool? restoredInner;

      expect(() {
        try {
          RendererStartupEnvironment.debugIsAndroid = true;
          final capturedInner = RendererStartupEnvironment.debugIsAndroid;
          try {
            RendererStartupEnvironment.debugIsAndroid = false;
            throw sentinel;
          } finally {
            RendererStartupEnvironment.debugIsAndroid = capturedInner;
            restoredInner = RendererStartupEnvironment.debugIsAndroid;
          }
        } finally {
          RendererStartupEnvironment.debugIsAndroid = capturedOuter;
        }
      }, throwsA(same(sentinel)));

      expect(restoredInner, isTrue);
      expect(RendererStartupEnvironment.debugIsAndroid, prior);
      expect(RendererStartupEnvironment.isAndroid, prior ?? Platform.isAndroid);
    });
  }
}
