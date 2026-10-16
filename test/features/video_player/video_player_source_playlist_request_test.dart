import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/series_source_fetcher.dart';
import 'package:flutter/widgets.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';
import 'package:http/http.dart' as http;
import 'support/startup_driver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;
import 'video_player_trakt_snapshots_test.dart' show traktBrowser;

void main() {
  TraktTestTransport.install();
  for (final retirement in ['dispose', 'new playlist']) {
    testWidgets(
      'P16 real P17 request returns before transition cleanup after MDBList rollback delivery crosses $retirement',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final a = source('Show.S01E01.mkv', 'https://request.test/outgoing');
        final bad = source(
          'Show.S01E02.mkv',
          'https://request.test/unavailable',
        );
        final c = source('Show.S01E03.mkv', 'https://request.test/newest');
        final fetcher = SeriesSourceFetcher(
          searchPacks: (s, e) async => [],
          searchEpisodes: (s, e) async => [bad],
          season: 1,
          episode: 1,
        );
        var rollbackReported = false;
        final delivery = CompletionDelivery(
          'switchToSourcePlaylist',
          (v) => v == null && rollbackReported,
        );
        final cleanup = <Timer>[];
        final logs = <String>[];
        final previous = debugPrint;
        debugPrint = (message, {wrapWidth}) {
          if (message != null) logs.add(message);
          previous(message, wrapWidth: wrapWidth);
        };
        T observe<T>(T Function() action) => runZoned(
          action,
          zoneSpecification: ZoneSpecification(
            createTimer: (self, parent, zone, duration, callback) {
              final timer = parent.createTimer(zone, duration, callback);
              if (duration == const Duration(milliseconds: 1500) &&
                  StackTrace.current.toString().contains(
                    'switchToSourcePlaylist',
                  )) {
                cleanup.add(timer);
              }
              return timer;
            },
          ),
        );
        Future<void>? selected;
        try {
          f.network.handler = (r) {
            if (r.url.host == 'api.mdblist.com' &&
                r.url.path == '/scrobble/pause') {
              final body = jsonDecode(r.body) as Map;
              if ((body['show'] as Map?)?['episode'] == 2) {
                rollbackReported = true;
              }
            }
            return secondaryReply(r);
          };
          await observe(
            () => delivery.run(
              () => d.mount(
                VideoPlayerScreen(
                  videoUrl: a.directUrl!,
                  title: a.name,
                  playlist: [PlaylistEntry(url: a.directUrl!, title: a.name)],
                  contentImdbId: 'tt5100000',
                  contentType: 'series',
                  contentSeason: 1,
                  contentEpisode: 1,
                  mdblistScrobble: true,
                  stremioSources: [a, bad, c],
                  seriesSourceFetcher: fetcher,
                  resolveSourceToPlaylist: (candidate, {canContinue}) async => [
                    PlaylistEntry(
                      url: candidate == bad ? '' : candidate.directUrl!,
                      title: candidate.name,
                    ),
                  ],
                ),
              ),
            ),
          );
          await d.waitCheckpoint('mdblist', 1);
          final browser = await traktBrowser(t, f);
          selected = observe(
            () => delivery.run(() => browser.onEpisodeSelected(1, 2)),
          );
          await f.until(t, () => delivery.pending.isNotEmpty);
          expect(rollbackReported, isTrue);
          expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(1));
          expect(cleanup, isEmpty);
          expect(
            delivery.pending,
            hasLength(1),
            reason:
                'The original caller is suspended after its restored MDBList target',
          );
          if (retirement == 'dispose') {
            await t.pumpWidget(const SizedBox.shrink());
            await f.until(t, () => f.player.disposed.isCompleted);
          } else {
            playerControls(t).onShowStremioSources!();
            await f.advance(t, const Duration(milliseconds: 300));
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            final url = (await f.finish(t, sheet.resolveSource(c)))!;
            final dynamic callback = sheet.onSourceSelected;
            final action = observe(
              () => f.actions.start('superseding source playlist', () async {
                final dynamic result = callback(2, url);
                if (result is Future) await result;
              }),
            );
            await f.finish(t, action.future);
            await f.until(t, () => cleanup.length == 1);
            await d.drain();
            expect(f.player.state.playlist.medias.single.uri, c.directUrl);
            expect(cleanup, hasLength(1));
          }
          final before = cleanup.length;
          delivery.release();
          await f.finish(t, selected!);
          await d.drain();
          expect(
            cleanup,
            hasLength(before),
            reason:
                'The post-await request guard prevents the old transition cleanup',
          );
          expect(
            logs.where((s) => s.contains('setState() called after dispose')),
            isEmpty,
          );
          expect(
            logs.where((s) => s.contains('Episode fetch failed:')),
            isEmpty,
          );
          if (retirement == 'new playlist') {
            expect(f.player.state.playlist.medias.single.uri, c.directUrl);
          }
          expect(d.uncaught, isEmpty);
        } finally {
          delivery.release();
          if (selected != null) await f.finish(t, selected);
          await d.close();
          debugPrint = previous;
        }
      },
    );
  }
  for (final duringStartup in [false, true]) {
    testWidgets(
      'P16 ${duringStartup ? 'failover identity adoption' : 'explicit playlist navigation before checkpoint'} retires a real pending episode search',
      (t) async {
        final d = StartupDriver(t, autoFrame: !duringStartup);
        await d.initialize();
        TraktTestTransport.instance.attach(d.f);
        PlatformUtil.debugSetAndroidTvCached(true);
        await d.rules(series: true);
        final a = startupSource(
          'Show.S01E01.mkv',
          type: duringStartup ? StreamType.torrent : StreamType.directUrl,
        );
        final b = startupSource('another-pack', url: '');
        final c = startupSource(
          'Show.S01E02.mkv',
          url: 'https://startup.test/old-request-e2',
        );
        const winner = 'https://startup.test/winning-pack-e1';
        final query = Completer<List<Torrent>>();
        var searchEntered = false;
        final resolved = <Torrent>[];
        final fetcher = SeriesSourceFetcher(
          searchPacks: (s, e) async => [],
          searchEpisodes: (s, e) {
            searchEntered = true;
            return query.future;
          },
          season: 1,
          episode: 1,
        );
        final checkpoint = CompletionDelivery(
          'switchToSourcePlaylist',
          (v) => v == null,
        )..armed = false;
        Completer<void>? ack;
        if (duringStartup) {
          ack = d.openGates[a.directUrl!] = Completer<void>();
          d.openFailures[a.directUrl!] = StateError(
            'fixture failed first candidate',
          );
        }
        d.replies[winner] = (p) {
          p.publishFrame();
          d.f.controllers.last.publishFrame();
        };
        d.replies[c.directUrl!] = (p) {
          p.publishFrame();
          d.f.controllers.last.publishFrame();
        };
        d.f.network.handler = (r) {
          if (r.url.host == 'api.tvmaze.com') {
            final show = {
              'id': 1616,
              'name': 'P16 show',
              'externals': {'imdb': 'tt1600016'},
              'genres': <String>[],
            };
            return http.Response(
              jsonEncode(
                r.url.path.endsWith('/episodes')
                    ? [
                        for (var e = 1; e <= 2; e++)
                          {
                            'id': 16160 + e,
                            'season': 1,
                            'number': e,
                            'name': 'Episode $e',
                          },
                      ]
                    : r.url.path == '/search/shows'
                    ? [
                        {'score': 1.0, 'show': show},
                      ]
                    : show,
              ),
              200,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response('{}', 404);
        };
        Future<List<PlaylistEntry>?> resolve(
          Torrent s, {
          bool Function()? canContinue,
        }) async {
          resolved.add(s);
          return [
            PlaylistEntry(
              url: s == c ? c.directUrl! : winner,
              title: s == c ? 'Show.S01E02.mkv' : 'Show.S01E01.mkv',
            ),
          ];
        }

        Future<void>? fetching;
        try {
          await d.begin(
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: 'Show',
              contentImdbId: 'tt1600016',
              contentType: 'series',
              contentSeason: 1,
              contentEpisode: 1,
              playlist: [PlaylistEntry(url: a.directUrl!, title: a.name)],
              stremioSources: [a, b],
              startupFailoverEnabled: duringStartup,
              seriesSourceFetcher: fetcher,
              resolveSourceToPlaylist: resolve,
              onStremioSourceCommitted: (s) async => d.commits.add(s),
            ),
          );
          await d.openEntered();
          if (duringStartup) {
            d.f.controllers.last.publishFrame();
            await d.tick();
          } else {
            await d.initialized();
          }
          expect(find.byType(TvControls), findsOneWidget);
          t.widget<TvControls>(find.byType(TvControls)).onShowPlaylist!();
          await d.f.until(
            t,
            () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
          );
          final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
          fetching = browser.onEpisodeSelected(1, 2);
          await d.f.until(t, () => searchEntered);
          expect(query.isCompleted, isFalse);
          if (duringStartup) {
            ack!.complete();
            await d.initialized();
            expect(d.commits, [b]);
            expect(d.opens, [a.directUrl, winner]);
            query.complete([c]);
            await d.f.finish(t, fetching!);
            await d.settle();
            expect(d.opens, [a.directUrl, winner]);
            expect(resolved, [b]);
            expect(d.commits, [b]);
          } else {
            t.widget<TvControls>(find.byType(TvControls)).onShowSources!();
            await d.tick(const Duration(milliseconds: 300));
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
            checkpoint.armed = true;
            final choose = checkpoint.run(() => d.select(sheet, 1, url));
            await d.f.until(t, () => checkpoint.pending.isNotEmpty);
            expect(choose.isCompleted, isFalse);
            query.complete([c]);
            await d.f.finish(t, fetching!);
            await d.settle();
            expect(checkpoint.pending, isNotEmpty);
            expect(d.opens, [a.directUrl]);
            expect(resolved, [b]);
            checkpoint.release();
            await d.f.finish(t, choose.future);
            expect(d.opens, [a.directUrl, winner]);
            expect(d.commits, [a, b]);
          }
        } finally {
          ack?.completeIfPending();
          checkpoint.release();
          if (!query.isCompleted) query.complete([]);
          if (fetching != null) await d.f.finish(t, fetching);
          await d.close();
          PlatformUtil.debugSetAndroidTvCached(false);
          TraktTestTransport.instance.recorder = null;
        }
      },
    );
  }
  testWidgets(
    'P16 a real P17 native-open exception preserves incoming identity while its catch logs and drains the transition',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      PlatformUtil.debugSetAndroidTvCached(true);
      final a = startupSource('Failure.Show.S01E01.mkv'),
          b = startupSource('Failure.Show.S01E02.mkv');
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 1,
        searchPacks: (s, e) async => [],
        searchEpisodes: (s, e) async => [],
      );
      d.f.network.handler = (r) {
        final show = {
          'id': 1617,
          'name': 'Failure Show',
          'externals': {'imdb': 'tt1600017'},
          'genres': <String>[],
        };
        return http.Response(
          jsonEncode(
            r.url.path.endsWith('/episodes')
                ? [
                    for (var e = 1; e <= 2; e++)
                      {
                        'id': 16170 + e,
                        'season': 1,
                        'number': e,
                        'name': 'Episode $e',
                      },
                  ]
                : r.url.path == '/search/shows'
                ? [
                    {'score': 1.0, 'show': show},
                  ]
                : show,
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      };
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: a.name,
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            playlist: [PlaylistEntry(url: a.directUrl!, title: a.name)],
            stremioSources: [a, b],
            seriesSourceFetcher: fetcher,
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.name),
            ],
            onStremioSourceCommitted: (s) async => d.commits.add(s),
          ),
        );
        await d.initialized();
        t.widget<TvControls>(find.byType(TvControls)).onShowPlaylist!();
        await d.f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        d.openFailures[b.directUrl!] = StateError(
          'fixture P17 native rejection',
        );
        await d.f.until(
          t,
          () => browser.seriesPlaylist.fullTvmazeEpisodes.any(
            (e) => e['number'] == 2,
          ),
        );
        // The real child closes its sheet before dispatching this callback.
        Navigator.of(t.element(find.byType(SeriesBrowser))).pop();
        final dynamic selection = browser.onEpisodeSelected(1, 2);
        await d.f.finish<dynamic>(t, selection as Future<dynamic>);
        await d.settle();
        expect(
          d.logs,
          contains(
            'Episode source load failed: Bad state: fixture P17 native rejection',
          ),
        );
        expect(d.opens, [a.directUrl, b.directUrl]);
        expect(d.commits, [a]);
        expect(d.player.state.playlist.medias.single.uri, a.directUrl);
        expect(
          t.widget<TvControls>(find.byType(TvControls)).isTransitioning,
          isFalse,
        );
        await d.tick(const Duration(milliseconds: 1500));
        expect(find.byType(TransitionOverlay), findsNothing);
        await d.f.until(t, () => find.byType(SeriesBrowser).evaluate().isEmpty);
        t.widget<TvControls>(find.byType(TvControls)).onShowPlaylist!();
        await d.f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final retained = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        expect(retained.seriesPlaylist.allEpisodes.map((e) => e.url), [
          b.directUrl,
        ]);
        expect(
          retained.seriesPlaylist.allEpisodes.single.seriesInfo.episode,
          2,
        );
      } finally {
        await d.close();
        TraktTestTransport.instance.recorder = null;
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
  testWidgets(
    'P16 a shuffle request replacing its playlist retires an older EOF adjacency read without a navigation increment',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      final a = startupSource('Shuffle.Show.S01E01.mkv'),
          two = startupSource('Shuffle.Show.S01E02.mkv'),
          three = startupSource('Shuffle.Show.S01E03.mkv');
      final adjacent = Completer<({int season, int episode})?>();
      var adjacentReads = 0;
      final searches = <int>[];
      final fetcher = SeriesSourceFetcher(
        season: 1,
        episode: 1,
        resolveAdjacentEpisode: (s, e, direction) {
          adjacentReads++;
          return adjacent.future;
        },
        loadCustomEpisodeInventory: () async => [
          {'season': 1, 'number': 3, 'name': 'Third'},
        ],
        searchPacks: (s, e) async => [],
        searchEpisodes: (s, e) async {
          searches.add(e);
          return [e == 3 ? three : two];
        },
      );
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: a.name,
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioSources: [a],
            seriesSourceFetcher: fetcher,
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.name),
            ],
            onStremioSourceCommitted: (s) async => d.commits.add(s),
          ),
        );
        await d.initialized();
        playerControls(t).onRandom();
        await d.tick(const Duration(milliseconds: 350));
        expect(find.byType(PlayerMenuPanel), findsOneWidget);
        final menu = t.widget<PlayerMenuPanel>(find.byType(PlayerMenuPanel));
        d.player.emit('completed', true);
        await d.f.until(t, () => adjacentReads == 1);
        expect(adjacent.isCompleted, isFalse);
        d.observe(menu.onShuffleOnce);
        await d.f.until(
          t,
          () => d.logs.any(
            (s) =>
                s.contains('event=next_episode_candidate_outcome') &&
                s.contains('reason=committed'),
          ),
        );
        await d.settle();
        expect(d.opens, [a.directUrl, three.directUrl]);
        expect(searches, [3]);
        expect(adjacent.isCompleted, isFalse);
        adjacent.complete((season: 1, episode: 2));
        await d.settle();
        await d.tick(const Duration(seconds: 3));
        expect(searches, [3]);
        expect(d.opens, [a.directUrl, three.directUrl]);
        expect(d.player.state.playlist.medias.single.uri, three.directUrl);
        expect(d.commits, [a, three]);
      } finally {
        if (!adjacent.isCompleted) adjacent.complete(null);
        await d.close();
        TraktTestTransport.instance.recorder = null;
      }
    },
  );
  testWidgets(
    'P16 restoring a rejected pack to a direct launch retires a real request started on that pending pack',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource(
            'Show.S01E01.mkv',
            url: 'https://startup.test/rollback-request-a',
          ),
          b = startupSource(
            'Show.S01E01.mkv',
            url: 'https://startup.test/rollback-request-b',
          ),
          c = startupSource(
            'Show.S01E03.mkv',
            url: 'https://startup.test/rollback-request-c',
          );
      final ack = d.openGates[b.directUrl!] = Completer<void>();
      final search = Completer<List<Torrent>>();
      var searching = false;
      final fetcher = SeriesSourceFetcher(
        searchPacks: (s, e) async => [],
        searchEpisodes: (s, e) {
          searching = true;
          return search.future;
        },
        season: 1,
        episode: 1,
      );
      d.f.network.handler = (r) => http.Response(
        jsonEncode(
          r.url.path.endsWith('/episodes')
              ? [
                  for (var e = 1; e <= 3; e++)
                    {
                      'id': 1600 + e,
                      'season': 1,
                      'number': e,
                      'name': 'Episode $e',
                    },
                ]
              : {
                  'id': 16,
                  'name': 'Show',
                  'externals': {'imdb': 'tt9200016'},
                  'genres': <String>[],
                },
        ),
        200,
      );
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: a.name,
            contentImdbId: 'tt9200016',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            stremioSources: [a, b],
            seriesSourceFetcher: fetcher,
            resolveSourceToPlaylist: (source, {canContinue}) async =>
                source == b
                ? [
                    PlaylistEntry(url: b.directUrl!, title: b.name),
                    const PlaylistEntry(
                      url: 'https://startup.test/rollback-request-b2',
                      title: 'Show.S01E02.mkv',
                    ),
                  ]
                : [PlaylistEntry(url: source.directUrl!, title: source.name)],
            onStremioSourceCommitted: (s) async => d.commits.add(s),
          ),
        );
        await d.initialized();
        final sheet = await d.sheet();
        final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
        d.openFailures[b.directUrl!] = StateError(
          'fixture pack rejection after held native entry',
        );
        final manual = d.select(sheet, 1, url);
        await d.openEntered(2);
        expect(manual.isCompleted, isFalse);
        playerControls(t).onShowPlaylist();
        await d.f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        Navigator.of(t.element(find.byType(SeriesBrowser))).pop();
        final request = d.observe(
          () => d.f.actions.start('real request on pending pack', () async {
            await browser.onEpisodeSelected(1, 3);
          }, held: true),
        );
        await d.f.until(t, () => searching);
        expect(request.isCompleted, isFalse);
        ack.complete();
        await d.f.finish(t, manual.future);
        expect(d.opens, [a.directUrl, b.directUrl, a.directUrl]);
        expect(d.player.state.playlist.medias.single.uri, a.directUrl);
        search.complete([c]);
        await d.f.finish(t, request.future);
        await d.settle();
        expect(d.opens, [a.directUrl, b.directUrl, a.directUrl]);
        expect(d.player.state.playlist.medias.single.uri, a.directUrl);
        expect(d.commits, [a]);
        expect(d.errors, isEmpty);
      } finally {
        ack.completeIfPending();
        if (!search.isCompleted) search.complete([]);
        await d.close();
      }
    },
  );
}
