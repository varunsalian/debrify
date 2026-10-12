import 'dart:async';
import 'dart:convert';

import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/player_actions.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/trakt_transport.dart';
import 'support/video_player_environment.dart';
import 'video_player_source_test.dart' show source;

void main() {
  TraktTestTransport.install();
  testWidgets(
    'MDBList pending checkpoint across an explicit source playlist switch preserves validation gating and the existing target',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = SecondaryTrackerDriver(t, f);
      await d.initialize();
      final reply = Completer<http.Response>();
      final a = source(
        'Fixture.Show.S01E01.mkv',
        'https://player.test/pending-a.mp4',
      );
      final b = source(
        'Fixture.Show.S01E02.mkv',
        'https://player.test/pending-b.mp4',
      );
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: a.name,
            playlist: [PlaylistEntry(url: a.directUrl!, title: a.name)],
            contentImdbId: 'tt5100000',
            contentType: 'series',
            contentSeason: 1,
            contentEpisode: 1,
            mdblistScrobble: true,
            stremioSources: [a, b],
            stremioCurrentSourceIndex: 0,
            resolveStremioSource: (s) async => s.directUrl,
            resolveSourceToPlaylist: (s, {canContinue}) async => [
              PlaylistEntry(url: s.directUrl!, title: s.name),
            ],
          ),
        );
        await d.waitCheckpoint('mdblist', 1);
        f.network.handler = (r) {
          if (r.url.host == 'api.mdblist.com' &&
              r.url.path == '/scrobble/pause' &&
              (jsonDecode(r.body) as Map)['progress'] == 25) {
            return reply.future;
          }
          return secondaryReply(r);
        };
        await d.position(300000);
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('mdblist', 2);
        d.expectCheckpoint('mdblist', 1, 'pause', 25, season: 1, episode: 1);
        playerControls(t).onShowStremioSources!();
        await f.advance(t, const Duration(milliseconds: 300));
        final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
        final url = (await f.finish(t, sheet.resolveSource(b)))!;
        sheet.onSourceSelected(1, url);
        await f.until(
          t,
          () => f.player.calls.where((c) => c.$1 == 'open').length == 2,
        );
        expect(f.player.state.playlist.medias.first.uri, b.directUrl);
        expect(d.forTracker('mdblist'), hasLength(2));
        reply.complete(http.Response('{}', 201));
        await d.drain();
        await d.tick(const Duration(minutes: 2));
        await d.waitCheckpoint('mdblist', 3);
        expect(
          d
              .forTracker('mdblist')
              .map((r) => (jsonDecode(r.body) as Map)['show']),
          everyElement({
            'ids': {'imdb': 'tt5100000'},
            'season': 1,
            'episode': 1,
          }),
        );
        d.expectCheckpoint('mdblist', 2, 'pause', 0.01, season: 1, episode: 1);
      } finally {
        if (!reply.isCompleted) reply.complete(http.Response('{}', 201));
        await d.close();
      }
    },
  );
}
