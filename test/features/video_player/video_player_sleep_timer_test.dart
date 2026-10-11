import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/screens/video_player/widgets/styled_dock.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/services/storage/player_appearance_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

const sleepScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/sleep.mp4',
  title: 'Sleep original',
  playlist: [
    PlaylistEntry(url: 'https://player.test/sleep.mp4', title: 'Sleep 1'),
    PlaylistEntry(url: 'https://player.test/next.mp4', title: 'Sleep 2'),
  ],
);

void main() {
  for (final tv in [false, true]) {
    testWidgets(
      'sleep menu and ${tv ? 'TV' : 'desktop'} dock preserve mode, preset and ceil label',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        if (!tv) {
          await t.runAsync(
            () => PlayerAppearanceStorage.setPlayerDockStyle('auto'),
          );
        }
        PlatformUtil.debugSetAndroidTvCached(tv);
        try {
          await f.mount(t, sleepScreen);
          if (tv) {
            expect(
              t.widget<TvControls>(find.byType(TvControls)).sleepTimerLabel,
              isNull,
            );
          } else {
            expect(playerControls(t).sleepTimerLabel, isNull);
          }
          var menu = await sleepMenu(t, f);
          expect(menu.sleepMode, SleepTimerMode.off);
          expect(menu.sleepArmedMinutes, 0);
          expect(menu.sleepMinutesLeft, 0);
          expect(menu.allowEndOfItem, isTrue);
          expect(find.byType(BottomSheet), findsNothing);
          expect(find.text('End of episode'), findsOneWidget);
          // Exercise the real menu row and its original selection callback.
          await t.tap(find.text('15 minutes'));
          await f.advance(t);
          await waitSleepToast(t, f, 'Sleep timer set for 15 minutes');
          menu = await sleepMenu(t, f);
          expect(menu.sleepMode, SleepTimerMode.countdown);
          expect(menu.sleepArmedMinutes, 15);
          expect(menu.sleepMinutesLeft, 15);
          menu.onClose();
          await f.advance(t, const Duration(milliseconds: 300));
          if (tv) {
            expect(
              t.widget<TvControls>(find.byType(TvControls)).sleepTimerLabel,
              '15 min',
            );
            expect(find.text('15 min'), findsOneWidget);
          } else {
            expect(playerControls(t).sleepTimerLabel, '15 min');
            expect(
              t.widget<StyledDock>(find.byType(StyledDock)).sleepTimerLabel,
              '15 min',
            );
            expect(find.byTooltip('Sleep timer · 15 min'), findsOneWidget);
          }
        } finally {
          await f.close(t);
        }
      },
    );
  }

  for (final mode in [SleepTimerMode.countdown, SleepTimerMode.endOfItem]) {
    testWidgets(
      'selection callback immediately rebuilds ${mode.name} menu and dock',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        try {
          await f.mount(t, sleepScreen);
          final menu = await sleepMenu(t, f);
          menu.onSleepSelected(SleepTimerSelection(mode, 15));
          await f.advance(t);
          final updated = t.widget<PlayerMenuPanel>(
            find.byType(PlayerMenuPanel),
          );
          expect(updated.sleepMode, mode);
          expect(
            updated.sleepArmedMinutes,
            mode == SleepTimerMode.countdown ? 15 : 0,
          );
          expect(
            updated.sleepMinutesLeft,
            mode == SleepTimerMode.countdown ? 15 : 0,
          );
          expect(
            playerControls(t).sleepTimerLabel,
            mode == SleepTimerMode.countdown ? '15 min' : 'Episode',
          );
        } finally {
          await f.close(t);
        }
      },
    );
  }

  testWidgets('off callback immediately rebuilds an armed menu and dock', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    try {
      await f.mount(t, sleepScreen);
      await pickSleep(
        t,
        f,
        const SleepTimerSelection(SleepTimerMode.countdown, 15),
      );
      final armed = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
      expect(armed.sleepMode, SleepTimerMode.countdown);
      expect(armed.sleepArmedMinutes, 15);
      expect(
        () => armed.onSleepSelected(SleepTimerSelection.off),
        returnsNormally,
      );
      await f.advance(t);
      final off = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
      expect(off.sleepMode, SleepTimerMode.off);
      expect(off.sleepArmedMinutes, 0);
      expect(off.sleepMinutesLeft, 0);
      expect(playerControls(t).sleepTimerLabel, isNull);
    } finally {
      await f.close(t);
    }
  });

  testWidgets('off cancels countdown and clears mode, preset and dock label', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    await t.runAsync(() => PlayerAppearanceStorage.setPlayerDockStyle('auto'));
    try {
      await f.mount(t, sleepScreen);
      await pickSleep(
        t,
        f,
        const SleepTimerSelection(SleepTimerMode.countdown, 1),
      );
      await f.advance(t, const Duration(seconds: 4));
      await pickSleep(t, f, SleepTimerSelection.off);
      await waitSleepToast(t, f, 'Sleep timer off');
      final menu = await sleepMenu(t, f);
      expect(menu.sleepMode, SleepTimerMode.off);
      expect(menu.sleepArmedMinutes, 0);
      expect(menu.sleepMinutesLeft, 0);
      menu.onClose();
      await f.advance(t);
      expect(playerControls(t).sleepTimerLabel, isNull);
      expect(
        t.widget<StyledDock>(find.byType(StyledDock)).sleepTimerLabel,
        isNull,
      );
      final pauses = f.player.calls.where((c) => c.$1 == 'pause').length;
      await f.advance(t, const Duration(minutes: 2));
      // If cancellation regresses, expiry must finish its asynchronous resume
      // save before pause can be observed. Drain those existing boundaries.
      for (var frame = 0; frame < 40; frame++) {
        await f.advance(t, const Duration(milliseconds: 20));
      }
      expect(f.player.calls.where((c) => c.$1 == 'pause').length, pauses);
    } finally {
      await f.close(t);
    }
  });

  testWidgets(
    're-arm replaces old countdown and fires only at the new expiry',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      try {
        await f.mount(t, sleepScreen);
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.countdown, 1),
        );
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.countdown, 2),
        );
        final pauses = f.player.calls.where((c) => c.$1 == 'pause').length;
        await f.advance(t, const Duration(minutes: 1));
        expect(f.player.calls.where((c) => c.$1 == 'pause').length, pauses);
        final menu = await sleepMenu(t, f);
        expect(menu.sleepArmedMinutes, 2);
        expect(menu.sleepMode, SleepTimerMode.countdown);
        menu.onClose();
        await f.advance(t);
        await f.advance(t, const Duration(minutes: 1));
        await f.until(
          t,
          () =>
              f.player.calls.where((c) => c.$1 == 'pause').length == pauses + 1,
        );
        await waitSleepToast(t, f, 'Sleep timer ended — paused');
        final ended = await sleepMenu(t, f);
        expect(ended.sleepMode, SleepTimerMode.off);
        expect(ended.sleepArmedMinutes, 0);
        expect(ended.sleepMinutesLeft, 0);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'end-of-item cancels countdown and EOF stops before playlist advance',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      try {
        await f.mount(t, sleepScreen);
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.countdown, 1),
        );
        await f.advance(t, const Duration(seconds: 4));
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.endOfItem),
        );
        await waitSleepToast(t, f, 'Stopping at the end of this episode');
        var menu = await sleepMenu(t, f);
        expect(menu.sleepMode, SleepTimerMode.endOfItem);
        expect(menu.sleepArmedMinutes, 0);
        expect(menu.sleepMinutesLeft, 0);
        menu.onClose();
        await f.advance(t);
        expect(playerControls(t).sleepTimerLabel, 'Episode');
        final opens = f.player.calls.where((c) => c.$1 == 'open').length;
        final pauses = f.player.calls.where((c) => c.$1 == 'pause').length;
        await f.advance(t, const Duration(minutes: 2));
        expect(f.player.calls.where((c) => c.$1 == 'pause').length, pauses);
        await f.advance(t, const Duration(seconds: 4));
        f.player.emit('completed', true);
        await waitSleepToast(t, f, 'Sleep timer — stopping here');
        expect(f.player.calls.where((c) => c.$1 == 'open').length, opens);
        expect(f.player.calls.where((c) => c.$1 == 'pause').length, pauses);
        menu = await sleepMenu(t, f);
        expect(menu.sleepMode, SleepTimerMode.off);
        menu.onClose();
        await f.advance(t);
        expect(playerControls(t).sleepTimerLabel, isNull);
        f.player.emit('completed', true);
        for (var i = 0; i < 20; i++) {
          await f.advance(t, const Duration(milliseconds: 20));
        }
        expect(
          f.player.calls.where((c) => c.$1 == 'open').length,
          opens,
          reason: 'the EOF sleep latch also blocks a later automatic advance',
        );
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets('end-of-item EOF returns before Xtream series channel advance', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final channels = [
      for (var episode = 1; episode <= 2; episode++)
        IptvChannel(
          name: 'Sleep S01E0$episode',
          url: 'https://iptv.test/sleep-episode-$episode.ts',
          contentType: 'series',
          attributes: const {
            'series_id': 'sleep',
            'series_playlist_id': 'fixture',
          },
        ),
    ];
    try {
      await f.mount(
        t,
        VideoPlayerScreen(
          videoUrl: channels[0].url,
          title: channels[0].name,
          iptvChannels: channels,
        ),
      );
      await pickSleep(
        t,
        f,
        const SleepTimerSelection(SleepTimerMode.endOfItem),
      );
      final opens = f.player.calls.where((c) => c.$1 == 'open').length;
      f.player.emit('completed', true);
      await waitSleepToast(t, f, 'Sleep timer — stopping here');
      await f.advance(t, const Duration(seconds: 2));
      expect(f.player.calls.where((c) => c.$1 == 'open').length, opens);
      expect(f.player.state.playlist.medias.single.uri, channels[0].url);
      final menu = await sleepMenu(t, f);
      expect(menu.sleepMode, SleepTimerMode.off);
    } finally {
      await f.close(t);
    }
  });

  for (final live in [true, false]) {
    testWidgets(
      'IPTV ${live ? 'live' : 'VOD'} menu gates end-of-item through the original caller',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final channel = IptvChannel(
          name: 'Sleep channel',
          url: 'https://iptv.test/sleep.ts',
          contentType: live ? 'live' : 'movie',
        );
        try {
          await f.mount(
            t,
            VideoPlayerScreen(
              videoUrl: channel.url,
              title: channel.name,
              iptvChannels: [channel],
            ),
          );
          final menu = await sleepMenu(t, f);
          expect(menu.allowEndOfItem, !live);
          expect(
            find.text('End of episode'),
            live ? findsNothing : findsOneWidget,
          );
          expect(menu.sleepMode, SleepTimerMode.off);
          expect(menu.sleepArmedMinutes, 0);
          expect(menu.sleepMinutesLeft, 0);
        } finally {
          await f.close(t);
        }
      },
    );
  }

  testWidgets('disposal cancels the armed countdown without firing later', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    await f.mount(t, sleepScreen);
    final errors = <Object>[];
    final menu = await sleepMenu(t, f);
    runZonedGuarded(() {
      menu.onSleepSelected(
        const SleepTimerSelection(SleepTimerMode.countdown, 1),
      );
    }, (error, stack) => errors.add(error));
    await f.advance(t);
    await f.close(t);
    final calls = List.of(f.player.calls);
    await t.pump(const Duration(minutes: 2));
    expect(t.takeException(), isNull);
    expect(errors, isEmpty);
    expect(f.player.calls, calls);
    expect(f.player.disposed.isCompleted, isTrue);
  });
}
