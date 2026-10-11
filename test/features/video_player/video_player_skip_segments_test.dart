import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/screens/video_player/widgets/skip_segment_button.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/player_actions.dart';
import 'support/skip_segment_driver.dart';
import 'support/video_player_environment.dart';

void main() {
  testWidgets(
    'skip settings enable one exact request and position ticks deduplicate it',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        expect(d.requests, hasLength(1));
        d.expectQuery();
        d.expectButton(false);
        for (var i = 0; i < 3; i++) {
          await d.tick();
        }
        expect(d.requests, hasLength(1));
        await d.release(0);
        d.expectButton(true);
        await d.tick();
        expect(d.requests, hasLength(1));
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  for (final entry in <(String, String?, String?, int?, int?, String)>[
    ('disabled', 'tt4100000', 'series', 2, 3, 'Skip fixture'),
    (
      'custom identity',
      const CustomSeriesIdentity('fixture', 'local-show').id,
      'series',
      2,
      3,
      'Skip fixture',
    ),
    ('non-series', 'tt4100000', 'movie', 2, 3, 'Skip fixture'),
    ('invalid IMDb', 'bad4100000', 'series', 2, 3, 'Skip fixture'),
    ('missing IMDb', null, 'series', 2, 3, 'Skip fixture'),
    ('negative season', 'tt4100000', 'series', -1, 3, 'Skip fixture'),
    ('zero episode', 'tt4100000', 'series', 2, 0, 'Skip fixture'),
    ('negative episode', 'tt4100000', 'series', 2, -1, 'Skip fixture'),
    ('missing season', 'tt4100000', 'series', null, 3, 'Unparseable file'),
    ('missing episode', 'tt4100000', 'series', 2, null, 'Unparseable file'),
    (
      'missing season episode',
      'tt4100000',
      'series',
      null,
      null,
      'Unparseable file',
    ),
  ]) {
    testWidgets('skip request rejects ${entry.$1}', (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(enabled: entry.$1 != 'disabled');
        await f.mount(
          t,
          skipScreen(
            id: entry.$2,
            type: entry.$3,
            season: entry.$4,
            episode: entry.$5,
            title: entry.$6,
          ),
        );
        await d.tick();
        expect(d.requests, isEmpty);
        d.expectButton(false);
      } finally {
        await f.close(t);
      }
    });
  }

  for (final season in [0, 7]) {
    testWidgets('skip request preserves season $season and trims IMDb', (
      t,
    ) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(
          t,
          skipScreen(id: '  tt4100000  ', season: season, episode: 8),
        );
        expect(d.requests, hasLength(1));
        d.expectQuery(season: season, episode: 8);
        await d.tick();
        d.expectButton(true);
      } finally {
        await f.close(t);
      }
    });
  }

  testWidgets('skip request falls back to parsed title season and episode', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    final d = SkipSegmentDriver(t, f);
    try {
      await d.configure();
      await f.mount(
        t,
        skipScreen(
          season: null,
          episode: null,
          title: 'Fixture.Show.S04E06.mkv',
        ),
      );
      expect(d.requests, hasLength(1));
      d.expectQuery(season: 4, episode: 6);
      await d.tick();
      d.expectButton(true);
    } finally {
      await f.close(t);
    }
  });

  testWidgets(
    'skip button uses loaded duration key and exact segment boundaries',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure(hold: true);
        await f.mount(t, skipScreen());
        await d.release(0);
        await d.tick(9);
        d.expectButton(false);
        await d.tick(10);
        d.expectButton(true);
        await d.tick(29);
        d.expectButton(true);
        await d.tick(30);
        d.expectButton(false);
        await d.tick();
        d.expectButton(true);
        await d.duration(const Duration(seconds: 1100));
        d.expectButton(false);
        expect(d.requests, hasLength(2));
        d.expectQuery(seconds: 1100, index: 1);
        await d.duration(Duration.zero);
        await d.tick();
        d.expectButton(false);
        expect(d.requests, hasLength(2));
        await d.release(1);
        d.expectButton(false);
      } finally {
        d.releaseAll();
        await f.close(t);
      }
    },
  );

  testWidgets(
    'skip action seeks and publishes clock immediately before native completion and haptic',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(t, skipScreen());
        await d.tick();
        d.expectButton(true);
        final clock = playerControls(t).clock;
        final before = f.channels.length;
        t.widget<SkipSegmentButton>(find.byType(SkipSegmentButton)).onPressed();
        expect(clock.value.position, const Duration(seconds: 30));
        expect(
          f.player.calls.where((c) => c.$1 == 'seek').last.$2,
          const Duration(seconds: 30),
        );
        await f.advance(t);
        d.expectButton(false);
        expect(
          f.channels
              .skip(before)
              .where(
                (c) =>
                    c.$1 == 'flutter/platform' &&
                    c.$2.method == 'HapticFeedback.vibrate',
              )
              .map((c) => c.$2.arguments),
          ['HapticFeedbackType.selectionClick'],
        );
        expect(find.text('00:30'), findsOneWidget);
      } finally {
        await f.close(t);
      }
    },
  );

  testWidgets('TV Select owns visible skip action while the bar is hidden', (
    t,
  ) async {
    final f = VideoPlayerEnvironment();
    await t.runAsync(f.initialize);
    PlatformUtil.debugSetAndroidTvCached(true);
    final d = SkipSegmentDriver(t, f);
    try {
      await d.configure();
      await f.mount(t, skipScreen());
      await d.tick();
      await f.advance(t, const Duration(seconds: 8));
      d.expectButton(true);
      final pauseCount = f.player.calls.where((c) => c.$1 == 'pause').length;
      final seekCount = f.player.calls.where((c) => c.$1 == 'seek').length;
      await f.key(t, LogicalKeyboardKey.select);
      expect(
        f.player.calls.where((c) => c.$1 == 'seek'),
        hasLength(seekCount + 1),
      );
      expect(
        f.player.calls.where((c) => c.$1 == 'seek').last.$2,
        const Duration(seconds: 30),
      );
      expect(
        f.player.calls.where((c) => c.$1 == 'pause'),
        hasLength(pauseCount),
      );
      d.expectButton(false);
    } finally {
      await f.close(t);
    }
  });
  testWidgets(
    'skip exact key distinguishes adjacent whole seconds while subsecond ticks share it',
    (t) async {
      final f = VideoPlayerEnvironment();
      await t.runAsync(f.initialize);
      final d = SkipSegmentDriver(t, f);
      try {
        await d.configure();
        await f.mount(t, skipScreen());
        await d.duration(const Duration(seconds: 1201));
        expect(d.requests, hasLength(2));
        d.expectQuery(seconds: 1201, index: 1);
        await d.duration(const Duration(milliseconds: 1201500));
        expect(d.requests, hasLength(2));
        await d.duration(const Duration(seconds: 1200));
        expect(d.requests, hasLength(2));
        await d.tick();
        d.expectButton(true);
      } finally {
        await f.close(t);
      }
    },
  );
}
