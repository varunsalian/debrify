import 'dart:async';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'support/tv_episode_driver.dart';
import 'support/player_actions.dart';

void main() {
  for (final kind in [
    'valid channel',
    'missing sources',
    'empty sources',
    'negative index',
    'past end',
    'missing identity',
  ]) {
    testWidgets(
      'P17 progress prefetch guards $kind at the real channel position subscription',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final probe = _PreparationProbe();
        final source = episodeSource('Unidentified channel stream');
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'Unknown',
              seriesSourceFetcher: probe,
              stremioTvChannels: tvDirectory,
              stremioTvChannelSwitchProvider: (id) async => null,
            ),
          );
          final guide = await d.stremioGuide();
          await d.stremioPick(
            guide,
            'b',
            sources: kind == 'missing sources'
                ? null
                : kind == 'empty sources'
                ? []
                : [source],
            sourceIndex: kind == 'negative index'
                ? -1
                : kind == 'past end'
                ? 4
                : 0,
            season: kind == 'missing identity' ? null : 2,
            episode: kind == 'missing identity' ? null : 3,
          );
          expect(playerControls(t).isPlaying, isTrue);
          expect(find.byType(mkv.Video), findsOneWidget);
          probe.calls.clear();
          final seeks = d.seeks.length;
          d.player.emit('duration', const Duration(seconds: 200));
          d.player.emit('position', const Duration(seconds: 130));
          await d.f.advance(t);
          if (kind == 'valid channel') {
            expect(probe.calls, [(source, 2, 3, 130000, 200000)]);
          } else {
            expect(probe.calls, isEmpty);
          }
          expect(d.seeks.length, seeks);
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P17 removing the live widget fetcher stops subsequent progress preparation',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final probe = _PreparationProbe();
      final source = episodeSource('Show.S02E03');
      VideoPlayerScreen screen(SeriesSourceFetcher? fetcher) =>
          VideoPlayerScreen(
            videoUrl: source.directUrl!,
            title: source.displayTitle,
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            stremioSources: [source],
            seriesSourceFetcher: fetcher,
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          );
      try {
        await d.mount(screen: screen(probe));
        probe.calls.clear();
        d.player.emit('duration', const Duration(seconds: 200));
        d.player.emit('position', const Duration(seconds: 130));
        await d.f.advance(t);
        expect(probe.calls, hasLength(1));
        probe.calls.clear();
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: d.f.navigator,
            theme: ThemeData.dark(),
            home: screen(null),
          ),
        );
        await d.f.advance(t);
        d.player.emit('position', const Duration(seconds: 140));
        await d.f.advance(t);
        expect(probe.calls, isEmpty);
        expect(d.opens, hasLength(1));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 transition alone blocks preparation while a held provider receives a playing event',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final probe = _PreparationProbe();
      final source = episodeSource('Show.S02E03');
      final payload = Completer<Map<String, dynamic>?>();
      Future<dynamic>? task;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: source.directUrl!,
            title: source.displayTitle,
            contentType: 'series',
            contentSeason: 2,
            contentEpisode: 3,
            stremioSources: [source],
            seriesSourceFetcher: probe,
            requestNextChannel: () => payload.future,
            resolveSourceToPlaylist: (s, {canContinue}) async => [],
          ),
        );
        task = d.beginNextChannel();
        await d.f.actions.settle(t);
        d.player.state = d.player.state.copyWith(playing: true);
        d.player.emit('playing', true);
        await d.f.advance(t);
        expect(playerControls(t).isPlaying, isTrue);
        probe.calls.clear();
        d.player.emit('duration', const Duration(seconds: 200));
        d.player.emit('position', const Duration(seconds: 130));
        await d.f.advance(t);
        expect(probe.calls, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        if (!payload.isCompleted) payload.complete(null);
        if (task != null) await d.f.finish(t, task);
        await d.close();
      }
    },
  );
  testWidgets(
    'P17 startup validation blocks preparation until the initial frame is accepted',
    (t) async {
      final d = TvEpisodeDriver(
        t,
        configurePlayer: (player) {
          player.onOpen = () {};
        },
      );
      await d.initialize();
      final probe = _PreparationProbe();
      final source = episodeSource('Show.S02E03');
      final committed = <Torrent>[];
      try {
        t.view.physicalSize = const Size(1280, 800);
        t.view.devicePixelRatio = 1;
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(
              navigatorKey: d.f.navigator,
              theme: ThemeData.dark(),
              home: VideoPlayerScreen(
                videoUrl: source.directUrl!,
                title: source.displayTitle,
                contentType: 'series',
                contentSeason: 2,
                contentEpisode: 3,
                stremioSources: [source],
                seriesSourceFetcher: probe,
                startupFailoverEnabled: true,
                onStremioSourceCommitted: (s) async {
                  committed.add(s);
                },
                resolveSourceToPlaylist: (s, {canContinue}) async => [],
              ),
            ),
          ),
        );
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(t, () => d.opens.isNotEmpty);
        d.player.emit('playing', true);
        d.player.emit('duration', const Duration(seconds: 200));
        d.player.emit('position', const Duration(seconds: 130));
        await d.f.advance(t);
        expect(d.player.state.playing, isTrue);
        expect(committed, isEmpty);
        expect(probe.calls, isEmpty);
        d.player.publishFrame();
        d.f.controllers.last.publishFrame();
        await d.f.until(t, () => committed.isNotEmpty);
        expect(committed, [source]);
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
        expect(playerControls(t).isPlaying, isTrue);
        probe.calls.clear();
        d.player.emit('duration', const Duration(seconds: 200));
        d.player.emit('position', const Duration(seconds: 140));
        await d.f.advance(t);
        expect(probe.calls, [(source, 2, 3, 140000, 200000)]);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

class _PreparationProbe extends SeriesSourceFetcher {
  _PreparationProbe()
    : super(
        season: 2,
        episode: 3,
        searchEpisodes: (s, e) async => [],
        searchPacks: (s, e) async => [],
        prepareNextDirectEpisode: (s, e, source) async {},
      );
  final calls = <(Torrent, int, int, int, int)>[];
  @override
  Future<void> prepareFromProgress({
    required Torrent source,
    required int season,
    required int episode,
    required int positionMs,
    required int durationMs,
  }) {
    calls.add((source, season, episode, positionMs, durationMs));
    return super.prepareFromProgress(
      source: source,
      season: season,
      episode: episode,
      positionMs: positionMs,
      durationMs: durationMs,
    );
  }
}
