import 'package:debrify/screens/video_player/widgets/channel_guide.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final kind in ['debrify', 'stremio', 'episodes']) {
    testWidgets(
      'P17 TV dock $kind retained callbacks, stable tear-offs and Back',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        var switches = 0;
        try {
          PlatformUtil.debugSetAndroidTvCached(true);
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Show.S01E01.mkv',
              channelDirectory: kind == 'debrify' ? tvDirectory : null,
              requestChannelById: kind == 'debrify' ? (id) async => null : null,
              requestNextChannel: kind == 'debrify'
                  ? () async {
                      switches++;
                      return {'url': 'https://player.test/next.mp4'};
                    }
                  : null,
              stremioTvChannels: kind == 'stremio' ? tvDirectory : null,
              stremioTvChannelSwitchProvider: kind == 'stremio'
                  ? (id) async => null
                  : null,
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              seriesSourceFetcher: kind == 'episodes'
                  ? SeriesSourceFetcher(
                      season: 1,
                      episode: 1,
                      searchEpisodes: (s, e) async => [],
                      searchPacks: (s, e) async => [],
                    )
                  : null,
              resolveSourceToPlaylist: kind == 'episodes'
                  ? (s, {canContinue}) async => []
                  : null,
            ),
          );
          final first = t.widget<TvControls>(find.byType(TvControls));
          if (kind == 'episodes') {
            first.onShowPlaylist!();
            await d.f.advance(t, const Duration(milliseconds: 500));
            expect(find.byType(BottomSheet), findsOneWidget);
            Navigator.of(t.element(find.byType(VideoPlayerScreen))).pop();
            await d.f.advance(t, const Duration(milliseconds: 500));
          } else {
            first.onShowGuide!();
            await d.f.advance(t, const Duration(milliseconds: 400));
            if (kind == 'debrify') {
              expect(find.byType(ChannelGuide), findsOneWidget);
            } else {
              expect(find.byType(StremioTvGuideSheet), findsOneWidget);
            }
            await t.binding.handlePopRoute();
            await d.f.advance(t);
            expect(find.byType(ChannelGuide), findsNothing);
            expect(find.byType(StremioTvGuideSheet), findsNothing);
            expect(
              FocusManager.instance.primaryFocus?.debugLabel,
              'tvPlayerRoot',
            );
            // The same collaborator receiver must keep tear-off equality after a rebuild.
            d.player.emit('duration', const Duration(seconds: 1500));
            await d.f.advance(t);
            final again = t.widget<TvControls>(find.byType(TvControls));
            expect(again.onShowGuide, first.onShowGuide);
            if (kind == 'debrify') {
              expect(again.onNextChannel, first.onNextChannel);
              final dynamic next = again.onNextChannel!;
              await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
              expect(switches, 1);
            }
          }
        } finally {
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
  for (final kind in ['debrify', 'stremio']) {
    for (final key in [LogicalKeyboardKey.keyG, LogicalKeyboardKey.arrowUp]) {
      testWidgets('P17 desktop $key opens $kind guide and escape closes', (
        t,
      ) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: kind == 'debrify' ? tvDirectory : null,
              requestChannelById: kind == 'debrify' ? (id) async => null : null,
              stremioTvChannels: tvDirectory,
              stremioTvChannelSwitchProvider: (id) async => null,
            ),
          );
          await d.f.key(t, key);
          expect(
            kind == 'debrify'
                ? find.byType(ChannelGuide)
                : find.byType(StremioTvGuideSheet),
            findsOneWidget,
          );
          if (key == LogicalKeyboardKey.keyG) {
            t
                .widget<Focus>(
                  find.byWidgetPredicate(
                    (w) =>
                        w is Focus && w.focusNode?.debugLabel == 'tvPlayerRoot',
                  ),
                )
                .focusNode!
                .requestFocus();
            await d.f.advance(t);
          }
          await d.f.key(t, LogicalKeyboardKey.escape);
          expect(find.byType(ChannelGuide), findsNothing);
          expect(find.byType(StremioTvGuideSheet), findsNothing);
        } finally {
          await d.close();
        }
      });
    }
  }
  testWidgets('P17 desktop page up invokes next channel retained key caller', (
    t,
  ) async {
    final d = TvEpisodeDriver(t);
    await d.initialize();
    var requests = 0;
    try {
      await d.mount(
        screen: VideoPlayerScreen(
          videoUrl: 'https://player.test/a.mp4',
          title: 'A',
          requestNextChannel: () async {
            requests++;
            return {'url': 'https://player.test/next.mp4'};
          },
        ),
      );
      await d.f.key(t, LogicalKeyboardKey.pageUp);
      await d.f.until(
        t,
        () => d.opens.last.uri == 'https://player.test/next.mp4',
      );
      expect(requests, 1);
    } finally {
      await d.close();
    }
  });
  for (final kind in ['debrify', 'stremio']) {
    testWidgets(
      'P17 hidden TV bar up opens $kind guide with feature precedence',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          PlatformUtil.debugSetAndroidTvCached(true);
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: kind == 'debrify' ? tvDirectory : null,
              requestChannelById: kind == 'debrify' ? (id) async => null : null,
              stremioTvChannels: tvDirectory,
              stremioTvChannelSwitchProvider: (id) async => null,
            ),
          );
          await d.f.advance(t, const Duration(seconds: 4));
          expect(
            t
                .widget<ExcludeFocus>(
                  find
                      .ancestor(
                        of: find.byType(TvControls),
                        matching: find.byType(ExcludeFocus),
                      )
                      .first,
                )
                .excluding,
            isTrue,
          );
          await d.f.key(t, LogicalKeyboardKey.arrowUp);
          expect(
            kind == 'debrify'
                ? find.byType(ChannelGuide)
                : find.byType(StremioTvGuideSheet),
            findsOneWidget,
          );
          await t.binding.handlePopRoute();
          await d.f.advance(t);
          expect(find.byType(ChannelGuide), findsNothing);
          expect(find.byType(StremioTvGuideSheet), findsNothing);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
        }
      },
    );
  }
}
