import 'dart:async';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/stremio_tv_guide_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final mode in ['Debrify', 'Stremio']) {
    testWidgets(
      'P17 $mode zero start percent creates no duration-driven seek',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Launch',
              startAtPercent: 0,
              requestNextChannel: mode == 'Debrify'
                  ? () async => {'url': 'https://player.test/b.mp4'}
                  : null,
              stremioTvChannels: mode == 'Stremio' ? tvDirectory : null,
              stremioTvChannelSwitchProvider: mode == 'Stremio'
                  ? (id) async => null
                  : null,
            ),
          );
          final before = d.seeks.length;
          if (mode == 'Debrify') {
            await d.nextChannel();
          } else {
            await d.stremioPick(await d.stremioGuide(), 'b', startAtPercent: 0);
          }
          d.player.emit('duration', const Duration(seconds: 200));
          await d.f.advance(t);
          expect(d.opens.last.uri, 'https://player.test/b.mp4');
          expect(d.seeks.skip(before), isEmpty);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P17 Stremio next publishes its catalog title without a guide directory',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Launch file',
            contentTitle: 'Launch catalog',
            stremioTvCurrentChannelId: 'a',
            stremioTvNextProvider: (id) async => {
              'channelId': 'b',
              'url': 'https://player.test/b.mp4',
              'title': 'Channel b',
            },
          ),
        );
        expect(playerControls(t).title, 'Launch catalog');
        final dynamic next = playerControls(t).onNext!;
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
        expect(playerControls(t).onShowGuide, isNull);
        expect(playerControls(t).title, 'Channel b');
        expect(d.opens.last.uri, 'https://player.test/b.mp4');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 Stremio source resolver publishes capability and resolves the selected source',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final source = episodeSource('Incoming.S02E03');
      final calls = <Torrent>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            stremioTvChannels: tvDirectory,
            stremioTvChannelSwitchProvider: (id) async => null,
          ),
        );
        await d.stremioPick(
          await d.stremioGuide(),
          'b',
          sources: [source],
          resolver: (s) async {
            calls.add(s);
            return 'https://player.test/resolved.mp4';
          },
        );
        expect(find.byType(StremioTvGuideSheet), findsNothing);
        expect(playerControls(t).onShowStremioSources, isNotNull);
        final sheet = await d.sourceSheet();
        expect(sheet.sources, [source]);
        expect(
          await d.f.finish(t, sheet.resolveSource(source)),
          'https://player.test/resolved.mp4',
        );
        expect(calls, [source]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 Stremio held next-slot dedupe prevents episode-fetch fallback',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final payload = Completer<Map<String, dynamic>?>();
      var requests = 0;
      var fetches = 0;
      Future<dynamic>? task;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'Show.S01E01.mkv',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioTvCurrentChannelId: 'a',
            stremioTvNextProvider: (id) {
              requests++;
              return payload.future;
            },
            seriesSourceFetcher: SeriesSourceFetcher(
              season: 1,
              episode: 1,
              resolveAdjacentEpisode: (s, e, direction) async =>
                  (season: 1, episode: 2),
              searchEpisodes: (s, e) async {
                fetches++;
                return [episodeSource('Show.S01E02')];
              },
              searchPacks: (s, e) async => [],
            ),
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
            ],
          ),
        );
        final dynamic next = playerControls(t).onNext!;
        task = d.observe<dynamic>(() => next()) as Future<dynamic>;
        await d.f.until(t, () => requests == 1);
        await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
        expect(requests, 1);
        expect(fetches, 0);
        expect(d.opens, hasLength(1));
        expect(find.text('Loading next...'), findsOneWidget);
        payload.complete({
          'channelId': 'b',
          'url': 'https://player.test/b.mp4',
          'title': 'B',
        });
        await d.f.finish(t, task);
        expect(d.opens.last.uri, 'https://player.test/b.mp4');
        expect(d.errors, isEmpty);
      } finally {
        if (!payload.isCompleted) payload.complete(null);
        if (task != null) await d.f.finish(t, task);
        await d.close();
      }
    },
  );
  for (final route in ['next', 'by id', 'Stremio']) {
    testWidgets(
      'P17 $route channel subtitle failure retains its diagnostic source',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              requestNextChannel: route == 'next'
                  ? () async => {'url': 'https://player.test/b.mp4'}
                  : null,
              channelDirectory: route == 'by id' ? tvDirectory : null,
              requestChannelById: route == 'by id'
                  ? (id) async => {'url': 'https://player.test/b.mp4'}
                  : null,
              stremioTvChannels: route == 'Stremio' ? tvDirectory : null,
              stremioTvChannelSwitchProvider: route == 'Stremio'
                  ? (id) async => null
                  : null,
            ),
          );
          d.player.failures['subtitle'] = StateError(
            'p17 channel subtitle failure',
          );
          if (route == 'next') {
            await d.nextChannel();
          } else if (route == 'by id') {
            final guide = await d.debrifyGuide();
            await d.byId(guide, guide.channels.last);
          } else {
            await d.stremioPick(await d.stremioGuide(), 'b');
          }
          final source = route == 'next'
              ? 'next-channel-disable-auto'
              : route == 'by id'
              ? 'channel-switch-disable-auto'
              : 'stremio-tv-switch-disable-auto';
          expect(
            d.logs,
            contains(
              contains(
                '[SubtitleDiag] set FAILED source=$source requestedId=no error=Bad state: p17 channel subtitle failure',
              ),
            ),
          );
          expect(d.opens.last.uri, 'https://player.test/b.mp4');
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
