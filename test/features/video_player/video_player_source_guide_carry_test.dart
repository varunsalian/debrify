import 'dart:async';
import 'dart:convert';
import 'package:debrify/models/quick_play_rules.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'support/local_completion_driver.dart';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/startup_driver.dart';
import 'support/trakt_transport.dart';

void main() {
  TraktTestTransport.install();
  testWidgets(
    'P16 source playlist carries the discovered TVMaze identity, full guide and artwork while its new metadata request is pending',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      PlatformUtil.debugSetAndroidTvCached(true);
      await d.f.finish(t, TVMazeService.clearCache());
      final a = startupSource('Fixture.S01E01.mkv'),
          b = startupSource('Other.Show.S01E01.mkv');
      var hold = false;
      final pending = <Completer<http.Response>>[];
      final payloads = <http.Response>[];
      final show = {
        'id': 1600,
        'name': 'Fixture official',
        'externals': {'imdb': 'tt1600016'},
        'genres': <String>[],
        'image': {
          'original': 'https://artwork.test/p16.png',
          'medium': 'https://artwork.test/p16.png',
        },
      };
      http.Response response(http.Request r) {
        if (r.url.path.endsWith('/episodes')) {
          return http.Response(
            jsonEncode([
              for (var i = 1; i <= 4; i++)
                {
                  'id': 16000 + i,
                  'season': 1,
                  'number': i,
                  'name': 'Episode $i',
                  'summary': 'P16 guide $i',
                },
            ]),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode(
            r.url.path == '/search/shows'
                ? [
                    {'score': 1.0, 'show': show},
                  ]
                : show,
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      d.f.network.handler = (r) {
        if (r.url.host == 'api.tvmaze.com') {
          final reply = response(r);
          if (hold) {
            final gate = Completer<http.Response>();
            pending.add(gate);
            payloads.add(reply);
            return gate.future;
          }
          return reply;
        }
        if (r.url.host == 'artwork.test') {
          return http.Response.bytes(
            base64Decode(
              'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aV1sAAAAASUVORK5CYII=',
            ),
            200,
            headers: {'content-type': 'image/png'},
          );
        }
        return http.Response('{}', 404);
      };
      try {
        await d.begin(
          d.screen(
            type: 'series',
            season: 1,
            episode: 1,
            sources: [a, b],
            entries: [PlaylistEntry(url: a.directUrl!, title: a.name)],
            playlist: (s, {canContinue}) async => [
              PlaylistEntry(url: b.directUrl!, title: b.name),
              const PlaylistEntry(
                url: 'https://startup.test/other-e2',
                title: 'Other.Show.S01E02.mkv',
              ),
            ],
          ),
        );
        await d.initialized();
        t.widget<TvControls>(find.byType(TvControls)).onShowPlaylist!();
        await d.f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final first = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        await d.f.until(
          t,
          () => first.seriesPlaylist.fullTvmazeEpisodes.length == 4,
        );
        final old = first.seriesPlaylist;
        expect(old.imdbId, 'tt1600016');
        expect(old.tvmazeShowId, 1600);
        expect(old.tvmazeShowName, 'Fixture official');
        expect(old.showPosterUrl, 'https://artwork.test/p16.png');
        final guide = old.fullTvmazeEpisodes;
        Navigator.of(t.element(find.byType(SeriesBrowser))).pop();
        await d.tick(const Duration(milliseconds: 400));
        await d.f.until(t, () => find.byType(SeriesBrowser).evaluate().isEmpty);
        // Clear only service caches. The public outgoing guide remains owned by
        // the route and must be carried before the replacement fetch completes.
        await d.f.finish(t, TVMazeService.clearCache());
        hold = true;
        final openBrowser = t
            .widget<TvControls>(find.byType(TvControls))
            .onShowPlaylist!;
        t.widget<TvControls>(find.byType(TvControls)).onShowSources!();
        await d.tick(const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
        final action = d.select(sheet, 1, url);
        await d.f.until(t, () => pending.isNotEmpty);
        openBrowser();
        await d.f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final current = t
            .widget<SeriesBrowser>(find.byType(SeriesBrowser))
            .seriesPlaylist;
        expect(identical(current, old), isFalse);
        expect(current.imdbId, 'tt1600016');
        expect(current.tvmazeShowId, 1600);
        expect(current.tvmazeShowName, 'Fixture official');
        expect(current.showPosterUrl, 'https://artwork.test/p16.png');
        expect(current.fullTvmazeEpisodes, guide);
        expect(current.fullTvmazeEpisodes.map((e) => e['number']), [
          1,
          2,
          3,
          4,
        ]);
        expect(pending.every((r) => !r.isCompleted), isTrue);
        Navigator.of(t.element(find.byType(SeriesBrowser))).pop();
        hold = false;
        for (var i = 0; i < pending.length; i++) {
          pending[i].complete(payloads[i]);
        }
        await d.f.finish(t, action.future);
        expect(d.commits, [a, b]);
        expect(d.player.state.playlist.medias.single.uri, b.directUrl);
      } finally {
        hold = false;
        for (var i = 0; i < pending.length; i++) {
          if (!pending[i].isCompleted) pending[i].complete(payloads[i]);
        }
        await d.close();
        TraktTestTransport.instance.recorder = null;
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
  testWidgets(
    'P16 failover adopts a winning pack index and cache, then a rejected direct pick restores its URL and headers',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      await d.rules(series: true);
      final rules = CompletionDelivery(
        'openInitialVodWithFailover',
        (v) => v is QuickPlayRules,
      );
      final a = startupSource('adopt-first', headers: {'X-Source': 'outgoing'});
      final b = startupSource('adopt-pack', url: '');
      final c = startupSource('adopt-rejected');
      final oldEntries = [
        PlaylistEntry(url: a.directUrl!, title: 'Old.Show.S01E01.mkv'),
        const PlaylistEntry(
          url: 'https://startup.test/old-e2',
          title: 'Old.Show.S01E02.mkv',
        ),
      ];
      final winner = [
        const PlaylistEntry(
          url: 'https://startup.test/new-e1',
          title: 'New.Show.S01E01.mkv',
        ),
        const PlaylistEntry(
          url: 'https://startup.test/new-e3',
          title: 'New.Show.S01E03.mkv',
        ),
        const PlaylistEntry(
          url: 'https://startup.test/new-e2',
          title: 'New.Show.S01E02.mkv',
          httpHeaders: {'X-Winner': 'pack'},
        ),
      ];
      d.openFailures[oldEntries[1].url] = StateError('first rejected');
      try {
        await rules.run(
          () => d.begin(
            d.screen(
              type: 'series',
              season: 1,
              episode: 2,
              entries: oldEntries,
              sources: [a, b, c],
              failover: true,
              playlist: (s, {canContinue}) async => winner,
            ),
          ),
        );
        await d.f.until(t, () => rules.pending.isNotEmpty);
        // Initialization has parsed the outgoing series to choose S1E2;
        // keep the rules delivery held until that cache exists.
        expect(d.opens, isEmpty);
        rules.release();
        await d.initialized();
        expect(d.commits, [b]);
        expect(d.opens, [oldEntries[1].url, winner[2].url]);
        t.widget<TvControls>(find.byType(TvControls)).onShowPlaylist!();
        await d.f.until(
          t,
          () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
        expect(browser.currentEpisodeIndex, 2);
        expect(
          browser.seriesPlaylist.allEpisodes.map((e) => e.url).toSet(),
          winner.map((e) => e.url).toSet(),
        );
        Navigator.of(t.element(find.byType(SeriesBrowser))).pop();
        await d.tick(const Duration(milliseconds: 400));
        await d.update(
          d.screen(
            type: 'series',
            season: 1,
            episode: 2,
            entries: oldEntries,
            sources: [a, b, c],
            resolve: (s) async => s.directUrl,
          ),
        );
        t.widget<TvControls>(find.byType(TvControls)).onShowSources!();
        await d.tick(const Duration(milliseconds: 300));
        expect(find.byType(SourceSheet), findsOneWidget);
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        d.openFailures[c.directUrl!] = StateError('follow-up rejected');
        await d.f.finish(t, d.select(sheet, 2, c.directUrl!).future);
        expect(d.opens, [
          oldEntries[1].url,
          winner[2].url,
          c.directUrl,
          winner[2].url,
        ]);
        final restored =
            d.player.calls.where((c) => c.$1 == 'open').last.$2
                as (mk.Playable, bool);
        expect((restored.$1 as mk.Media).httpHeaders, {'X-Winner': 'pack'});
        expect(d.player.state.playlist.medias.single.uri, winner[2].url);
        expect(d.commits, [b]);
      } finally {
        rules.release();
        await d.close();
        PlatformUtil.debugSetAndroidTvCached(false);
      }
    },
  );
}
