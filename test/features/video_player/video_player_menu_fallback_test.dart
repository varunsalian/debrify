import 'package:debrify/screens/video_player/widgets/player_menu_panel.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/menu_metadata_driver.dart';
import 'support/player_actions.dart';

void main() {
  testWidgets(
    'p13 cached movie tracks opens synchronously before a later quick section',
    (t) async {
      final d = MenuMetadataDriver(t);
      await d.setup();
      try {
        await d.mountMovies();
        d.tracks();
        await d.f.until(t, () => d.pending.length >= 2);
        d.release();
        await d.shown();
        expect(d.panel.contentImdbId, 'tt1300001');
        d.panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final requests = d.searches.length;
        d.tracks();
        playerControls(t).onSpeed();
        await d.shown();
        expect(d.panel.initialSection, PlayerMenuSection.speed);
        expect(d.panel.contentImdbId, 'tt1300001');
        expect(d.searches, hasLength(requests));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 tracks movie collection uses launch identity while background metadata is held',
    (t) async {
      final d = MenuMetadataDriver(t);
      await d.setup();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/known-movie.mp4',
            title: 'Menu.Movie.2024.mkv',
            contentImdbId: 'tt1300999',
            disableAutoResume: true,
            startIndex: 0,
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/known-movie.mp4',
                title: 'Menu.Movie.2024.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/other-movie.mp4',
                title: 'Other.Movie.2023.mkv',
              ),
            ],
          ),
        );
        await d.f.until(t, () => d.pending.isNotEmpty);
        final requests = d.searches.length;
        d.tracks();
        await d.shown();
        expect(d.panel.contentImdbId, 'tt1300999');
        expect(d.panel.contentType, 'movie');
        expect(d.panel.contentSeason, isNull);
        expect(d.panel.contentEpisode, isNull);
        expect(d.searches, hasLength(requests));
        expect(d.pending.every((request) => !request.isCompleted), isTrue);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'p13 tracks and quick menu infer series from the actual playlist',
    (t) async {
      final d = MenuMetadataDriver(t);
      await d.setup();
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: 'https://player.test/series-one.mp4',
            title: 'Show.S03E04.mkv',
            contentImdbId: 'tt1300998',
            disableAutoResume: true,
            startIndex: 0,
            playlist: [
              PlaylistEntry(
                url: 'https://player.test/series-one.mp4',
                title: 'Show.S03E04.mkv',
              ),
              PlaylistEntry(
                url: 'https://player.test/series-two.mp4',
                title: 'Show.S03E05.mkv',
              ),
            ],
          ),
        );
        d.tracks();
        await d.shown();
        expect(d.panel.initialSection, PlayerMenuSection.subtitles);
        expect(d.panel.contentImdbId, 'tt1300998');
        expect(d.panel.contentType, 'series');
        expect(d.panel.contentSeason, 3);
        expect(d.panel.contentEpisode, 4);
        d.panel.onClose();
        await d.f.advance(t, const Duration(milliseconds: 350));
        playerControls(t).onSpeed();
        await d.shown();
        expect(d.panel.initialSection, PlayerMenuSection.speed);
        expect(d.panel.contentImdbId, 'tt1300998');
        expect(d.panel.contentType, 'series');
        expect(d.panel.contentSeason, 3);
        expect(d.panel.contentEpisode, 4);
        expect(d.searches, isEmpty);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}
