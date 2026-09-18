import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/services/launch_animation/launch_animation_library.dart';
import 'package:debrify/widgets/launch/imported_launch_player.dart';

void main() {
  for (final name in ['trace', 'swiss', 'monogram']) {
    for (final orientation in ['landscape', 'portrait']) {
      testWidgets(
        '$name $orientation imports, paints and holds its final artwork',
        (tester) async {
          late Directory root;
          late LoadedLaunchAnimation loaded;
          await tester.runAsync(() async {
            root = await Directory.systemTemp.createTemp(
              'recreated-launch-test-',
            );
            final library = LaunchAnimationLibrary(directory: () async => root);
            final source = File(
              'dev/launch_animations/recreations/$name.lottie',
            );
            final package = await library.inspectFile(source);
            expect(package.animations, hasLength(2));
            expect(package.orientationPair, isNotNull);
            final entry = await library.install(
              source,
              animationId: '$name-$orientation',
            );
            loaded = await library.load(entry.id);
            expect(loaded.alternate, isNotNull);
            expect(
              loaded.compositionFor(true).bounds.height,
              greaterThan(loaded.compositionFor(true).bounds.width),
            );
            expect(
              loaded.compositionFor(false).bounds.width,
              greaterThan(loaded.compositionFor(false).bounds.height),
            );
            expect(entry.warnings, isEmpty);
            expect(
              loaded.composition.duration.inMilliseconds,
              inInclusiveRange(1700, 2400),
            );
          });
          final errors = <Object>[];
          final boundaryKey = GlobalKey();
          final frames = <List<int>>[];
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = orientation == 'landscape'
              ? const Size(960, 540)
              : const Size(540, 960);
          for (final progress in [0.0, .25, .5, .75, 1.0]) {
            await tester.pumpWidget(
              MaterialApp(
                home: RepaintBoundary(
                  key: boundaryKey,
                  child: ImportedLaunchPlayer(
                    animation: loaded,
                    progress: AlwaysStoppedAnimation(progress),
                    onError: errors.add,
                  ),
                ),
              ),
            );
            await tester.pump();
            expect(tester.takeException(), isNull);
            await tester.runAsync(() async {
              final boundary =
                  boundaryKey.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary;
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              frames.add(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
          expect(errors, isEmpty);
          expect(loaded.composition.warnings, isEmpty);
          expect(
            frames.first,
            isNot(orderedEquals(frames.last)),
            reason: 'The animation must reveal visible artwork.',
          );
          expect(
            frames[1],
            isNot(orderedEquals(frames[2])),
            reason: 'The reveal must have motion.',
          );
          final finalFrame = frames.last;
          var brightPixels = 0;
          for (var i = 0; i < finalFrame.length; i += 4) {
            if (finalFrame[i] > 80 ||
                finalFrame[i + 1] > 80 ||
                finalFrame[i + 2] > 80) {
              brightPixels++;
            }
          }
          expect(
            brightPixels,
            greaterThan(300),
            reason: 'The last frame must retain the lockup.',
          );
          // Resize the existing player without a reload or a new controller.
          tester.view.physicalSize = orientation == 'landscape'
              ? const Size(540, 960)
              : const Size(960, 540);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(errors, isEmpty);
          expect(
            loaded.compositionFor(orientation == 'landscape').onWarning,
            isNotNull,
            reason: 'The player must switch to the other composition.',
          );
          expect(
            loaded.composition.onWarning,
            isNull,
            reason: 'The previously active composition must be detached.',
          );
          await tester.pumpWidget(const SizedBox());
          loaded.dispose();
          await tester.runAsync(() => root.delete(recursive: true));
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        },
      );
    }
  }
}
