import 'package:debrify/models/playlist_entry.dart' as owner;
import 'package:debrify/screens/video_player/models/playlist_entry.dart'
    as legacy;
import 'package:debrify/screens/video_player_screen.dart' as screen;
import 'package:debrify/models/movie_collection.dart';
import 'package:debrify/models/series_playlist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('former screen import exposes the same runtime declaration', () {
    const viaScreen = screen.PlaylistEntry(url: 'url', title: 'title');
    const viaOwner = owner.PlaylistEntry(url: 'url', title: 'title');
    const viaLegacy = legacy.PlaylistEntry(url: 'url', title: 'title');
    expect(identical(viaScreen, viaOwner), isTrue);
    expect(identical(viaLegacy, viaOwner), isTrue);
    expect(screen.PlaylistEntry, owner.PlaylistEntry);
    final List<owner.PlaylistEntry> list = <screen.PlaylistEntry>[viaScreen];
    list.add(viaLegacy.copyWithTitle('renamed'));
    expect(list.last, isA<screen.PlaylistEntry>());
    final player = screen.VideoPlayerScreen(
      videoUrl: 'url',
      title: 'title',
      playlist: list,
    );
    expect(player.playlist, same(list));
  });

  test(
    'both relocated consumers accept legacy and neutral entries at runtime',
    () {
      for (final entries in <List<owner.PlaylistEntry>>[
        <legacy.PlaylistEntry>[
          const legacy.PlaylistEntry(
            url: 'one',
            title: 'Example.S01E01.mkv',
            sizeBytes: 100,
          ),
          const legacy.PlaylistEntry(
            url: 'two',
            title: 'Example.S01E02.mkv',
            sizeBytes: 100,
          ),
        ],
        <owner.PlaylistEntry>[
          const owner.PlaylistEntry(
            url: 'one',
            title: 'Example.S01E01.mkv',
            sizeBytes: 100,
          ),
          const owner.PlaylistEntry(
            url: 'two',
            title: 'Example.S01E02.mkv',
            sizeBytes: 100,
          ),
        ],
      ]) {
        final movies = MovieCollection.fromPlaylistWithMainExtras(
          playlist: entries,
        );
        expect(movies.allFiles, same(entries));
        expect(movies.totalFiles, 2);
        final series = SeriesPlaylist.fromPlaylistEntries(
          entries,
          forceSeries: true,
        );
        expect(series.totalEpisodes, 2);
        expect(series.allEpisodes.map((episode) => episode.url), [
          'one',
          'two',
        ]);
        expect(
          series.allEpisodes.map((episode) => episode.seriesInfo.episode),
          [1, 2],
        );
      }
    },
  );
}
