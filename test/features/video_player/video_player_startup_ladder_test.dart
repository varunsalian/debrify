import 'dart:async';

import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/widgets/playback_startup_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/startup_driver.dart';

void main() {
  for (final type in [null, 'live', 'movie', 'series']) {
    testWidgets(
      'P16 startup $type without sources uses one probe and the original gate boundary',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        try {
          await d.begin(d.screen(type: type));
          await d.openEntered();
          final vod = type == 'movie' || type == 'series';
          expect(
            find.byType(PlaybackStartupView),
            vod ? findsOneWidget : findsNothing,
          );
          expect(d.event('bypass'), hasLength(vod ? 0 : 1));
          expect(d.event('begin'), hasLength(vod ? 1 : 0));
          if (vod) {
            expect(
              d.event('begin').singleOrNull,
              contains('sourceCount=0 policy=single_candidate'),
            );
          }
          d.frame();
          await d.result();
          await d.initialized();
          await d.settle();
          expect(d.opens, ['https://startup.test/original.mp4']);
          expect(d.commits, isEmpty);
          expect(find.byType(PlaybackStartupView), findsNothing);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final policy in ['disabled', 'try-next off', 'one', 'three', 'ten']) {
    testWidgets(
      'P16 ranked ladder bounds its actual attempts with $policy policy',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        final limit = policy == 'three'
            ? 3
            : policy == 'ten'
            ? 10
            : 1;
        await d.rules(attempts: limit, tryNext: policy != 'try-next off');
        final sources = List.generate(11, (i) => startupSource('limit-$i'));
        for (final a in sources) {
          d.openFailures[a.directUrl!] = StateError('dead candidate');
        }
        try {
          await d.begin(
            d.screen(sources: sources, failover: policy != 'disabled'),
          );
          await d.f.until(t, () => d.event('exhausted').isNotEmpty);
          expect(d.opens, sources.take(limit).map((s) => s.directUrl));
          expect(d.event('candidate_open'), hasLength(limit));
          expect(d.event('candidate_result'), hasLength(limit));
          expect(
            d.event('exhausted').singleOrNull,
            contains('attempts=$limit maxAttempts=$limit sourceCount=11'),
          );
          expect(d.commits, isEmpty);
          expect(find.byType(PlaybackStartupView), findsNothing);
          expect(d.player.calls.where((c) => c.$1 == 'stop'), hasLength(limit));
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final route in ['direct_url', 'playlist', 'single_url']) {
    testWidgets(
      'P16 failover resolves $route, skips external rows without spending attempts and preserves headers',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        await d.rules();
        final first = startupSource('launch');
        final external = startupSource(
          'external',
          type: StreamType.externalUrl,
        );
        final winner = startupSource(
          'winner',
          url: route == 'direct_url' ? 'https://startup.test/winner.mp4' : '',
          headers: {'X-Source': 'row'},
        );
        final resolves = <String>[];
        d.openFailures[first.directUrl!] = StateError('first fails');
        try {
          await d.begin(
            d.screen(
              sources: [first, external, winner],
              failover: true,
              resolve: route != 'playlist'
                  ? (s) async {
                      resolves.add(s.name);
                      return 'https://startup.test/single.mp4';
                    }
                  : null,
              playlist: route == 'playlist'
                  ? (s, {canContinue}) async {
                      resolves.add(s.name);
                      expect(canContinue!(), isTrue);
                      return [
                        const PlaylistEntry(
                          url: 'https://startup.test/pack.mp4',
                          title: 'P16 pack',
                          httpHeaders: {'X-Playlist': 'row'},
                        ),
                      ];
                    }
                  : null,
            ),
          );
          await d.committed();
          expect(d.opens, [
            first.directUrl,
            'https://startup.test/${route == 'direct_url'
                ? 'winner'
                : route == 'playlist'
                ? 'pack'
                : 'single'}.mp4',
          ]);
          expect(
            d.event('candidate_skip').singleOrNull,
            contains('reason=external_url'),
          );
          expect(
            d.event('resolve').lastOrNull,
            contains('attempt=2/3 sourceIndex=2'),
          );
          expect(d.event('resolve').lastOrNull, contains('route=$route'));
          expect(d.commits, [winner]);
          final opened =
              d.player.calls.where((c) => c.$1 == 'open').last.$2
                  as (mk.Playable, bool);
          expect(
            (opened.$1 as mk.Media).httpHeaders,
            route == 'playlist' ? {'X-Playlist': 'row'} : {'X-Source': 'row'},
          );
          expect(opened.$2, isTrue);
          expect(resolves, route == 'direct_url' ? isEmpty : ['winner']);
          await d.settle();
          final sheet = await d.sheet();
          expect(sheet.currentSourceIndex, 2);
          expect(
            d.event('commit').singleOrNull,
            contains(
              route == 'playlist'
                  ? 'playlistItems=1 playlistIndex=0'
                  : 'playlistItems=0 playlistIndex=0',
            ),
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final initial in [-10, 999]) {
    testWidgets(
      'P16 source index $initial is clamped and a resolved launch URL bypasses the external type skip',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final sources = [
          startupSource('first', type: StreamType.externalUrl),
          startupSource('last', type: StreamType.externalUrl),
        ];
        try {
          await d.begin(
            d.screen(
              sources: sources,
              index: initial,
              url: 'https://startup.test/resolved.mp4',
            ),
          );
          await d.committed();
          final index = initial < 0 ? 0 : 1;
          expect(d.commits, [sources[index]]);
          expect(d.opens, ['https://startup.test/resolved.mp4']);
          expect(d.event('candidate_skip'), isEmpty);
          expect(
            d.event('resolve').singleOrNull,
            contains('sourceIndex=$index'),
          );
          expect(d.event('resolve').singleOrNull, contains('route=launch_url'));
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final resolverKind in ['single', 'playlist']) {
    for (final failure in ['throws', 'empty', 'null']) {
      testWidgets(
        'P16 $resolverKind resolver $failure rejects without opening and continues to the next source',
        (t) async {
          final d = StartupDriver(t, autoFrame: true);
          await d.initialize();
          await d.rules();
          final a = startupSource('resolver-first');
          final b = startupSource('resolver-b', url: '');
          final c = startupSource('resolver-c');
          d.openFailures[a.directUrl!] = StateError('dead');
          try {
            await d.begin(
              d.screen(
                sources: [a, b, c],
                failover: true,
                resolve: resolverKind == 'single'
                    ? (s) async {
                        if (failure == 'throws') {
                          throw StateError('resolver exception');
                        }
                        return failure == 'empty' ? '' : null;
                      }
                    : null,
                playlist: resolverKind == 'playlist'
                    ? (s, {canContinue}) async {
                        if (failure == 'throws') {
                          throw StateError('resolver exception');
                        }
                        return failure == 'empty' ? <PlaylistEntry>[] : null;
                      }
                    : null,
              ),
            );
            await d.committed();
            expect(d.opens, [a.directUrl, c.directUrl]);
            expect(
              d.event('candidate_reject').singleOrNull,
              contains('reason=empty_resolution'),
            );
            expect(
              d.event('resolve_result'),
              hasLength(failure == 'throws' ? 1 : 0),
            );
            if (failure == 'throws') {
              expect(
                d.event('resolve_result').singleOrNull,
                contains('ok=false reason=exception exception=StateError'),
              );
              expect(
                d.event('resolve_result').singleOrNull,
                isNot(contains('resolver exception')),
              );
            }
            expect(d.event('candidate_open'), hasLength(2));
            expect(d.event('commit').singleOrNull, contains('attempt=3/3'));
            expect(d.commits, [c]);
          } finally {
            await d.close();
          }
        },
      );
    }
  }

  testWidgets(
    'P16 a failed lazy launch consumes attempt one before ranked source two opens',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      await d.rules();
      final a = startupSource('lazy-first');
      final b = startupSource('lazy-next');
      try {
        await d.begin(
          d.screen(
            sources: [a, b],
            url: '',
            failover: true,
            entries: [
              const PlaylistEntry(url: '', title: 'lazy', provider: 'torbox'),
            ],
          ),
        );
        await d.committed();
        expect(d.opens, [b.directUrl]);
        expect(
          d.event('begin').singleOrNull,
          contains('startIndex=1 initialFailed=true'),
        );
        expect(d.event('candidate_open').singleOrNull, contains('attempt=2/3'));
        expect(d.commits, [b]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 PikPak counts its torrent acquisition before an empty resolver and skips later torrent rows',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      await d.rules();
      final first = startupSource('pik-direct');
      final cold = startupSource('pik-cold', type: StreamType.torrent, url: '');
      final skipped = startupSource(
        'pik-skip',
        type: StreamType.torrent,
        url: '',
      );
      final winner = startupSource('pik-winner');
      d.openFailures[first.directUrl!] = StateError('dead');
      final resolved = <String>[];
      try {
        await d.begin(
          d.screen(
            sources: [first, cold, skipped, winner],
            failover: true,
            provider: 'PiKpAk',
            resolve: (s) async {
              resolved.add(s.name);
              return null;
            },
          ),
        );
        await d.committed();
        expect(resolved, ['pik-cold']);
        expect(
          d.event('candidate_skip').singleOrNull,
          contains('reason=pikpak_acquisition_limit'),
        );
        expect(d.opens, [first.directUrl, winner.directUrl]);
        expect(d.event('commit').singleOrNull, contains('attempt=3/3'));
        expect(d.commits, [winner]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 exact episode matching rejects a missing pack and adopts the winning row with its headers and title',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      await d.rules(series: true);
      final first = startupSource('show-launch');
      final missing = startupSource('missing-pack', url: '');
      final good = startupSource('exact-pack', url: '');
      d.openFailures[first.directUrl!] = StateError('dead');
      try {
        await d.begin(
          d.screen(
            type: 'series',
            season: 2,
            episode: 3,
            sources: [first, missing, good],
            failover: true,
            playlist: (s, {canContinue}) async => [
              const PlaylistEntry(
                url: 'https://startup.test/s02e01',
                title: 'Show.S02E01.mkv',
              ),
              PlaylistEntry(
                url: 'https://startup.test/${s.name}',
                title: s == missing ? 'Show.S02E02.mkv' : 'Show.S02E03.mkv',
                httpHeaders: {'Episode': s.name},
              ),
            ],
          ),
        );
        await d.committed();
        expect(d.opens, [first.directUrl, 'https://startup.test/exact-pack']);
        expect(
          d.event('candidate_reject').singleOrNull,
          contains(
            'reason=playlist_missing_episode targetSeason=2 targetEpisode=3',
          ),
        );
        expect(
          d.event('commit').singleOrNull,
          contains('playlistItems=2 playlistIndex=1'),
        );
        expect(d.commits, [good]);
        final call =
            d.player.calls.where((c) => c.$1 == 'open').last.$2
                as (mk.Playable, bool);
        expect((call.$1 as mk.Media).httpHeaders, {'Episode': 'exact-pack'});
        await d.settle();
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 debrid first open hides the shield and the winner callback is unawaited after State adoption',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      final a = startupSource('debrid', type: StreamType.torrent);
      final commit = Completer<void>();
      d.onCommit = (_) => commit.future;
      try {
        await d.begin(
          d.screen(sources: [a], resolve: (s) async => s.directUrl),
        );
        await d.openEntered();
        expect(find.byType(PlaybackStartupView), findsNothing);
        d.frame();
        await d.committed();
        await d.settle();
        expect(commit.isCompleted, isFalse);
        expect(
          d.event('candidate_open').singleOrNull,
          contains('route=debrid_direct'),
        );
        expect(
          d.event('commit').singleOrNull,
          contains('playlistItems=0 playlistIndex=0'),
        );
        final sheet = await d.sheet();
        expect(sheet.currentSourceIndex, 0);
        expect(find.byType(PlaybackStartupView), findsNothing);
        commit.complete();
        await d.settle();
      } finally {
        if (!commit.isCompleted) commit.complete();
        await d.close();
      }
    },
  );
  testWidgets(
    'P16 ranked startup renders each attempt message and keeps acceptance behind the final acknowledgement',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      await d.rules(attempts: 3);
      final sources = List.generate(3, (i) => startupSource('message-$i'));
      final acks = [
        for (final source in sources)
          d.openGates[source.directUrl!] = Completer<void>(),
      ];
      try {
        await d.begin(d.screen(sources: sources, failover: true));
        for (var i = 0; i < 3; i++) {
          await d.openEntered(i + 1);
          final view = t.widget<PlaybackStartupView>(
            find.byType(PlaybackStartupView),
          );
          expect(
            view.details,
            i == 0
                ? 'Checking stream 1 of 3…'
                : 'Stream unavailable · Trying ${i + 1} of 3…',
          );
          expect(view.retrying, i > 0);
          if (i < 2) {
            d.player.emit('error', 'fixture failed attempt');
            await d.result(count: i + 1);
          } else {
            d.frame();
            await d.result(count: 3);
            expect(d.commits, isEmpty);
            expect(find.byType(PlaybackStartupView), findsOneWidget);
          }
          expect(acks[i].isCompleted, isFalse);
          acks[i].complete();
        }
        await d.initialized();
        expect(d.commits, [sources[2]]);
        expect(find.byType(PlaybackStartupView), findsNothing);
        expect(d.opens, sources.map((s) => s.directUrl));
      } finally {
        for (final a in acks) {
          a.completeIfPending();
        }
        await d.close();
      }
    },
  );
  for (final empty in [false, true]) {
    testWidgets(
      'P16 ${empty ? 'empty' : 'null'} source list releases a rejected VOD gate before route cleanup',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        try {
          await d.begin(d.screen(sources: empty ? [] : null));
          await d.openEntered();
          expect(find.byType(PlaybackStartupView), findsOneWidget);
          d.player.emit('error', 'fixture rejected single candidate');
          await d.result();
          await d.f.until(
            t,
            () => find
                .text('No playable source could be started.')
                .evaluate()
                .isNotEmpty,
          );
          expect(find.byType(PlaybackStartupView), findsNothing);
          expect(
            find.text('No playable source could be started.'),
            findsNWidgets(2),
          );
          expect(d.routeReturned, isFalse);
          expect(d.commits, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P16 a retry message refreshes even when failed open and failed stop publish no stream event',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      await d.rules(attempts: 2);
      final a = startupSource('quiet-fail'), b = startupSource('quiet-retry');
      final first = d.openGates[a.directUrl!] = Completer<void>();
      final next = d.openGates[b.directUrl!] = Completer<void>();
      d.openFailures[a.directUrl!] = StateError(
        'fixture initial native failure',
      );
      try {
        await d.begin(d.screen(sources: [a, b], failover: true));
        await d.openEntered();
        await d.tick(const Duration(seconds: 4));
        expect(
          t
              .widget<PlaybackStartupView>(find.byType(PlaybackStartupView))
              .details,
          'Checking stream 1 of 2…',
        );
        d.player.failures['stop'] = StateError('fixture quiet stop failure');
        first.complete();
        await d.openEntered(2);
        expect(next.isCompleted, isFalse);
        expect(
          t
              .widget<PlaybackStartupView>(find.byType(PlaybackStartupView))
              .details,
          'Stream unavailable · Trying 2 of 2…',
        );
        d.frame();
        await d.result(count: 2);
        next.complete();
        await d.committed();
        expect(d.commits, [b]);
      } finally {
        first.completeIfPending();
        next.completeIfPending();
        await d.close();
      }
    },
  );
  testWidgets(
    'P16 a PikPak startup winner invokes the retained commit caller only after its real metadata gate',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource(
        'pik-success',
        url: 'https://dl.mypikpak.com/p16.mkv',
      );
      try {
        await d.begin(d.screen(sources: [a], provider: 'pikpak'));
        await d.committed();
        await d.initialized();
        await d.settle();
        expect(d.opens, [a.directUrl]);
        expect(d.commits, [a]);
        expect(d.event('candidate_open'), isEmpty);
        expect(
          d.logs.where((s) => s.contains('event=player_source_committed')),
          hasLength(1),
        );
        expect(find.byType(PlaybackStartupView), findsNothing);
      } finally {
        await d.close();
      }
    },
  );
}
