import 'dart:async';

import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/models/hud_state.dart';
import 'package:debrify/screens/video_player/widgets/aspect_ratio_hud.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/display_defaults_reads.dart';
import 'support/display_mode_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

const nextAspects = <(AspectMode, String, IconData, BoxFit, double?)>[
  (AspectMode.cover, 'Cover', Icons.crop_free_rounded, BoxFit.cover, null),
  (
    AspectMode.fitWidth,
    'Fit Width',
    Icons.fit_screen_rounded,
    BoxFit.fitWidth,
    null,
  ),
  (
    AspectMode.fitHeight,
    'Fit Height',
    Icons.fit_screen_rounded,
    BoxFit.fitHeight,
    null,
  ),
  (
    AspectMode.aspect16_9,
    '16:9',
    Icons.aspect_ratio_rounded,
    BoxFit.cover,
    16 / 9,
  ),
  (
    AspectMode.aspect4_3,
    '4:3',
    Icons.aspect_ratio_rounded,
    BoxFit.cover,
    4 / 3,
  ),
  (
    AspectMode.aspect21_9,
    '21:9',
    Icons.aspect_ratio_rounded,
    BoxFit.cover,
    21 / 9,
  ),
  (AspectMode.aspect1_1, '1:1', Icons.crop_square_rounded, BoxFit.cover, 1),
  (
    AspectMode.aspect3_2,
    '3:2',
    Icons.aspect_ratio_rounded,
    BoxFit.cover,
    3 / 2,
  ),
  (
    AspectMode.aspect5_4,
    '5:4',
    Icons.aspect_ratio_rounded,
    BoxFit.cover,
    5 / 4,
  ),
  (
    AspectMode.cinemaZoom,
    'Cinema Zoom',
    Icons.zoom_in_map_rounded,
    BoxFit.contain,
    null,
  ),
  (
    AspectMode.contain,
    'Contain',
    Icons.crop_free_rounded,
    BoxFit.contain,
    null,
  ),
];

void main() {
  testWidgets(
    'display early key A cycles the initializer while defaults wait and preserves the player error and blocked save',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      final oldStore = SharedPreferencesStorePlatform.instance;
      DisplayDefaultsReads? reads;
      final errors = <Object>[];
      try {
        await d.defaults(aspect: 10);
        reads = await t.runAsync(DisplayDefaultsReads.install);
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: f.navigator,
            theme: ThemeData.dark(),
            home: displayScreen(),
          ),
        );
        await f.until(t, () => reads!.entered);
        expect(f.creationOrder, ['media-kit-init']);
        expect(f.players, isEmpty);
        expect(f.controllers, isEmpty);
        expect(find.byType(mkv.Video), findsNothing);
        expect(find.byType(AspectRatioHud), findsNothing);
        final errorZone = Zone.current.fork(
          specification: ZoneSpecification(
            handleUncaughtError: (self, parent, zone, error, stack) {
              errors.add(error);
            },
          ),
        );
        await errorZone.run(() => t.sendKeyEvent(LogicalKeyboardKey.keyA));
        await f.advance(t);
        final hud = t.widget<AspectRatioHud>(find.byType(AspectRatioHud)).hud;
        expect(hud.aspectRatio, 'Cover');
        expect(hud.icon, Icons.crop_free_rounded);
        expect(errors, hasLength(1));
        expect(errors.single, isA<Error>());
        expect(errors.single.toString(), contains("Field '_player"));
        expect(errors.single.toString(), contains('has not been initialized'));
        expect(f.players, isEmpty, reason: 'Early zoom cannot reach a player');
        expect(
          reads!.writes,
          isEmpty,
          reason: 'Not-ready resume save is blocked',
        );
        await f.advance(t, const Duration(milliseconds: 1499));
        expect(find.byType(AspectRatioHud), findsOneWidget);
        await f.advance(t, const Duration(milliseconds: 1));
        expect(find.byType(AspectRatioHud), findsNothing);
        expect(f.players, isEmpty);
        expect(reads.writes, isEmpty);
        reads.unblock();
        await f.mount(t, displayScreen());
        expect(f.players, hasLength(1));
        d.expectAspect(AspectMode.cinemaZoom, BoxFit.contain, null);
        expect(playerControls(t).speed, 1.0);
        final native = f.player.platform as FakeNativePlayer;
        expect(native.properties['video-zoom'], '0.415037');
        await t.sendKeyEvent(LogicalKeyboardKey.keyA);
        await f.advance(t);
        d.expectAspect(AspectMode.contain, BoxFit.contain, null);
        expect(native.properties['video-zoom'], '0.000000');
        final saved = await d.record();
        expect(saved['aspect'], 'contain');
        expect(saved['speed'], 1.0);
        expect(errors, hasLength(1));
      } finally {
        reads?.unblock();
        await f.close(t);
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  for (var index = 0; index < nextAspects.length; index++) {
    final expected = nextAspects[index];
    testWidgets(
      'display aspect key cycles to ${expected.$2} with rendered ratio HUD zoom and save',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        await t.runAsync(f.initialize);
        final d = DisplayModeDriver(t, f);
        try {
          await d.defaults(aspect: index);
          await f.mount(t, displayScreen());
          expect(playerControls(t).aspectMode, AspectMode.values[index]);
          expect(
            (f.player.platform as FakeNativePlayer).properties['video-zoom'],
            index == 10 ? '0.415037' : '0.000000',
          );
          await t.sendKeyEvent(LogicalKeyboardKey.keyA);
          await f.advance(t);
          d.expectAspect(expected.$1, expected.$4, expected.$5);
          expect(find.byType(AspectRatioHud), findsOneWidget);
          final hud = t.widget<AspectRatioHud>(find.byType(AspectRatioHud)).hud;
          expect(hud.aspectRatio, expected.$2);
          expect(hud.icon, expected.$3);
          expect(
            (f.player.platform as FakeNativePlayer).properties['video-zoom'],
            expected.$1 == AspectMode.cinemaZoom ? '0.415037' : '0.000000',
          );
          final state = await d.record();
          expect(state['aspect'], switch (expected.$1) {
            AspectMode.aspect16_9 => '16:9',
            AspectMode.aspect4_3 => '4:3',
            AspectMode.aspect21_9 => '21:9',
            AspectMode.aspect1_1 => '1:1',
            AspectMode.aspect3_2 => '3:2',
            AspectMode.aspect5_4 => '5:4',
            _ => expected.$1.name,
          });
          await f.advance(t, const Duration(milliseconds: 1499));
          expect(find.byType(AspectRatioHud), findsOneWidget);
          await f.advance(t, const Duration(milliseconds: 1));
          expect(find.byType(AspectRatioHud), findsNothing);
        } finally {
          await f.close(t);
        }
      },
    );
  }

  testWidgets('display aspect pending HUD clear does nothing after disposal', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final d = DisplayModeDriver(t, f);
    try {
      await d.defaults();
      await f.mount(t, displayScreen());
      await t.sendKeyEvent(LogicalKeyboardKey.keyA);
      await f.advance(t);
      expect(find.byType(AspectRatioHud), findsOneWidget);
      final signal = t
          .widget<ValueListenableBuilder<AspectRatioHudState?>>(
            find.byType(ValueListenableBuilder<AspectRatioHudState?>),
          )
          .valueListenable;
      final shown = signal.value;
      var notifications = 0;
      void observe() => notifications++;
      signal.addListener(observe);
      await t.pumpWidget(const SizedBox.shrink());
      await f.advance(t, const Duration(milliseconds: 1500));
      signal.removeListener(observe);
      expect(t.takeException(), isNull);
      expect(notifications, 0);
      expect(signal.value, same(shown));
    } finally {
      await f.close(t);
    }
  });

  testWidgets(
    'display aspect menu passes selection and identical aspect is a no-op',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        final panel = await d.menu(PlayerMenuSection.aspect);
        expect(panel.aspectMode, AspectMode.contain);
        final native = f.player.platform as FakeNativePlayer;
        final before = native.calls.length;
        panel.onAspectSelected(AspectMode.contain);
        await f.advance(t);
        expect(native.calls.length, before);
        panel.onAspectSelected(AspectMode.aspect4_3);
        await f.advance(t);
        await d.closeMenu();
        d.expectAspect(AspectMode.aspect4_3, BoxFit.cover, 4 / 3);
        expect(native.properties['video-zoom'], '0.000000');
        expect((await d.record())['aspect'], '4:3');
        expect(find.byType(AspectRatioHud), findsNothing);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets('display non-native aspect path skips native zoom', (t) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final d = DisplayModeDriver(t, f);
    try {
      await d.defaults();
      await f.mount(t, displayScreen());
      await d.aspect(AspectMode.cinemaZoom);
      d.expectAspect(AspectMode.cinemaZoom, BoxFit.contain, null);
      expect(t.takeException(), isNull);
    } finally {
      await f.close(t);
    }
  });

  testWidgets(
    'display native zoom rejection logs once and still applies aspect',
    (t) async {
      final f = VideoPlayerEnvironment(native: true);
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      final oldPrint = debugPrint;
      final logs = <String>[];
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
        final native = f.player.platform as FakeNativePlayer;
        native.failures['setProperty'] = StateError('zoom fixture');
        await d.aspect(AspectMode.cinemaZoom);
        d.expectAspect(AspectMode.cinemaZoom, BoxFit.contain, null);
        expect(
          logs.where(
            (s) =>
                s ==
                'VideoPlayer: aspect zoom apply failed: Bad state: zoom fixture',
          ),
          hasLength(1),
        );
        expect(
          native.calls
              .where(
                (c) =>
                    c.$1 == 'setProperty' &&
                    (c.$2 as (String, String)).$1 == 'video-zoom',
              )
              .last,
          ('setProperty', ('video-zoom', '0.415037')),
        );
        expect(t.takeException(), isNull);
      } finally {
        debugPrint = oldPrint;
        await f.close(t);
      }
    },
  );
}
