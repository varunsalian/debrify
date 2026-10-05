import 'dart:convert';
import 'dart:io';

import 'package:debrify/screens/debrify_tv/widgets/switch_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/debrify_tv_fixture.dart';

const _captureLinux = bool.fromEnvironment('DEBRIFY_TV_CAPTURE_ORIGINAL_LINUX');
const _requireLinux = bool.fromEnvironment('DEBRIFY_TV_REQUIRE_ORIGINAL_LINUX');
const _reverse = bool.fromEnvironment('DEBRIFY_TV_REVERSE_GOLDENS');

Future<void> fonts(WidgetTester t) async {
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
}

void main() {
  final scenes = [
    'grid_tv',
    'search_phone',
    'empty_desktop',
    'spotlight_tv',
    'settings_tv',
    'editor_child_phone',
  ];
  for (final scene in _reverse ? scenes.reversed : scenes) {
    testWidgets('ORIGINAL golden $scene ready focus cache and dimensions', (
      t,
    ) async {
      await fonts(t);
      await debrifyTvCase(t, (f) async {
        f.television = scene.endsWith('_tv');
        f.count = scene == 'empty_desktop'
            ? 0
            : scene == 'grid_tv' || scene == 'search_phone'
            ? 6
            : 2;
        f.goldenFavorites = scene == 'grid_tv';
        f.goldenSearchNames = scene == 'search_phone';
        f.expectOriginalPhoneAddCardOverflow = scene == 'search_phone';
        f.childProfile = scene == 'editor_child_phone';
        f.style = scene == 'spotlight_tv' || f.childProfile
            ? 'spotlight'
            : 'grid';
        final size = scene.endsWith('_phone')
            ? const Size(390, 844)
            : scene == 'empty_desktop'
            ? const Size(1280, 800)
            : const Size(1920, 1080);
        await f.mount(t, size: size);
        if (scene == 'grid_tv') {
          f.node('DebrifyTVQuickPlay').requestFocus();
          await f.settle(t);
          expect(f.node('DebrifyTVQuickPlay').hasFocus, isTrue);
          expect(find.text('ORIGINAL CHANNEL 6'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (w) => w is Icon && w.icon == Icons.star_rounded && w.size == 14,
            ),
            findsNWidgets(2),
          );
        } else if (scene == 'search_phone') {
          await f.tap(t, find.byTooltip('Search channels'));
          await t.enterText(find.byType(EditableText), 'Original');
          await f.settle(t);
          expect(find.text('ORIGINAL CHANNEL 3'), findsOneWidget);
          expect(find.text('OTHER CHANNEL 4'), findsNothing);
          expect(f.node('DebrifyTVChannelSearch').hasFocus, isTrue);
          expect(
            f.originalPhoneAddCardOverflows,
            hasLength(2),
            reason:
                'R add-card overflows by exactly 37 pixels in both phone layouts',
          );
        } else if (scene == 'empty_desktop') {
          FocusManager.instance.primaryFocus?.unfocus();
          await f.settle(t);
          expect(find.text('No channels yet'), findsOneWidget);
        } else if (scene == 'spotlight_tv') {
          f.node('debrify-tv-spotlight-ch:original-2').requestFocus();
          await t.pump();
          await t.pump(const Duration(milliseconds: 250));
          await f.until(
            t,
            () => f.spotlight.view.stats?.channelId == 'original-2',
          );
          await f.settle(t);
          expect(f.spotlight.view.stats!.pooled, 1);
          expect(f.spotlight.view.stats!.fetchedAt, isNull);
          expect(find.textContaining('never'), findsWidgets);
          expect(f.node('debrify-tv-spotlight-ch:original-2').hasFocus, isTrue);
        } else if (scene == 'settings_tv') {
          await f.settings(t);
          expect(find.text('Channel playback'), findsOneWidget);
          expect(find.text('Start from random timestamp'), findsOneWidget);
          expect(find.text('Done'), findsOneWidget);
          expect(FocusManager.instance.primaryFocus, isNotNull);
          expect(
            f.originalLayoutDiagnostics,
            isNotEmpty,
            reason: 'ORIGINAL SwitchRow decoration diagnostic stays recorded',
          );
        } else {
          f.spotlight.view.onEdit(f.channels.first);
          await t.pump();
          await f.settle(t);
          expect(find.text('Keywords (3/1000)'), findsOneWidget);
          expect(find.text('one'), findsOneWidget);
          expect(find.text('two'), findsOneWidget);
          expect(find.text('three'), findsOneWidget);
          expect(find.text('Always on for this profile'), findsOneWidget);
          expect(t.widget<SwitchRow>(find.byType(SwitchRow)).value, isTrue);
          FocusManager.instance.primaryFocus?.unfocus();
          await f.settle(t);
        }
        expect(f.requests, isEmpty);
        expect(t.view.physicalSize, size);
        expect(t.view.devicePixelRatio, 1);
        expect(MediaQuery.textScalerOf(f.hostKey.currentContext!).scale(1), 1);
        final platform = Platform.isLinux ? 'linux' : 'macos';
        final path = 'test/goldens/debrify_tv/$platform/$scene.png';
        final config =
            jsonDecode(
                  File(
                    'dev/tool/debrify_tv_checker_config.json',
                  ).readAsStringSync(),
                )
                as Map;
        final strict =
            !Platform.isLinux ||
            _captureLinux ||
            _requireLinux ||
            File(path).existsSync() ||
            (config['completed_step'] as int) >= 1;
        if (strict) {
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../../../../goldens/debrify_tv/$platform/$scene.png',
            ),
          );
        }
      });
    });
  }
}
