// Anime episodes are renamed to the IMDb coordinate only when the meta's own
// numbering is the IMDb show's; per-cour numbering, Kitsu and TMDB IDs keep
// the addon's IDs, so sources that work today keep working.

import 'package:debrify/services/stremio_anime_episode_ids.dart';
import 'package:flutter_test/flutter_test.dart';

List<Object?> ids(List<Map<String, dynamic>> videos) => [
  for (final video in videos) video['id'],
];

Map<String, dynamic> ep(String id, Object? season, Object? episode) => {
  'id': id,
  'season': season,
  'episode': episode,
};

void main() {
  const meta = {'id': 'mal:21', 'imdb_id': 'tt0388629'};

  test('a multi-season TVDB layout takes the IMDb coordinates', () {
    final videos = [
      ep('mal:21:1', 1, 1),
      ep('mal:21:61', 2, 1),
      ep('anilist:21:62', '2', '2'),
      ep('anidb:69:3', 2, 3),
    ];

    expect(ids(withImdbAnimeEpisodeIds(meta, videos)), [
      'tt0388629:1:1',
      'tt0388629:2:1',
      'tt0388629:2:2',
      'tt0388629:2:3',
    ]);
    expect(videos.first['id'], 'mal:21:1', reason: 'input is not mutated');
  });

  test('an IMDb-named fallback episode proves a single-season layout', () {
    final videos = [ep('mal:30:1', 1, 1), ep('tt9999999:1:2', 1, 2)];

    expect(ids(withImdbAnimeEpisodeIds({'imdb_id': 'tt9999999'}, videos)), [
      'tt9999999:1:1',
      'tt9999999:1:2',
    ]);
  });

  test('an IMDb-named special proves the layout too', () {
    final videos = [ep('tt9999999:0:1', 0, 1), ep('mal:30:1', 1, 1)];

    expect(ids(withImdbAnimeEpisodeIds({'imdb_id': 'tt9999999'}, videos)), [
      'tt9999999:0:1',
      'tt9999999:1:1',
    ]);
  });

  test('IMDb IDs that disagree with the numbering keep the addon IDs', () {
    // Absolute order: everything is season 1, while the unmapped episodes
    // carry their IMDb season. Season 1 episode 13 is not IMDb S1E13.
    final videos = [
      ep('mal:30:1', 1, 1),
      ep('mal:31:1', 2, 1),
      ep('tt9999999:2:1', 1, 13),
    ];

    expect(
      withImdbAnimeEpisodeIds({'imdb_id': 'tt9999999'}, videos),
      same(videos),
    );
  });

  test('a show-wide layout names a single cour by its IMDb coordinates', () {
    final videos = [ep('mal:30:1', 1, 1), ep('mal:30:2', 1, 2)];

    expect(
      ids(
        withImdbAnimeEpisodeIds({
          'imdb_id': 'tt9999999',
          '_metaProvider': 'tvdb',
        }, videos),
      ),
      ['tt9999999:1:1', 'tt9999999:1:2'],
    );
    expect(
      ids(
        withImdbAnimeEpisodeIds(
          {'imdb_id': 'tt9999999', '_metaProvider': 'tvdb'},
          [...videos, ep('mal:31:1', 1, 13)],
        ),
      ),
      ['mal:30:1', 'mal:30:2', 'mal:31:1'],
      reason: 'several cours in one season may be absolute order',
    );
  });

  test('one absolute-order cour keeps the addon IDs', () {
    // TVDB absolute order: one MAL entry spanning IMDb seasons, numbered
    // 1..N in season 1 while its IDs count within each season.
    final videos = [ep('mal:21:1', 1, 1), ep('mal:21:5', 1, 66)];

    expect(
      withImdbAnimeEpisodeIds({
        'imdb_id': 'tt0388629',
        '_metaProvider': 'tvdb',
      }, videos),
      same(videos),
    );
  });

  test('the MAL and Kitsu layouts are never renamed', () {
    final videos = [ep('mal:21:1', 1, 1), ep('mal:2:1', 2, 1)];

    for (final provider in ['mal', 'kitsu']) {
      expect(
        withImdbAnimeEpisodeIds({
          'imdb_id': 'tt0388629',
          '_metaProvider': provider,
        }, videos),
        same(videos),
      );
    }
  });

  test('per-cour numbering from season 1 keeps the addon IDs', () {
    // AIOMetadata's MAL layout for a later cour: season 1 with the
    // franchise IMDb ID. IMDb S1 would be the wrong episodes.
    final videos = [ep('mal:25777:1', 1, 1), ep('mal:25777:2', 1, 2)];

    expect(
      withImdbAnimeEpisodeIds({'imdb_id': 'tt2560140'}, videos),
      same(videos),
    );
  });

  test('Kitsu, TMDB, specials and other IDs keep their names', () {
    final videos = [
      ep('kitsu:12:1', 1, 1),
      ep('tmdb:37854:2:1', 2, 1),
      ep('mal:21:900', 0, 900),
      ep('mal:21:5', null, 5),
      ep('cut-1', 2, 2),
    ];

    expect(ids(withImdbAnimeEpisodeIds(meta, videos)), ids(videos));
  });

  test('without a valid IMDb ID nothing changes', () {
    final videos = [ep('mal:21:1', 1, 1), ep('mal:2:1', 2, 1)];

    expect(withImdbAnimeEpisodeIds({'id': 'mal:21'}, videos), same(videos));
    expect(
      withImdbAnimeEpisodeIds({'imdb_id': 'mal:21'}, videos),
      same(videos),
    );
    expect(
      ids(withImdbAnimeEpisodeIds({'_imdbId': 'tt0388629'}, videos)),
      ['tt0388629:1:1', 'tt0388629:2:1'],
      reason: 'the stamped IMDb ID counts too',
    );
  });

  test('only anime catalog IDs of an IMDb show are checked again', () {
    expect(mayHaveImdbAnimeEpisodes('mal:21', 'tt0388629'), isTrue);
    expect(mayHaveImdbAnimeEpisodes('anilist:21', 'tt0388629'), isTrue);
    expect(mayHaveImdbAnimeEpisodes('kitsu:12', 'tt0388629'), isFalse);
    expect(mayHaveImdbAnimeEpisodes('OnePace', 'tt0388629'), isFalse);
    expect(mayHaveImdbAnimeEpisodes('mal:21', 'mal:21'), isFalse);
  });
}
