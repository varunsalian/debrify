import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/iptv_spotlight_timeline_fixture.dart';

const reverse = bool.fromEnvironment('IPTV_SPOTLIGHT_TIMELINE_REVERSE_GOLDENS');
const captureLinux = bool.fromEnvironment(
  'IPTV_SPOTLIGHT_TIMELINE_CAPTURE_ORIGINAL_LINUX',
);
const requireLinux = bool.fromEnvironment(
  'IPTV_SPOTLIGHT_TIMELINE_REQUIRE_ORIGINAL_LINUX',
);
void main() {
  final scenes = [
    'identity',
    'programme_replay',
    'retry',
    'panned_states',
    'dense_scaled',
    'empty',
  ];
  for (final scene in reverse ? scenes.reversed : scenes) {
    testWidgets('ORIGINAL golden $scene ready focus and dimensions', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final font = await rootBundle.load('assets/fonts/Inter-Regular.ttf');
        expect(
          font.getUint32(0),
          0x00010000,
          reason: 'the pinned ORIGINAL font must be a valid TrueType asset',
        );
        await (FontLoader(
          'TimelineGoldenInter',
        )..addFont(Future.value(font))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      await timelineCase(tester, (f) async {
        f.fontFamily = 'TimelineGoldenInter';
        f.height = 360;
        f.rowHeight = 60;
        f.autofocus = scene != 'empty';
        if (scene == 'dense_scaled') {
          f.dense = true;
          f.rowHeight = 46;
          f.textScale = 1.3;
        }
        if (scene == 'panned_states') {
          f.channels[4] = timelineChannel(4, live: false);
          f.initialWindowStart = DateTime(2030, 1, 1, 12);
        } else {
          f.loader = (c) async {
            if (scene == 'retry' && identical(c, f.channels[1])) {
              throw StateError('offline');
            }
            return [
              timelineProgramme(
                'Archived morning',
                DateTime(2030, 1, 1, 9),
                minutes: 60,
                archive: true,
              ),
              timelineProgramme(
                'Current news',
                DateTime(2030, 1, 1, 10),
                minutes: 30,
              ),
              timelineProgramme(
                'Next programme',
                DateTime(2030, 1, 1, 10, 30),
                minutes: 60,
              ),
            ];
          };
        }
        await f.mount(tester);
        await f.settle(tester);
        if (scene == 'programme_replay') {
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
          await tester.pump();
          // Select the past archive cell using the pointer; the same preview contract applies.
          await tester.tap(find.text('Archived morning').first);
          await tester.pump();
          expect(f.selections.last.programme!.hasArchive, isTrue);
        }
        if (scene == 'retry') {
          f.controller!.focusChannelAt(1);
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump();
          expect(find.text('Guide unavailable  ·  Retry'), findsOneWidget);
        }
        if (scene == 'panned_states') {
          f.script.calls[1].resolve([]);
          f.script.calls[2].resolve([
            timelineProgramme('Outside window', DateTime(2030, 1, 1, 8)),
          ]);
          f.script.calls[3].fail();
          await tester.pump();
          expect(find.text('Loading guide…'), findsOneWidget);
          expect(find.text('No programme information'), findsOneWidget);
          expect(
            find.text('No information in this time window'),
            findsOneWidget,
          );
          expect(find.text('On demand  ·  Press OK to open'), findsOneWidget);
        }
        await tester.pump(const Duration(milliseconds: 200));
        expect(tester.takeException(), isNull);
        expect(
          tester.getSize(find.byKey(timelineCapture)),
          const Size(1280, 360),
        );
        if (scene == 'identity') {
          expect(f.controller!.hasFocus, isTrue);
          expect(find.text('NOW'), findsNWidgets(5));
        }
        final platform = Platform.isLinux ? 'linux' : 'macos';
        final path =
            'test/goldens/iptv_spotlight_timeline/$platform/$scene.png';
        if (Platform.isLinux && !captureLinux) {
          if (!requireLinux && !File(path).existsSync()) return;
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'Missing ORIGINAL Linux golden',
          );
        }
        await expectLater(
          find.byKey(timelineCapture),
          matchesGoldenFile(
            '../../../../goldens/iptv_spotlight_timeline/$platform/$scene.png',
          ),
        );
      }, count: scene == 'empty' ? 0 : 5);
    });
  }
}
