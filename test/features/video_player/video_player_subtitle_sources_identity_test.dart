import 'dart:async';

import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/identity_fixture.dart';
import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_subtitle_sources_payload_test.dart' show removeFixture;
import 'video_player_trakt_snapshots_test.dart'
    show traktPlaylist, traktBrowser;

void main() {
  for (final type in ['movie', 'series']) {
    for (final embeddedFirst in [false, true]) {
      testWidgets(
        'subtitle manual $type identity embeddedFirst=$embeddedFirst overrides custom launch and reuses warmed discovery',
        (t) async {
          final d = SubtitleSourcesDriver(
            t,
            configurePlayer: seedLanguagePlayer,
          );
          await d.setup();
          await d.register('manual');
          await d.order(language: 'eng', embeddedFirst: embeddedFirst);
          await installIdentityCatalog(
            t,
            d.f,
            metas: [
              {
                'id': 'tt1100001',
                'imdb_id': 'tt1100001',
                'name': 'Manual identity',
                'type': type,
              },
            ],
          );
          final search = d.f.network.handler!;
          d.f.network.handler = (r) {
            if (r.url.host == 'identity.test') return search(r);
            if (r.url.path.startsWith('/subtitles/')) return d.slots('manual');
            return d.f.network.replies[r.url.toString()] ??
                http.Response('{}', 404);
          };
          try {
            await d.mount(
              screen: VideoPlayerScreen(
                videoUrl: 'https://player.test/custom.mp4',
                title: 'Custom launch',
                contentType: 'series',
                contentImdbId: const CustomSeriesIdentity(
                  'fixture',
                  'Custom launch',
                ).id,
              ),
              publishTracks: false,
            );
            expect(
              d.f.network.requests.where(
                (r) => r.url.path.startsWith('/subtitles/'),
              ),
              isEmpty,
            );
            expect(
              d.player.calls.where((c) => c.$1 == 'subtitle'),
              hasLength(embeddedFirst ? 1 : 0),
            );
            expect(
              d.player.state.track.subtitle.id,
              embeddedFirst ? '2' : 'no',
            );
            final panel = await d.menu();
            final selection = d.observe(() => panel.onIdentifyTitle!());
            await d.f.until(
              t,
              () => find.text('Manual identity').evaluate().isNotEmpty,
            );
            await t.tap(find.text('Manual identity'));
            if (type == 'series') {
              await d.f.until(
                t,
                () => find.text('Which episode?').evaluate().isNotEmpty,
              );
              await t.enterText(
                find.byWidgetPredicate(
                  (w) => w is TextField && w.decoration?.labelText == 'Season',
                ),
                '2',
              );
              await t.enterText(
                find.byWidgetPredicate(
                  (w) => w is TextField && w.decoration?.labelText == 'Episode',
                ),
                '4',
              );
              await t.tap(find.text('Apply'));
            }
            final result = await d.f.finish(t, selection);
            expect(result?.imdbId, 'tt1100001');
            expect(result?.contentType, type);
            expect(result?.season, type == 'series' ? 2 : null);
            expect(result?.episode, type == 'series' ? 4 : null);
            expect(
              d.f.network.requests
                  .where((r) => r.url.path.startsWith('/subtitles/'))
                  .map((r) => r.url.path),
              [
                '/subtitles/$type/${type == 'series' ? 'tt1100001:2:4' : 'tt1100001'}.json',
              ],
            );
            expect(d.player.state.track.subtitle.uri, isTrue);
            expect(d.requests(d.caption('manual')), 1);
            expect(
              d.logs,
              contains(
                'SubAuto: addon auto-select start — imdb=tt1100001 type=$type s=${type == 'series' ? 2 : null} e=${type == 'series' ? 4 : null}',
              ),
            );
            expect(
              d.logs.any((s) => s.contains('Using 1 cached addon subtitles')),
              isTrue,
            );
            expect(d.errors, isEmpty);
          } finally {
            await removeFixture(d);
          }
        },
      );
    }
  }

  testWidgets(
    'subtitle parsed playlist identity follows original index and enriched show across episode selection',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      await d.register('parsed');
      await d.order();
      final initial = Completer<http.Response>();
      d.f.network.handler = (r) =>
          r.url.path == '/subtitles/series/tt1100001:1:1.json'
          ? initial.future
          : r.url.path.startsWith('/subtitles/series/')
          ? d.slots('parsed')
          : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
      try {
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/trakt-one.mp4',
            title: 'Trakt.Show.S01E01.mkv',
            contentImdbId: 'tt1100001',
            contentType: 'series',
            playlist: traktPlaylist,
          ),
          publishTracks: false,
        );
        await d.f.until(
          t,
          () =>
              d.f.network.requests
                  .where(
                    (r) => r.url.path == '/subtitles/series/tt1100001:1:1.json',
                  )
                  .length ==
              2,
        );
        initial.complete(d.slots('parsed'));
        await d.f.until(t, () => d.player.state.track.subtitle.uri);
        await d.f.actions.settle(t);
        final b = await traktBrowser(t, d.f);
        b.seriesPlaylist.imdbId = 'tt1100002';
        await d.f.finish<void>(t, d.observe(() => b.onEpisodeSelected(1, 2)));
        await d.f.actions.settle(t);
        expect(
          d.f.network.requests
              .where((r) => r.url.path.startsWith('/subtitles/series/'))
              .map((r) => r.url.path),
          [
            '/subtitles/series/tt1100001:1:1.json',
            '/subtitles/series/tt1100001:1:1.json',
            '/subtitles/series/tt1100002:1:2.json',
          ],
        );
        expect(d.player.state.track.subtitle.uri, isTrue);
        expect(d.requests(d.caption('parsed')), 2);
        expect(d.errors, isEmpty);
      } finally {
        if (!initial.isCompleted) initial.complete(http.Response('{}', 404));
        await removeFixture(d);
      }
    },
  );
  for (final mode in [
    'complete series',
    'zero season',
    'zero episode',
    'missing season',
    'missing episode',
    'movie',
    'no id',
    'empty id',
  ]) {
    testWidgets(
      'subtitle single-file $mode discovery preserves the original coordinate fallback',
      (t) async {
        final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
        await d.setup();
        await d.register('single');
        await d.order(language: 'eng');
        d.f.network.handler = (r) => r.url.path.startsWith('/subtitles/')
            ? d.slots('single')
            : d.f.network.replies[r.url.toString()] ?? http.Response('{}', 404);
        final series = !['movie', 'no id', 'empty id'].contains(mode);
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/single.mp4',
              title: 'Single launch',
              contentImdbId: mode == 'no id'
                  ? null
                  : mode == 'empty id'
                  ? ''
                  : 'tt1100001',
              contentType: series ? 'series' : 'movie',
              contentSeason: mode == 'missing season'
                  ? null
                  : mode == 'zero season'
                  ? 0
                  : 3,
              contentEpisode: mode == 'missing episode'
                  ? null
                  : mode == 'zero episode'
                  ? 0
                  : 4,
            ),
            publishTracks: false,
          );
          await d.f.actions.settle(t);
          final requested = d.f.network.requests
              .where((r) => r.url.path.startsWith('/subtitles/'))
              .toList();
          if (mode == 'no id' || mode == 'empty id') {
            expect(requested, isEmpty);
            expect(d.player.state.track.subtitle.id, '2');
            expect(
              d.logs,
              contains(
                'SubAuto: restore done — embeddedSubtitleApplied=false → running addon auto-select',
              ),
            );
          } else {
            final type =
                [
                  'complete series',
                  'zero season',
                  'zero episode',
                ].contains(mode)
                ? 'series'
                : 'movie';
            final season = mode == 'zero season' ? 0 : 3;
            final episode = mode == 'zero episode' ? 0 : 4;
            expect(requested.map((r) => r.url.path), [
              '/subtitles/$type/${type == 'series' ? 'tt1100001:$season:$episode' : 'tt1100001'}.json',
            ]);
            expect(d.player.state.track.subtitle.uri, isTrue);
            expect(
              d.logs,
              contains(
                'SubAuto: addon auto-select start — imdb=tt1100001 type=$type s=${type == 'series' ? season : null} e=${type == 'series' ? episode : null}',
              ),
            );
            expect(
              d.logs,
              contains(
                'VideoPlayer: Fetching addon subtitles (IMDB: tt1100001)',
              ),
            );
            expect(
              d.logs,
              contains('VideoPlayer: Fetched and cached 1 addon subtitles'),
            );
            final panel = await d.menu();
            expect(panel.cachedAddonSlots, hasLength(1));
            expect(
              panel.cachedAddonSlots!.single.subtitles.single.id,
              'single',
            );
          }
          expect(d.errors, isEmpty);
        } finally {
          await removeFixture(d);
        }
      },
    );
  }
}
