import 'dart:io';

import 'package:debrify/services/desktop_schedule_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/recordings_fixture.dart';

const reverse = bool.fromEnvironment('RECORDINGS_REVERSE_GOLDENS');
const captureLinux = bool.fromEnvironment('RECORDINGS_CAPTURE_ORIGINAL_LINUX');
const requireLinux = bool.fromEnvironment('RECORDINGS_REQUIRE_ORIGINAL_LINUX');
bool loaded = false;

Future<void> fonts(WidgetTester t) async {
  if (loaded) return;
  await t.runAsync(() async {
    for (final family in ['Roboto', 'Inter', 'Poppins', 'JetBrainsMono']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf'));
      if (family == 'JetBrainsMono') {
        loader.addFont(rootBundle.load('assets/fonts/$family-Bold.ttf'));
      }
      await loader.load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });
  loaded = true;
}

void main() {
  final scenes = ['empty_tv', 'populated_desktop', 'library_focus_tv'];
  final pendingLinux =
      Platform.isLinux &&
      !captureLinux &&
      !requireLinux &&
      !Directory('test/goldens/recordings/linux').existsSync();
  for (final scene in reverse ? scenes.reversed : scenes) {
    testWidgets(
      'ORIGINAL recordings golden $scene readiness and focus',
      (t) async {
        await fonts(t);
        await recordingsCase(t, (f) async {
          f.television = scene.endsWith('_tv');
          if (scene != 'empty_tv') {
            await t.runAsync(() async {
              await f.file(
                'Evening_News_20240302_180000.ts',
                bytes: 1024 * 1024,
                modified: DateTime(2024, 3, 2, 18, 30),
              );
              await f.file(
                'Morning_Show_20240301_090000.ts',
                modified: DateTime(2024, 3, 1, 10),
              );
            });
            await f.seedSchedules([
              f.schedule(
                'original',
                start: DateTime(2024, 3, 3, 12),
                title: 'Weekend programme',
              ),
            ]);
            DesktopScheduleService.instance.shutdown();
          }
          await f.mount(t);
          if (scene == 'empty_tv') {
            expect(find.text('Your DVR is empty'), findsOneWidget);
            final button = f.focus(t, recordingsType('_HubButton').last);
            expect(button.focusNode!.hasFocus, isTrue);
          } else {
            expect(recordingsType('_LibraryRow'), findsNWidgets(2));
            expect(find.text('due'), findsOneWidget);
            if (scene == 'library_focus_tv') {
              final row = f.focus(t, recordingsType('_LibraryRow').first);
              row.focusNode!.requestFocus();
              await f.settle(t);
              expect(row.focusNode!.hasFocus, isTrue);
            } else {
              FocusManager.instance.primaryFocus?.unfocus();
              await f.settle(t);
            }
          }
          expect(find.byType(CircularProgressIndicator), findsNothing);
          expect(t.view.devicePixelRatio, 1);
          expect(
            MediaQuery.textScalerOf(f.pageKey.currentContext!).scale(1),
            1,
          );
          final platform = Platform.isLinux ? 'linux' : 'macos';
          await expectLater(
            find.byKey(recordingsCanvas),
            matchesGoldenFile(
              '../../../goldens/recordings/$platform/$scene.png',
            ),
          );
        });
      },
      // Linux originals await the separate Claude capture checkpoint.
      skip: pendingLinux,
    );
  }
}
