import 'dart:convert';

import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/widgets/movie_collection_browser.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/identify_title_driver.dart';
import 'support/menu_metadata_driver.dart';
import 'support/player_actions.dart';

void main() {
  testWidgets(
    'p13 quick menu prefers the current movie cache over the shared first movie identity',
    (t) async {
      final d = MenuMetadataDriver(t);
      await d.setup();
      try {
        d.f.network.handler = (request) {
          if (request.url.host == 'v3-cinemeta.strem.io') {
            if (request.url.path == '/manifest.json') {
              return http.Response('{}', 200);
            }
            final other = request.url.path.toLowerCase().contains('other');
            return http.Response(
              jsonEncode({
                'metas': [
                  {
                    'id': other ? 'tt1300002' : 'tt1300001',
                    'name': other ? 'Other Movie' : 'Menu Movie',
                    'year': other ? '2023' : '2024',
                  },
                ],
              }),
              200,
            );
          }
          return d.f.network.replies[request.url.toString()] ??
              http.Response('{}', 404);
        };
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/movie-one.mp4',
            title: 'Menu.Movie.2024.mkv',
            disableAutoResume: true,
            startIndex: 0,
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/movie-one.mp4',
                title: 'Menu.Movie.2024.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/movie-two.mp4',
                title: 'Other.Movie.2023.mkv',
              ),
            ],
          ),
        );
        d.tracks();
        await d.shown();
        expect(d.panel.contentImdbId, 'tt1300001');
        d.panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        playerControls(t).onShowPlaylist();
        await d.f.until(
          t,
          () => find.byType(MovieCollectionBrowser).evaluate().isNotEmpty,
        );
        final browser = t.widget<MovieCollectionBrowser>(
          find.byType(MovieCollectionBrowser),
        );
        d.observe(() => browser.onSelectIndex(1));
        d.f.navigator.currentState!.pop();
        await d.f.until(
          t,
          () => d.player.calls.where((call) => call.$1 == 'open').length == 2,
        );
        d.player.publishFrame();
        await d.f.advance(t);
        await d.f.until(
          t,
          () => d.logs.any(
            (line) =>
                line.contains('Found IMDB ID "tt1300002"') &&
                line.contains('(index 1)'),
          ),
          reason:
              'the real background prefetch has published the second cache entry',
        );
        d.tracks();
        await d.shown();
        expect(d.panel.contentImdbId, 'tt1300002');
        d.panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        playerControls(t).onSpeed();
        await d.shown();
        expect(d.panel.initialSection, PlayerMenuSection.speed);
        expect(d.panel.contentImdbId, 'tt1300002');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 quick menu keeps manually identified subtitle identity ahead of launch identity',
    (t) async {
      final d = IdentifyTitleDriver(t);
      await d.setupIdentity();
      d.metas = [IdentifyTitleDriver.identityMeta('Manual B')];
      try {
        await d.mountIdentity(
          screen: const VideoPlayerScreen(
            videoUrl: 'https://player.test/manual-quick.mp4',
            title: 'Launch A',
            contentImdbId: 'tt1200001',
            contentType: 'movie',
          ),
        );
        final pending = d.start(await d.menu());
        await d.found('Manual B');
        await t.tap(find.text('Manual B'));
        final result = await d.f.finish(t, pending);
        expect(result?.imdbId, 'tt1200002');
        d.panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        playerControls(t).onSpeed();
        await d.f.advance(t, const Duration(milliseconds: 350));
        expect(d.panel.initialSection, PlayerMenuSection.speed);
        expect(d.panel.contentImdbId, 'tt1200002');
        expect(d.panel.contentType, 'movie');
        expect(d.panel.subtitleIdentityLabel, 'Subtitles for Manual B');
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
