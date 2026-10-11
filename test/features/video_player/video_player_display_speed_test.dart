import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player/models/gesture_state.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved preference transport; application dependencies are frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/display_mode_driver.dart';
import 'support/fake_player.dart';
import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

List<Map<String, dynamic>> recordedWrites(SleepResumeWrites store) => [
  for (final write in store.writes)
    if (write.$1.endsWith('playback_state_v1'))
      (jsonDecode(write.$2 as String) as Map<String, dynamic>).values.single
          as Map<String, dynamic>,
];

void main() {
  testWidgets(
    'display speed menu preserves ordered rates wraps selections and persists each selected value',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        expect(playerControls(t).speed, 1.0);
        final panel = await d.menu(PlayerMenuSection.speed);
        expect(panel.speed, 1.0);
        expect(panel.aspectMode, AspectMode.contain);
        final labels = [
          '0.5×',
          '0.75×',
          'Normal',
          '1.25×',
          '1.5×',
          '1.75×',
          '2.0×',
        ];
        for (final label in labels) {
          expect(
            find.text(label),
            label == 'Normal' ? findsNWidgets(2) : findsOneWidget,
          );
        }
        final ys = labels
            .map((label) => t.getCenter(find.text(label).last).dy)
            .toList();
        expect(ys, orderedEquals([...ys]..sort()));
        await d.closeMenu();
        const rates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 0.5];
        for (final rate in rates) {
          await d.speed(rate);
          expect(playerControls(t).speed, rate);
          expect(d.rates.last, rate);
          expect((await d.record(speed: rate))['speed'], rate);
        }
        expect(d.rates, rates);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'display queued resume writes sample latest speed and aspect inside the save lock',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      final oldStore = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? store;
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        store = await t.runAsync(SleepResumeWrites.install);
        store!.barrier = Completer<void>();
        await d.speed(1.25);
        await f.until(t, () => store!.entered);
        expect(recordedWrites(store), hasLength(1));
        expect(recordedWrites(store).single['speed'], 1.25);
        expect(recordedWrites(store).single['aspect'], 'contain');
        await d.aspect(AspectMode.aspect4_3);
        await d.speed(1.75);
        expect(recordedWrites(store), hasLength(1));
        store.release();
        await f.until(t, () => recordedWrites(store!).length >= 3);
        final records = recordedWrites(store);
        expect(
          records.skip(1).map((r) => (r['speed'], r['aspect'])),
          everyElement((1.75, '4:3')),
        );
        expect((await d.record())['speed'], 1.75);
        expect((await d.record())['aspect'], '4:3');
      } finally {
        store?.release();
        await f.close(t);
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  testWidgets(
    'display temporary 2x never persists and queued hold saves sample after release and speed change',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = DisplayModeDriver(t, f);
      final oldStore = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? store;
      try {
        await d.defaults();
        await f.mount(t, displayScreen());
        await d.speed(1.5);
        expect((await d.record(speed: 1.5))['speed'], 1.5);
        store = await t.runAsync(SleepResumeWrites.install);
        store!.barrier = Completer<void>();
        await d.startHold();
        expect(playerControls(t).speed, 2.0);
        await d.aspect(AspectMode.cover);
        await f.until(t, () => store!.entered);
        expect(recordedWrites(store).single['speed'], 1.5);
        expect(recordedWrites(store).single['aspect'], 'cover');
        await d.aspect(AspectMode.aspect4_3);
        await d.endHold();
        expect(playerControls(t).speed, 1.5);
        await d.speed(0.75);
        expect(recordedWrites(store), hasLength(1));
        store.release();
        await f.until(t, () => recordedWrites(store!).length >= 3);
        final records = recordedWrites(store);
        expect(
          records.skip(1).map((r) => (r['speed'], r['aspect'])),
          everyElement((0.75, '4:3')),
        );
        expect(records.map((r) => r['speed']), isNot(contains(2.0)));
        expect((await d.record())['speed'], 0.75);
        expect(speedHudOpacity(t), 0.0);
      } finally {
        store?.release();
        await f.close(t);
        SharedPreferencesStorePlatform.instance = oldStore;
      }
    },
  );

  for (final speed in [1.0, 2.0]) {
    testWidgets(
      'display playlist resume speed $speed restores aspect zoom and preserves the 1x skip',
      (t) async {
        final f = VideoPlayerEnvironment(native: true);
        await t.runAsync(f.initialize);
        final d = DisplayModeDriver(t, f);
        const playlist = [
          PlaylistEntry(
            url: 'https://player.test/display-first.mp4',
            title: 'Display.S01E01.mkv',
          ),
          PlaylistEntry(
            url: 'https://player.test/display-second.mp4',
            title: 'Display.S01E02.mkv',
          ),
        ];
        try {
          await d.defaults();
          await f.mount(t, displayScreen(playlist: playlist));
          await d.speed(1.5);
          expect(d.rates, [1.5]);
          playerControls(t).onShowPlaylist();
          await f.until(
            t,
            () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
          );
          final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
          expect(browser.seriesPlaylist.allEpisodes, hasLength(2));
          await t.runAsync(
            () => SeriesProgressStorage.saveSeriesPlaybackState(
              seriesTitle: browser.seriesPlaylist.seriesTitle!,
              imdbId: browser.seriesPlaylist.imdbId,
              season: 1,
              episode: 2,
              positionMs: 120000,
              durationMs: 1200000,
              speed: speed,
              aspect: speed == 1.0 ? '4:3' : 'cinemaZoom',
            ),
          );
          unawaited(browser.onEpisodeSelected(1, 2));
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
          );
          for (var i = 0; i < 20; i++) {
            await f.advance(t, const Duration(milliseconds: 100));
          }
          if (find.byType(SeriesBrowser).evaluate().isNotEmpty) {
            f.navigator.currentState!.pop();
            await f.advance(t, const Duration(milliseconds: 350));
          }
          expect(d.rates, speed == 1.0 ? [1.5] : [1.5, 2.0]);
          expect(playerControls(t).speed, speed == 1.0 ? 1.5 : 2.0);
          d.expectAspect(
            speed == 1.0 ? AspectMode.aspect4_3 : AspectMode.cinemaZoom,
            speed == 1.0 ? BoxFit.cover : BoxFit.contain,
            speed == 1.0 ? 4 / 3 : null,
          );
          expect(
            (f.player.platform as FakeNativePlayer).properties['video-zoom'],
            speed == 1.0 ? '0.000000' : '0.415037',
          );
          expect(
            f.player.calls.where((c) => c.$1 == 'seek').last.$2,
            const Duration(seconds: 120),
          );
        } finally {
          await f.close(t);
        }
      },
    );
  }
}
