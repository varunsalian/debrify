import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/stremio_subtitle_service.dart';
import 'package:debrify/services/tvmaze_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/identify_title_driver.dart';
import 'support/player_actions.dart';
import 'support/subtitle_sources_driver.dart';
import 'video_player_subtitle_sources_language_test.dart'
    show seedLanguagePlayer;
import 'video_player_trakt_snapshots_test.dart' show traktPlaylist;

void main() {
  testWidgets(
    'p13 old menu cache delivery cannot overwrite an identified title',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      try {
        d.discovery = (request) => d.slots(
          request.url.path.contains('tt1200001') ? 'outgoing' : 'incoming',
        );
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/stale-menu-cache.mp4',
            title: 'Launch Title',
            contentImdbId: 'tt1200001',
            contentType: 'movie',
          ),
        );
        final old = await d.menu();
        final outgoing = await d.f.finish(
          t,
          StremioSubtitleService.instance.fetchSubtitleSlots(
            type: 'movie',
            imdbId: 'tt1200001',
          ),
        );
        expect(outgoing.single.subtitles.single.id, 'outgoing');
        final pending = d.start(old);
        await d.found('Chosen title');
        await t.tap(find.text('Chosen title'));
        expect((await d.f.finish(t, pending))?.imdbId, 'tt1200002');
        old.onAddonSlotsFetched!(outgoing);
        d.panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        playerControls(t).onSpeed();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final incoming = t.widget<PlayerMenuPanel>(
          find.byType(PlayerMenuPanel),
        );
        expect(incoming.contentImdbId, 'tt1200002');
        expect(incoming.cachedAddonSlots, isNotNull);
        expect(
          incoming.cachedAddonSlots!.single.subtitles.single.id,
          'incoming',
        );
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 menu cache write publishes its flat projection before metadata retry',
    (t) async {
      final d = SubtitleSourcesDriver(t, configurePlayer: seedLanguagePlayer);
      await d.setup();
      final search = Completer<http.Response>();
      final initialDiscovery = Completer<http.Response>();
      const show = {
        'id': 110,
        'name': 'Trakt Show',
        'externals': {'imdb': 'tt1100003'},
        'genres': <String>[],
      };
      var fresh = false;
      var discoveries = 0;
      try {
        await d.register('menu-projection');
        await d.order(language: 'eng');
        await d.f.finish(t, TVMazeService.clearCache());
        d.f.network.handler = (request) {
          if (request.url.host == 'api.tvmaze.com') {
            if (request.url.path == '/lookup/shows') return search.future;
            return http.Response(
              jsonEncode(
                request.url.path.endsWith('/episodes')
                    ? [
                        for (var n = 1; n <= 2; n++)
                          {
                            'id': n,
                            'season': 1,
                            'number': n,
                            'name': 'Episode $n',
                          },
                      ]
                    : show,
              ),
              200,
            );
          }
          if (request.url.path.startsWith('/subtitles/series/')) {
            discoveries++;
            if (discoveries == 1) return initialDiscovery.future;
            return d.slots(fresh ? 'fresh-menu' : 'old-menu');
          }
          if (request.url.path.endsWith('.srt')) {
            return http.Response(
              '1\n00:00:01,000 --> 00:00:02,000\nCaption\n',
              200,
            );
          }
          return d.f.network.replies[request.url.toString()] ??
              http.Response('{}', 404);
        };
        await d.mount(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/trakt-one.mp4',
            title: 'Trakt.Show.S01E01.mkv',
            contentImdbId: 'tt1100003',
            playlist: traktPlaylist,
          ),
          publishTracks: false,
        );
        await d.f.until(t, () => discoveries == 1);
        await d.f.until(
          t,
          () => d.logs.any((line) => line.contains('restore done')),
        );
        expect(search.isCompleted, isFalse);
        final panel = await d.menu();
        expect(panel.contentType, 'series');
        expect(panel.contentSeason, 1);
        expect(panel.contentEpisode, 1);
        fresh = true;
        final slots = await d.f.finish(
          t,
          StremioSubtitleService.instance.fetchSubtitleSlots(
            type: 'series',
            imdbId: 'tt1100003',
            season: 1,
            episode: 1,
          ),
        );
        expect(slots.single.subtitles.single.id, 'fresh-menu');
        expect(d.requests(d.caption('fresh-menu')), 0);
        panel.onAddonSlotsFetched!(slots);
        await d.f.advance(t, const Duration(milliseconds: 300));
        final beforeRetry = discoveries;
        expect(
          beforeRetry,
          3,
          reason:
              'initial discovery, panel discovery and explicit service result',
        );
        search.complete(http.Response(jsonEncode(show), 200));
        await d.f.until(
          t,
          () => d.logs.any(
            (line) => line.contains(
              'Series IMDB resolved after initial subtitle fetch',
            ),
          ),
        );
        await d.f.advance(t, const Duration(seconds: 1));
        expect(
          discoveries,
          beforeRetry,
          reason: 'the retry must consume the menu-published flat cache',
        );
        expect(d.requests(d.caption('fresh-menu')), 1);
        expect(d.errors, isEmpty);
      } finally {
        if (!search.isCompleted) search.complete(http.Response('{}', 404));
        if (!initialDiscovery.isCompleted) {
          initialDiscovery.complete(d.slots('old-menu'));
        }
        await d.close();
      }
    },
  );
}
