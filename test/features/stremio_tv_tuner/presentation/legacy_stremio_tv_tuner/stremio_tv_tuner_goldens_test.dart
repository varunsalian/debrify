import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../../support/stremio_tv_tuner_fixture.dart';

const reverse = bool.fromEnvironment('STREMIO_TV_TUNER_REVERSE_GOLDENS');
void main() {
  final scenes = [
    'tv_wide',
    'desktop_wide',
    'touch_tablet',
    'phone_narrow',
    'tv_hidden',
    'phone_actions',
    'phone_channel_list',
  ];
  for (final scene in reverse ? scenes.reversed : scenes) {
    testWidgets('ORIGINAL golden $scene ready focus and dimensions', (
      tester,
    ) async {
      await tester.runAsync(() async {
        for (final family in ['Roboto', 'Inter', 'Poppins', 'JetBrainsMono']) {
          await (FontLoader(family)
                ..addFont(rootBundle.load('assets/fonts/$family-Regular.ttf')))
              .load();
        }
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
      await tunerCase(tester, (f) async {
        f.television = scene.startsWith('tv');
        f.platform = scene == 'desktop_wide' || f.television
            ? TargetPlatform.macOS
            : TargetPlatform.android;
        f.hideNowPlaying = scene == 'tv_hidden';
        f.disableAnimations = true;
        final size = f.television
            ? const Size(1920, 1080)
            : scene == 'desktop_wide'
            ? const Size(1440, 900)
            : scene == 'touch_tablet'
            ? const Size(1280, 800)
            : const Size(390, 844);
        await f.mount(tester, size: size);
        if (f.television) {
          await f.focus(tester, 1);
          await tester.pump(const Duration(milliseconds: 200));
        }
        if (scene == 'phone_actions') {
          final detector = tester.widget<GestureDetector>(
            find
                .ancestor(
                  of: f.stages.first,
                  matching: find.byType(GestureDetector),
                )
                .first,
          );
          detector.onLongPress!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('Play this channel now'), findsOneWidget);
        }
        if (scene == 'phone_channel_list') {
          await tester.tap(find.text('Channels'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('All channels'), findsOneWidget);
        }
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byKey(tunerCapture)), size);
        if (scene == 'tv_wide') {
          expect(find.text('OPTIONS'), findsOneWidget);
          expect(f.nodes[1].hasPrimaryFocus, isTrue);
        }
        if (scene == 'touch_tablet') {
          final dynamic first = tester.widget(f.card(0));
          expect(first.centredId.value, 'channel-0');
        }
        if (scene == 'phone_narrow') {
          expect(find.text('Channels'), findsOneWidget);
          expect(find.text('Details'), findsOneWidget);
        }
        final platform = Platform.isLinux ? 'linux' : 'macos';
        final path = 'test/goldens/stremio_tv_tuner/$platform/$scene.png';
        if (Platform.isLinux) {
          expect(
            File(path).existsSync(),
            isTrue,
            reason: 'Missing ORIGINAL Linux golden',
          );
        }
        await expectLater(
          find.byKey(tunerCapture),
          matchesGoldenFile(
            '../../../../goldens/stremio_tv_tuner/$platform/$scene.png',
          ),
        );
      });
    });
  }
}
