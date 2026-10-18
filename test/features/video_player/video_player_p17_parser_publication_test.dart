import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/player_actions.dart';
import 'support/tv_episode_driver.dart';

void main() {
  for (final kind in ['non-list', 'mixed', 'maps-only', 'none']) {
    testWidgets(
      'P17 $kind Stremio source parsing publishes the source action before dispatch',
      (t) async {
        final d = TvEpisodeDriver(t);
        await d.initialize();
        final first = episodeSource('First.S01E01');
        final second = episodeSource('Second.S01E01');
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: 'https://player.test/a.mp4',
              title: 'A',
              stremioTvCurrentChannelId: 'a',
              stremioTvNextProvider: (id) async => {
                'url': 'https://player.test/b.mp4',
                'title': 'B',
                'channelId': 'b',
                'stremioSources': kind == 'non-list'
                    ? 'unavailable'
                    : ['mixed', 'maps-only'].contains(kind)
                    ? [first.toJson(), if (kind == 'mixed') 42, second.toJson()]
                    : [],
                'stremioCurrentSourceIndex': 1,
                'sourceResolver': (Torrent source) async => source.directUrl,
              },
            ),
          );
          final dynamic next = playerControls(t).onNext!;
          await d.f.finish<dynamic>(t, d.observe<dynamic>(() => next()));
          expect(d.opens.last.uri, 'https://player.test/b.mp4');
          final action = playerControls(t).onShowStremioSources;
          if (['mixed', 'maps-only'].contains(kind)) {
            expect(action, isNotNull);
            final sheet = await d.sourceSheet();
            expect(sheet.sources.map((source) => source.directUrl), [
              first.directUrl,
              second.directUrl,
            ]);
            expect(sheet.currentSourceIndex, 1);
          } else {
            expect(action, isNull);
          }
          expect(d.errors, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
