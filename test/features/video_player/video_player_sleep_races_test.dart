import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/sleep_timer_sheet.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/services/storage/video_progress_storage.dart';
import 'package:flutter/material.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/player_actions.dart';
import 'support/sleep_timer_driver.dart';
import 'support/video_player_environment.dart';

const raceScreen = VideoPlayerScreen(
  videoUrl: 'https://player.test/race.mp4',
  title: 'Sleep race',
);

void main() {
  testWidgets(
    'expiry awaits the real resume write before pause and clears the timer',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final previous = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? writes;
      try {
        await f.mount(t, raceScreen);
        await f.player.seek(const Duration(minutes: 3));
        await f.advance(t);
        writes = await t.runAsync(SleepResumeWrites.install);
        writes!.barrier = Completer<void>();
        final before = f.player.calls.where((c) => c.$1 == 'pause').length;
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.countdown),
        );
        await f.until(t, () => writes!.entered);
        expect(
          f.player.calls.where((c) => c.$1 == 'pause').length,
          before,
          reason: 'save must finish before pause',
        );
        expect(find.text('Sleep timer ended — paused'), findsNothing);
        writes.release();
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'pause').length > before,
        );
        expect(f.player.state.playing, isFalse);
        await waitSleepToast(t, f, 'Sleep timer ended — paused');
        final toast = t.widget<SnackBar>(find.byType(SnackBar));
        expect(toast.behavior, SnackBarBehavior.floating);
        expect(toast.duration, const Duration(seconds: 3));
        final saved = await t.runAsync(
          () => VideoProgressStorage.getVideoPlaybackState(
            videoTitle: 'Sleep race',
          ),
        );
        expect(saved?['positionMs'], 180000);
        expect(saved?['url'], raceScreen.videoUrl);
        final menu = await sleepMenu(t, f);
        expect(menu.sleepMode, SleepTimerMode.off);
        expect(menu.sleepArmedMinutes, 0);
        expect(menu.sleepMinutesLeft, 0);
      } finally {
        writes?.release();
        await f.close(t);
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );

  testWidgets('expiry awaits native pause before displaying its toast', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final pause = Completer<void>();
    try {
      await f.mount(t, raceScreen);
      f.player.delays['pause'] = pause;
      await pickSleep(
        t,
        f,
        const SleepTimerSelection(SleepTimerMode.countdown),
      );
      await f.until(
        t,
        () => f.player.calls.where((c) => c.$1 == 'pause').length == 1,
      );
      // Advance in small frames so the arm snackbar's entrance, lifetime and
      // exit finish. A large jump starts its lifetime only after that jump.
      for (var frame = 0; frame < 250; frame++) {
        await f.advance(t, const Duration(milliseconds: 20));
        expect(find.text('Sleep timer ended — paused'), findsNothing);
      }
      expect(pause.isCompleted, isFalse);
      expect(f.player.state.playing, isTrue);
      expect(find.text('Sleep timer ended — paused'), findsNothing);
      pause.complete();
      await waitSleepToast(t, f, 'Sleep timer ended — paused');
      expect(f.player.state.playing, isFalse);
    } finally {
      if (!pause.isCompleted) pause.complete();
      f.player.delays.remove('pause');
      await f.close(t);
    }
  });

  testWidgets(
    'in-flight expiry after dispose still calls disposed pause and reports its error without toast',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final previous = SharedPreferencesStorePlatform.instance;
      final errors = <Object>[];
      SleepResumeWrites? writes;
      try {
        await f.mount(t, raceScreen);
        writes = await t.runAsync(SleepResumeWrites.install);
        writes!.barrier = Completer<void>();
        final menu = await sleepMenu(t, f);
        runZonedGuarded(() {
          menu.onSleepSelected(
            const SleepTimerSelection(SleepTimerMode.countdown),
          );
        }, (error, stack) => errors.add(error));
        await f.until(t, () => writes!.entered);
        expect(f.player.calls.where((c) => c.$1 == 'pause'), isEmpty);
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(f.player.calls.last.$1, 'dispose');
        f.player.failures['pause'] = StateError(
          'native player already disposed',
        );
        writes.release();
        await f.until(t, () => errors.isNotEmpty);
        expect(errors, hasLength(1));
        expect(
          errors.single,
          isA<StateError>().having(
            (e) => e.message,
            'native rejection',
            'native player already disposed',
          ),
        );
        expect(f.player.calls.last.$1, 'pause');
        expect(f.player.calls.where((c) => c.$1 == 'pause'), hasLength(1));
        expect(find.text('Sleep timer ended — paused'), findsNothing);
      } finally {
        writes?.release();
        await f.close(t);
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );

  testWidgets(
    'in-flight expiry after dispose suppresses toast when native pause succeeds',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final previous = SharedPreferencesStorePlatform.instance;
      SleepResumeWrites? writes;
      final errors = <Object>[];
      try {
        await f.mount(t, raceScreen);
        writes = await t.runAsync(SleepResumeWrites.install);
        writes!.barrier = Completer<void>();
        final menu = await sleepMenu(t, f);
        runZonedGuarded(() {
          menu.onSleepSelected(
            const SleepTimerSelection(SleepTimerMode.countdown),
          );
        }, (error, stack) => errors.add(error));
        await f.advance(t);
        await f.until(t, () => writes!.entered);
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        writes.release();
        await f.until(t, () => f.player.calls.last.$1 == 'pause');
        await f.advance(t);
        expect(t.takeException(), isNull);
        expect(errors, isEmpty);
        expect(find.byType(SnackBar), findsNothing);
        expect(f.player.calls.where((c) => c.$1 == 'pause'), hasLength(1));
      } finally {
        writes?.release();
        await f.close(t);
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );

  testWidgets(
    'late overlapping EOF after disposal clears end mode before the next callback',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final previous = SharedPreferencesStorePlatform.instance;
      final previousPrint = debugPrint;
      final messages = <String>[];
      SleepResumeWrites? writes;
      try {
        await f.mount(
          t,
          const VideoPlayerScreen(
            videoUrl: 'https://player.test/race.mp4',
            title: 'Sleep late EOF',
            contentType: 'series',
            contentImdbId: 'tt4100000',
            contentSeason: 1,
            contentEpisode: 1,
          ),
        );
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.endOfItem),
        );
        writes = await t.runAsync(SleepResumeWrites.install);
        writes!.barrier = Completer<void>();
        debugPrint = (message, {wrapWidth}) {
          if (message != null) messages.add(message);
          previousPrint(message, wrapWidth: wrapWidth);
        };
        f.player.emit('completed', true);
        f.player.emit('completed', true);
        await f.until(
          t,
          () =>
              writes!.writes
                  .where((w) => w.$1.endsWith('playback_state_v1'))
                  .length >=
              2,
        );
        expect(
          messages.where(
            (m) => m == 'Player: Looking up next episode after S1E1',
          ),
          isEmpty,
        );
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        writes.release();
        await f.until(
          t,
          () => messages.contains('Player: Looking up next episode after S1E1'),
        );
        for (var frame = 0; frame < 40; frame++) {
          await f.advance(t, const Duration(milliseconds: 20));
        }
        // Existing defect: the first late EOF cancels end mode, so the second
        // enters the legacy next-episode lookup despite the disposed screen.
        expect(
          messages.where(
            (m) => m == 'Player: Looking up next episode after S1E1',
          ),
          hasLength(1),
        );
        expect(find.text('Sleep timer — stopping here'), findsNothing);
        expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
      } finally {
        writes?.release();
        debugPrint = previousPrint;
        await f.close(t);
        SharedPreferencesStorePlatform.instance = previous;
      }
    },
  );

  testWidgets(
    'sleep latch cancels an already queued automatic adjacent episode',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final next = Completer<({int season, int episode})?>();
      var requests = 0;
      var searches = 0;
      try {
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: raceScreen.videoUrl,
            title: raceScreen.title,
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              resolveAdjacentEpisode: (season, episode, direction) {
                requests++;
                return next.future;
              },
              searchPacks: (s, e) async {
                searches++;
                return [];
              },
              searchEpisodes: (s, e) async {
                searches++;
                return [];
              },
            ),
            resolveSourceToPlaylist: (candidate, {canContinue}) async => [],
          ),
        );
        f.player.emit('completed', true);
        await f.until(t, () => requests == 1);
        final opened = f.player.calls.where((c) => c.$1 == 'open').length;
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.countdown),
        );
        await waitSleepToast(t, f, 'Sleep timer ended — paused');
        next.complete((season: 1, episode: 2));
        await f.advance(t);
        await f.advance(t, const Duration(seconds: 3));
        expect(
          searches,
          0,
          reason: 'queued auto-next must reject the sleep stop before fetching',
        );
        expect(f.player.calls.where((c) => c.$1 == 'open').length, opened);
        expect(f.player.state.playing, isFalse);
      } finally {
        if (!next.isCompleted) next.complete(null);
        await f.close(t);
      }
    },
  );

  testWidgets('sleep latch outranks a pending live IPTV recovery retry', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final channel = IptvChannel(
      name: 'Sleep live',
      url: 'https://iptv.test/sleep.ts',
      contentType: 'live',
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
      final before = f.player.calls.where((c) => c.$1 == 'open').length;
      f.player.emit('completed', true);
      await f.until(
        t,
        () => f.player.calls.where((c) => c.$1 == 'open').length > before,
      );
      // Recovery's production debounce uses real wall time, too.
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 350)),
      );
      f.player.emit('completed', true);
      await f.advance(t);
      final opened = f.player.calls.where((c) => c.$1 == 'open').length;
      await pickSleep(
        t,
        f,
        const SleepTimerSelection(SleepTimerMode.countdown),
      );
      await waitSleepToast(t, f, 'Sleep timer ended — paused');
      await f.advance(t, const Duration(seconds: 6));
      f.player.emit('completed', true);
      await f.advance(t, const Duration(seconds: 20));
      expect(f.player.calls.where((c) => c.$1 == 'open').length, opened);
      expect(f.player.state.playing, isFalse);
    } finally {
      await f.close(t);
    }
  });

  testWidgets(
    'sleep latch blocks further recovery after an in-flight live open completes late',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final channel = IptvChannel(
        name: 'Late sleep live',
        url: 'https://iptv.test/late.ts',
        contentType: 'live',
      );
      final open = Completer<void>();
      try {
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: channel.url,
            title: channel.name,
            iptvChannels: [channel],
          ),
        );
        f.player.delays['open'] = open;
        final before = f.player.calls.where((c) => c.$1 == 'open').length;
        f.player.emit('completed', true);
        await f.until(
          t,
          () =>
              f.player.calls.where((c) => c.$1 == 'open').length == before + 1,
        );
        await pickSleep(
          t,
          f,
          const SleepTimerSelection(SleepTimerMode.countdown),
        );
        await waitSleepToast(t, f, 'Sleep timer ended — paused');
        expect(f.player.state.playing, isFalse);
        open.complete();
        await f.until(t, () => f.player.state.playing);
        // Original defect: the already-issued open(play: true) finishes after
        // the sleep pause. Pin it; extraction must not silently fix the race.
        expect(f.player.state.playing, isTrue);
        expect(f.player.calls.where((c) => c.$1 == 'pause'), hasLength(1));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 350)),
        );
        f.player.emit('completed', true);
        await f.advance(t, const Duration(seconds: 6));
        expect(f.player.calls.where((c) => c.$1 == 'open').length, before + 1);
      } finally {
        if (!open.isCompleted) open.complete();
        f.player.delays.remove('open');
        await f.close(t);
      }
    },
  );

  testWidgets(
    'end-of-item carried from VOD to live blocks recovery without treating live EOF as completion',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final channels = [
        IptvChannel(
          name: 'Sleep VOD',
          url: 'https://iptv.test/vod.ts',
          contentType: 'movie',
        ),
        IptvChannel(
          name: 'Sleep live',
          url: 'https://iptv.test/live.ts',
          contentType: 'live',
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
        final menu = await sleepMenu(t, f);
        menu.onClose();
        await f.advance(t);
        playerControls(t).onShowIptvChannels!();
        await f.advance(t);
        final guide = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        await f.finish(t, guide.onChannelSelected(channels, 1));
        guide.onClose();
        await f.advance(t);
        await f.until(
          t,
          () => f.player.state.playlist.medias.single.uri == channels[1].url,
        );
        final opened = f.player.calls.where((c) => c.$1 == 'open').length;
        f.player.emit('completed', true);
        await f.advance(t, const Duration(seconds: 6));
        expect(f.player.calls.where((c) => c.$1 == 'open').length, opened);
        expect(find.text('Sleep timer — stopping here'), findsNothing);
        final liveMenu = await sleepMenu(t, f);
        expect(liveMenu.sleepMode, SleepTimerMode.endOfItem);
        expect(liveMenu.allowEndOfItem, isFalse);
      } finally {
        await f.close(t);
      }
    },
  );
}
