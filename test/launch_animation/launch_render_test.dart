import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/launch_animation/launch_package.dart';
import 'package:debrify/services/launch_animation/launch_animation_library.dart';
import 'package:debrify/widgets/launch/imported_launch_player.dart';

void main() {
  testWidgets('a draw error is reported once without escaping the painter', (
    tester,
  ) async {
    late LoadedLaunchAnimation loaded;
    await tester.runAsync(() async {
      final bytes = await File(
        'dev/launch_animations/samples/hello-image.lottie',
      ).readAsBytes();
      final package = LaunchPackage.decode(bytes);
      loaded = await loadPrepared(package.prepare(package.initialId));
    });
    // Simulate a recoverable resource failure after decode has succeeded.
    final asset = loaded.composition.images.values.first;
    asset.loadedImage!.dispose();
    final errors = <Object>[];
    await tester.pumpWidget(
      MaterialApp(
        home: ImportedLaunchPlayer(
          animation: loaded,
          progress: const AlwaysStoppedAnimation(.5),
          onError: errors.add,
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(errors, hasLength(1));
    await tester.pump();
    expect(errors, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    asset.loadedImage = null;
    loaded.dispose();
  });

  for (final name in [
    'hello-landscape',
    'hello-portrait',
    'hello-multiple',
    'hello-image',
    'hello-features',
    'hello-radial',
    'hello-mattes',
  ]) {
    testWidgets(
      '$name decodes and paints across aspect ratios without errors',
      (tester) async {
        late LoadedLaunchAnimation loaded;
        await tester.runAsync(() async {
          final bytes = await File(
            'dev/launch_animations/samples/$name.lottie',
          ).readAsBytes();
          final package = LaunchPackage.decode(bytes);
          loaded = await loadPrepared(package.prepare(package.initialId));
        });
        final errors = <Object>[];
        for (final size in [
          const Size(320, 640),
          const Size(1920, 1080),
          const Size(2560, 1080),
        ]) {
          tester.view.resetPhysicalSize();
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          for (final progress in [0.0, .25, .5, 1.0]) {
            await tester.pumpWidget(
              MaterialApp(
                home: Scaffold(
                  body: ImportedLaunchPlayer(
                    animation: loaded,
                    progress: AlwaysStoppedAnimation(progress),
                    onError: errors.add,
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
          }
        }
        expect(errors, isEmpty);
        expect(loaded.composition.warnings, isEmpty);
        await tester.pumpWidget(const SizedBox());
        loaded.dispose();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      },
    );
  }
}
