import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:debrify/utils/episode_playback_request.dart';
import 'package:debrify/models/torrent.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/local_completion_driver.dart' show CompletionDelivery;
import 'support/tv_episode_driver.dart';

void main() {
  for (final route in ['debrify', 'stremio']) {
    testWidgets('P17 $route provider returns after disposal without opening', (
      t,
    ) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      final gate = Completer<Map<String, dynamic>?>();
      var requested = false;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            requestNextChannel: route == 'debrify'
                ? () {
                    requested = true;
                    return gate.future;
                  }
                : null,
            stremioTvCurrentChannelId: route == 'stremio' ? 'a' : null,
            stremioTvNextProvider: route == 'stremio'
                ? (id) {
                    requested = true;
                    return gate.future;
                  }
                : null,
          ),
        );
        final dynamic action = route == 'debrify'
            ? playerControls(t).onNextChannel!
            : playerControls(t).onNext!;
        final task = d.observe<dynamic>(() => action()) as Future<dynamic>;
        await d.f.until(t, () => requested);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => d.player.disposed.isCompleted);
        final opens = d.opens.length;
        gate.complete({'url': 'https://player.test/b.mp4'});
        await d.f.finish(t, task);
        expect(d.opens.length, opens);
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) {
          gate.complete(null);
        }
        await d.close();
      }
    });
  }
  for (final crossing in ['new navigation', 'dispose']) {
    for (final boundary in ['allow', 'resolver', 'open']) {
      testWidgets(
        'P17 fetch $boundary across $crossing rejects stale publication and pruning',
        (t) async {
          final d = TvEpisodeDriver(t);
          await d.initialize();
          final gate = Completer<void>();
          var entered = false;
          final candidate = episodeSource('Show.S01E03');
          Future<void> hold(String site) async {
            if (boundary == site && !entered) {
              entered = true;
              await gate.future;
            }
          }

          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/a.mp4',
                title: 'Show.S01E01.mkv',
                playlist: const [
                  PlaylistEntry(
                    url: 'https://player.test/a.mp4',
                    title: 'Show.S01E01.mkv',
                  ),
                  PlaylistEntry(
                    url: 'https://player.test/b.mp4',
                    title: 'Show.S01E02.mkv',
                  ),
                ],
                contentType: 'series',
                contentSeason: 1,
                contentEpisode: 1,
                seriesSourceFetcher: SeriesSourceFetcher(
                  season: 1,
                  episode: 1,
                  searchEpisodes: (s, e) async => [candidate],
                  searchPacks: (s, e) async => [],
                  validateCandidate: (s) async {
                    await hold('allow');
                    return true;
                  },
                ),
                resolveSourceToPlaylist: (s, {canContinue}) async {
                  await hold('resolver');
                  return [
                    PlaylistEntry(url: s.directUrl!, title: s.displayTitle),
                  ];
                },
              ),
            );
            final b = await d.browser();
            if (boundary == 'open') {
              d.player.beforeOperation = (name, value) async {
                if (name == 'open') {
                  await hold('open');
                }
              };
              d.player.heldOperation = (name, value) =>
                  name == 'open' && !gate.isCompleted;
            }
            final stale =
                d.observe<dynamic>(() => b.onEpisodeSelected(1, 3))
                    as Future<dynamic>;
            await d.f.until(t, () => entered);
            if (crossing == 'dispose') {
              await t.pumpWidget(const SizedBox.shrink());
              await d.f.until(t, () => d.player.disposed.isCompleted);
            } else {
              // Ordinary playlist selection owns a new navigation generation.
              final newer =
                  d.observe<dynamic>(() => b.onEpisodeSelected(1, 2))
                      as Future<dynamic>;
              if (boundary == 'open') {
                gate.complete();
                await d.f.finish(t, newer);
              } else {
                await d.f.finish(t, newer);
              }
            }
            if (!gate.isCompleted) {
              gate.complete();
            }
            await d.f.finish(t, stale);
            if (boundary != 'open') {
              expect(d.opens.any((m) => m.uri == candidate.directUrl), isFalse);
            }
            expect(d.errors, isEmpty);
            expect(
              d.logs.where(
                (s) =>
                    s.contains('next_episode_candidate_outcome') &&
                    s.contains('reason=committed'),
              ),
              isEmpty,
            );
          } finally {
            if (!gate.isCompleted) {
              gate.complete();
            }
            await d.close();
          }
        },
      );
    }
  }
  testWidgets(
    'P17 late Debrify percent tail reads duration of the newer channel',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var count = 0;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            startAtPercent: 0.25,
            channelDirectory: tvDirectory,
            requestNextChannel: () async => {
              'url': 'https://player.test/old.mp4',
            },
            requestChannelById: (id) async => {
              'url': 'https://player.test/new.mp4',
            },
          ),
        );
        final g = await d.debrifyGuide();
        g.onClose();
        await d.f.advance(t);
        d.player.onOpen = () {
          count++;
          if (count == 1) {
            d.player.emit('duration', Duration.zero);
          }
        };
        d.player.emit('duration', Duration.zero);
        await d.f.advance(t);
        final old = d.beginNextChannel();
        await d.f.until(
          t,
          () => d.opens.last.uri == 'https://player.test/old.mp4',
        );
        final before = d.seeks.length;
        await d.byId(g, g.channels.last);
        d.player.emit('duration', const Duration(seconds: 400));
        await d.f.advance(t, const Duration(milliseconds: 101));
        await d.f.finish(t, old);
        expect(d.opens.last.uri, 'https://player.test/new.mp4');
        expect(d.seeks.skip(before), [const Duration(seconds: 100)]);
      } finally {
        await d.close();
      }
    },
  );
  for (final route in ['debrify', 'stremio']) {
    testWidgets(
      'P17 held $route open failure after disposal preserves original error handling',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final gate = Completer<void>();
        var entered = false;
        Object? failure;
        var done = false;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              channelDirectory: route == 'debrify' ? tvDirectory : null,
              requestChannelById: route == 'debrify'
                  ? (id) async => null
                  : null,
              requestNextChannel: () async => {
                'url': 'https://player.test/b.mp4',
              },
              stremioTvChannels: tvDirectory,
              stremioTvChannelSwitchProvider: (id) async => null,
            ),
          );
          final dynamic action;
          if (route == 'stremio') {
            action = (await d.stremioGuide()).onChannelSwitched;
          } else {
            action = playerControls(t).onNextChannel!;
          }
          d.player.beforeOperation = (name, value) async {
            if (name == 'open') {
              entered = true;
              await gate.future;
            }
          };
          d.player.heldOperation = (name, value) =>
              name == 'open' && !gate.isCompleted;
          d.player.failures['open'] = StateError('held open failure');
          final Future<dynamic> task = route == 'stremio'
              ? action('b', 'https://player.test/b.mp4', 'B')
              : action();
          task.then<void>(
            (_) {
              done = true;
            },
            onError: (Object e) {
              failure = e;
              done = true;
            },
          );
          await d.f.until(t, () => entered);
          await t.pumpWidget(const SizedBox.shrink());
          await d.f.until(t, () => d.player.disposed.isCompleted);
          gate.complete();
          await d.f.until(t, () => done);
          if (route == 'debrify') {
            expect(failure, isA<FlutterError>());
          } else {
            expect(failure, isNull);
          }
          expect(d.logs.any((v) => v.contains('held open failure')), isTrue);
        } finally {
          if (!gate.isCompleted) {
            gate.complete();
          }
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P17 held ready-wait delivery seeks disposed fake after late next percent tail',
    (t) async {
      final d = TvEpisodeDriver(t);
      await d.initialize();
      var subtitleStart = 0;
      final ready = CompletionDelivery(
        'goToNextChannel',
        (v) =>
            v == null &&
            d.opens.length == 2 &&
            d.player.calls.where((c) => c.$1 == 'subtitle').length >
                subtitleStart,
      );
      ready.armed = false;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/a.mp4',
            title: 'A',
            startAtPercent: 0.25,
            requestNextChannel: () async => {
              'url': 'https://player.test/b.mp4',
            },
          ),
        );
        subtitleStart = d.player.calls.where((c) => c.$1 == 'subtitle').length;
        ready.armed = true;
        final dynamic next = playerControls(t).onNextChannel!;
        final Future<dynamic> task = d.observe<dynamic>(
          () => ready.run(() => next()),
        );
        await d.f.until(t, () => ready.pending.isNotEmpty);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => d.player.disposed.isCompleted);
        final before = d.seeks.length;
        ready.release();
        await d.f.finish(t, task);
        expect(d.seeks.skip(before), [const Duration(minutes: 5)]);
        expect(d.errors, isEmpty);
      } finally {
        ready.release();
        await d.close();
      }
    },
  );
  for (final crossing in ['new navigation', 'dispose']) {
    testWidgets(
      'P17 committed attempt delivery across $crossing skips synchronous retain publication',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final old = episodeSource('Show.S01E01');
        final pack = episodeSource(
          'Pack',
          type: StreamType.torrent,
          coverage: 'seasonPack',
          season: 1,
        );
        final candidate = episodeSource('Show.S01E03');
        final delivered = CompletionDelivery(
          'tryEpisodeCandidate',
          (v) => v == EpisodePlaybackOutcome.committed,
        );
        delivered.armed = false;
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: old.directUrl!,
              title: old.displayTitle,
              playlist: [
                PlaylistEntry(url: old.directUrl!, title: old.displayTitle),
                const PlaylistEntry(
                  url: 'https://player.test/two.mp4',
                  title: 'Show.S01E02.mkv',
                ),
              ],
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              stremioSources: [old, pack],
              seriesSourceFetcher: SeriesSourceFetcher(
                season: 1,
                episode: 1,
                searchEpisodes: (s, e) async => [candidate],
                searchPacks: (s, e) async => [],
              ),
              resolveSourceToPlaylist: (s, {canContinue}) async =>
                  s == candidate
                  ? [PlaylistEntry(url: s.directUrl!, title: s.displayTitle)]
                  : [],
            ),
          );
          final browser = await d.browser();
          delivered.armed = true;
          final Future<dynamic> task = d.observe<dynamic>(
            () => delivered.run(() => browser.onEpisodeSelected(1, 3)),
          );
          await d.f.until(t, () => delivered.pending.isNotEmpty);
          expect(d.opens.last.uri, candidate.directUrl);
          if (crossing == 'dispose') {
            await t.pumpWidget(const SizedBox.shrink());
            await d.f.until(t, () => d.player.disposed.isCompleted);
          } else {
            // Its old index is now outside the committed singleton playlist;
            // this accepted navigation still advances the real generation.
            await d.f.finish<dynamic>(
              t,
              d.observe<dynamic>(() => browser.onEpisodeSelected(1, 2)),
            );
          }
          delivered.release();
          await d.f.finish(t, task);
          if (crossing != 'dispose') {
            final sheet = await d.sourceSheet();
            expect(sheet.currentSourceIndex, 2);
            expect(sheet.sources.map((s) => s.name), [
              old.name,
              pack.name,
              candidate.name,
            ]);
          }
          expect(d.errors, isEmpty);
        } finally {
          delivered.release();
          await d.close();
        }
      },
    );
  }
}
