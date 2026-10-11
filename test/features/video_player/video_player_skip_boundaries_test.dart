import 'dart:async';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/skip_segment_button.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/series_progress_storage.dart';
import 'package:debrify/screens/video_player/services/skip_segment_ui_controller.dart';
import 'package:debrify/services/skip_segment_service.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/skip_segment_driver.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

const skipPlaylist = [
  PlaylistEntry(
    url: 'https://player.test/one.mp4',
    title: 'Fixture.S01E01.mkv',
  ),
  PlaylistEntry(
    url: 'https://player.test/two.mp4',
    title: 'Fixture.S01E02.mkv',
  ),
  PlaylistEntry(url: '', title: 'Fixture.S01E03.mkv'),
];

void main() {
  testWidgets(
    'skip playlist episode wins over launch arguments and switches wait for real duration',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      final open = Completer<void>();
      try {
        await d.configure(hold: true, seriesMetadata: true);
        await f.mount(t, skipScreen(playlist: skipPlaylist));
        d.expectQuery(season: 1, episode: 1);
        await d.release(0);
        await d.tick();
        d.expectButton(true);
        final clock = playerControls(t).clock;
        final generation = clock.value.generation;
        final notifier = d.notifier;
        final skipAtBoundary = <SkipSegment?>[];
        void observeMediaClock() {
          if (clock.value.generation != generation) {
            skipAtBoundary.add(notifier.value);
          }
        }

        clock.addListener(observeMediaClock);
        f.player.delays['open'] = open;
        await d.next();
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        clock.removeListener(observeMediaClock);
        expect(skipAtBoundary, isNotEmpty);
        expect(skipAtBoundary, everyElement(isNull));
        d.expectButton(false);
        await d.tick();
        expect(d.requests, hasLength(1));
        f.player.onOpen = () {};
        open.complete();
        // Let readiness and the transition finish without an incoming duration.
        // The State still holds the outgoing positive duration in this window.
        for (var frame = 0; frame < 20; frame++) {
          await f.advance(t, const Duration(milliseconds: 100));
          await d.tick();
        }
        d.expectButton(false);
        expect(d.requests, hasLength(1));
        await d.duration(Duration.zero);
        await d.tick();
        d.expectButton(false);
        expect(d.requests, hasLength(1));
        await d.duration(const Duration(seconds: 900));
        for (var frame = 0; frame < 10; frame++) {
          await f.advance(t, const Duration(milliseconds: 100));
        }
        await d.tick();
        expect(d.requests, hasLength(2));
        d.expectQuery(season: 1, episode: 2, seconds: 900, index: 1);
        await d.release(1);
        await d.tick();
        d.expectButton(true);
      } finally {
        if (!open.isCompleted) open.complete();
        f.player.delays.remove('open');
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip failed playlist load re-arms prior current media without a duration event',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(seriesMetadata: true);
        await f.mount(t, skipScreen(playlist: skipPlaylist));
        await d.tick();
        d.expectButton(true);
        f.player.onOpen = () {};
        await d.next();
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        await d.tick();
        expect(d.requests, hasLength(1));
        d.expectButton(false);
        await d.next();
        for (var frame = 0; frame < 100; frame++) {
          await f.advance(t, const Duration(milliseconds: 100));
          await d.tick();
          if (d.requests.length == 2) break;
        }
        await d.tick();
        expect(d.requests, hasLength(2));
        d.expectQuery(season: 1, episode: 2, index: 1);
        d.expectButton(true);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets('skip playlist reset preserves cached episode on return', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final d = SkipSegmentDriver(t, f);
    try {
      await d.configure(hold: true, seriesMetadata: true);
      await f.mount(t, skipScreen(playlist: skipPlaylist));
      await d.release(0);
      await d.tick();
      d.expectButton(true);
      f.player.onOpen = () {};
      await d.next();
      await f.until(
        t,
        () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
      );
      for (var frame = 0; frame < 20; frame++) {
        await f.advance(t, const Duration(milliseconds: 100));
        await d.tick();
      }
      await d.duration(const Duration(seconds: 1000));
      await d.tick();
      expect(d.requests, hasLength(2));
      await d.release(1, reply: skipReply(start: 40, end: 60));
      await d.tick(45);
      d.expectButton(true);
      playerControls(t).onPrevious!();
      await f.until(
        t,
        () => f.player.calls.where((c) => c.$1 == 'open').length == 3,
      );
      for (var frame = 0; frame < 20; frame++) {
        await f.advance(t, const Duration(milliseconds: 100));
        await d.tick();
      }
      await d.duration(const Duration(seconds: 1200));
      await d.tick();
      expect(d.requests, hasLength(2));
      d.expectButton(true);
    } finally {
      d.releaseAll();
      await f.close(t);
    }
  });

  testWidgets(
    'skip playlist reset reloads same-key cache after no-frame detour',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true, seriesMetadata: true);
        await f.mount(t, skipScreen(playlist: skipPlaylist));
        await d.release(0);
        await d.tick();
        d.expectButton(true);
        f.player.onOpen = () {};
        await d.next();
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        for (var frame = 0; frame < 20; frame++) {
          await f.advance(t, const Duration(milliseconds: 100));
          await d.tick();
        }
        expect(d.requests, hasLength(1));
        playerControls(t).onPrevious!();
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 3,
        );
        for (var frame = 0; frame < 20; frame++) {
          await f.advance(t, const Duration(milliseconds: 100));
          await d.tick();
        }
        await d.duration(const Duration(seconds: 1200));
        await d.tick();
        expect(d.requests, hasLength(1));
        d.expectButton(true);
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip request falls back to guide IMDb and accepts series playlist without catalog type',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(
          t,
          skipScreen(
            id: 'invalid',
            type: null,
            season: 9,
            episode: 9,
            playlist: skipPlaylist,
          ),
        );
        expect(d.requests, isEmpty);
        playerControls(t).onShowPlaylist();
        await f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        browser.seriesPlaylist.imdbId = ' tt7654321 ';
        await t.tapAt(const Offset(10, 10));
        await f.advance(t, const Duration(milliseconds: 400));
        await d.tick();
        expect(d.requests, hasLength(1));
        d.expectQuery(id: 'tt7654321', season: 1, episode: 1);
        d.expectButton(true);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip unknown persisted provider normalizes to auto before settings load',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await t.runAsync(() async {
          final prefs = await ProfilePreferences.instance();
          await prefs.setString('skip_segment_provider', 'unavailable');
        });
        await f.mount(t, skipScreen());
        await d.tick();
        d.expectButton(true);
        d.expectQuery();
        expect(
          f.network.requests.where((r) => r.url.host == 'api.introdb.app'),
          isNotEmpty,
        );
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip clamps to subsecond duration using the same whole-second request key',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await d.duration(const Duration(milliseconds: 1199900));
        await d.release(1, reply: skipReply(start: 1100, end: 1199.9));
        await d.tick(1105);
        d.expectButton(true);
        await d.duration(const Duration(milliseconds: 1199500));
        expect(d.requests, hasLength(2));
        d.expectButton(true);
        final clock = playerControls(t).clock;
        t.widget<SkipSegmentButton>(find.byType(SkipSegmentButton)).onPressed();
        expect(clock.value.position, const Duration(milliseconds: 1199500));
        expect(
          f.player.calls.where((c) => c.$1 == 'seek').last.$2,
          const Duration(milliseconds: 1199500),
        );
        await f.advance(t);
        // The old segment end is still beyond the shortened same-key duration.
        d.expectButton(true);
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip engine media boundary clears UI on direct source change independently of playlist reset',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      final open = Completer<void>();
      final a = source('Original', 'https://player.test/original.mp4');
      final b = source('Replacement', 'https://player.test/replacement.mp4');
      try {
        await d.configure();
        await f.mount(
          t,
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'Skip source',
            contentImdbId: 'tt4100000',
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            stremioSources: [a, b],
            stremioCurrentSourceIndex: 0,
            resolveStremioSource: (s) async => s.directUrl,
          ),
        );
        await d.tick();
        d.expectButton(true);
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        f.player.delays['open'] = open;
        sheet.onSourceSelected(1, b.directUrl!);
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        d.expectButton(false);
        await d.tick();
        d.expectButton(false);
        open.complete();
        await f.advance(t);
        await f.advance(t);
      } finally {
        if (!open.isCompleted) open.complete();
        f.player.delays.remove('open');
        await f.close(t);
      }
    },
  );
  testWidgets(
    'skip suspended native seek immediately clears UI and disposal saves target position',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      final seek = Completer<void>();
      try {
        await d.configure();
        await f.mount(t, skipScreen());
        await d.tick();
        d.expectButton(true);
        f.player.delays['seek'] = seek;
        t.widget<SkipSegmentButton>(find.byType(SkipSegmentButton)).onPressed();
        await f.advance(t);
        d.expectButton(false);
        expect(f.player.state.position, const Duration(seconds: 15));
        expect(
          playerControls(t).clock.value.position,
          const Duration(seconds: 30),
        );
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        final saved = await t.runAsync(
          () => SeriesProgressStorage.getSeriesPlaybackState(
            seriesTitle: 'Skip fixture',
            imdbId: 'tt4100000',
            season: 2,
            episode: 3,
          ),
        );
        expect(saved?['positionMs'], 30000);
        seek.complete();
        await f.advance(t);
      } finally {
        if (!seek.isCompleted) seek.complete();
        f.player.delays.remove('seek');
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip notifier borrowed by rendered builder is disposed with its State owner',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(t, skipScreen());
        await d.tick();
        final builder = t.widget<ValueListenableBuilder<SkipSegment?>>(
          find.byWidgetPredicate(
            (w) =>
                w is ValueListenableBuilder<SkipSegment?> &&
                w.valueListenable is SkipSegmentUiController,
          ),
        );
        final notifier = builder.valueListenable as SkipSegmentUiController;
        void listener() {}
        expect(() => notifier.addListener(listener), returnsNormally);
        notifier.removeListener(listener);
        await t.pumpWidget(const SizedBox.shrink());
        await f.until(t, () => f.player.disposed.isCompleted);
        expect(() => notifier.addListener(listener), throwsFlutterError);
      } finally {
        await f.close(t);
      }
    },
  );
  for (final failure in [false, true]) {
    testWidgets(
      'skip playlist held A-B-A ${failure ? 'reset generation survives failed-load re-arm' : 'reset loading permits new same-key request'}',
      (t) async {
        final f = VideoPlayerEnvironment();
        await t.runAsync(f.initialize);
        final d = SkipSegmentDriver(t, f);
        try {
          await d.configure(hold: true, seriesMetadata: true);
          await f.mount(t, skipScreen(playlist: skipPlaylist));
          await d.tick();
          f.player.onOpen = () {};
          await d.next();
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
          );
          for (var frame = 0; frame < 20; frame++) {
            await f.advance(t, const Duration(milliseconds: 20));
          }
          expect(d.requests, hasLength(1));
          expect(playerControls(t).onPrevious, isNotNull);
          playerControls(t).onPrevious!();
          await f.until(
            t,
            () => f.player.calls.where((c) => c.$1 == 'open').length == 3,
          );
          for (var frame = 0; frame < 20; frame++) {
            await f.advance(t, const Duration(milliseconds: 20));
          }
          if (failure) {
            playerControls(t).onShowPlaylist();
            await f.until(
              t,
              () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
            );
            t
                .widget<SeriesBrowser>(find.byType(SeriesBrowser))
                .onEpisodeSelected(1, 3);
            for (var frame = 0; frame < 100; frame++) {
              await f.advance(t, const Duration(milliseconds: 20));
            }
            await d.release(0);
            d.expectButton(false);
            await d.tick();
            d.expectButton(true);
            expect(d.requests, hasLength(1));
          } else {
            await d.duration(const Duration(seconds: 1200));
            await d.tick();
            expect(d.requests, hasLength(2));
            d.expectQuery(season: 1, episode: 1, index: 1);
            await d.release(1);
            d.expectButton(true);
          }
        } finally {
          d.releaseAll();
          await f.close(t);
        }
      },
    );
  }
}
