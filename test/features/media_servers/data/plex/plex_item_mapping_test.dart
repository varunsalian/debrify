import 'dart:convert';
import 'dart:io';

import 'package:debrify/features/media_servers/data/plex/plex_item_mapping.dart';
import 'package:debrify/models/media_server_library.dart';
import 'package:debrify/models/media_server_watch_state.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _container(String name) =>
    (jsonDecode(
              File(
                'test/fixtures/media_servers/plex/$name.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>)['MediaContainer']
        as Map<String, dynamic>;

Map<String, dynamic> _first(String name) =>
    (_container(name)['Metadata'] as List).first as Map<String, dynamic>;

void main() {
  group('recorded responses', () {
    test('a movie keeps its identity, length and image', () {
      final item = plexItem(_first('movie_metadata'))!;

      expect(item['Id'], '2');
      expect(item['Name'], 'Night of the Living Dead');
      expect(item['Type'], 'Movie');
      expect(item['ProductionYear'], 1968);
      expect(item['RunTimeTicks'], 6023 * 10000);
      expect(item['IsFolder'], isFalse);
      expect(item['ImageTags'], {'Primary': 'thumb'});
      final library = MediaServerLibraryItem.fromJson(item);
      expect(library.playable, isTrue);
      expect(library.imageId, '2');
    });

    test('an episode names its show, season and number', () {
      final library = MediaServerLibraryItem.fromJson(
        plexItem(_first('episode_metadata'))!,
      );

      expect(library.type, 'Episode');
      expect(library.season, 1);
      expect(library.episode, 1);
      expect(library.seriesId, '3');
      expect(library.seriesName, 'Breaking Bad');
      expect(library.numberedEpisode, isTrue);
      expect(library.playable, isTrue);
    });

    test('shows and seasons are folders and never playable', () {
      final show = MediaServerLibraryItem.fromJson(
        plexItem(_first('shows_all'))!,
      );
      final season = MediaServerLibraryItem.fromJson(
        plexItem(_first('show_children'))!,
      );

      expect(show.type, 'Series');
      expect(show.isFolder, isTrue);
      expect(show.playable, isFalse);
      expect(season.type, 'Season');
      expect(season.isFolder, isTrue);
      expect(season.playable, isFalse);
    });

    test('library sections become views with their collection type', () {
      final sections = (_container('sections')['Directory'] as List)
          .cast<Map<String, dynamic>>()
          .map(plexSectionItem)
          .toList();

      expect(sections.map((s) => s!['Id']), ['s1', 's2']);
      expect(sections.map((s) => s!['CollectionType']), ['movies', 'tvshows']);
      expect(
        sections.map((s) => MediaServerLibraryItem.fromJson(s!).isFolder),
        everyElement(isTrue),
      );
    });

    test('a single-file version becomes one direct-play source', () {
      final media =
          (_first('movie_metadata')['Media'] as List).single
              as Map<String, dynamic>;
      final source = plexMediaSource(media)!;

      expect(source['Id'], '2_mkv');
      expect(source['Container'], 'mkv');
      expect(source['Size'], 240555);
      final streams = (source['MediaStreams'] as List)
          .cast<Map<String, dynamic>>();
      expect(streams.first, {
        'Type': 'Video',
        'Codec': 'h264',
        'Width': 1920,
        'Height': 1080,
      });
      expect(streams.last, {
        'Type': 'Audio',
        'IsExternal': false,
        'Language': 'eng',
      });
      expect(jsonEncode(source), isNot(contains('/data/')));
    });

    test('external ids come from the Guid list', () {
      expect(plexExternalIds(_first('movie_metadata')), {
        'imdb:tt0063350',
        'tmdb:10331',
        'tvdb:1831',
      });
    });
  });

  group('watch state', () {
    test('progress, played and last-played time map to the shared model', () {
      final item = plexItem({
        'ratingKey': '16',
        'type': 'movie',
        'title': 'Long',
        'duration': 600023,
        'viewOffset': 91000,
        'lastViewedAt': 1794750335,
      })!;

      final state = MediaServerWatchState.fromItem(item);
      expect(state.positionMs, 91000);
      expect(state.durationMs, 600023);
      expect(state.played, isFalse);
      expect(state.lastPlayedAtMs, 1794750335 * 1000);
      expect(state.hasPartialBookmark, isTrue);
    });

    test('an item never played still has a boolean played flag', () {
      final state = MediaServerWatchState.fromItem(
        plexItem({'ratingKey': '1', 'type': 'movie', 'duration': 1000})!,
      );
      expect(state.played, isFalse);
      expect(state.positionMs, 0);
      expect(state.lastPlayedAtMs, isNull);
    });

    test('a view count marks the item played', () {
      final item = plexItem({
        'ratingKey': '1',
        'type': 'movie',
        'viewCount': 2,
      })!;
      expect(MediaServerWatchState.fromItem(item).played, isTrue);
    });
  });

  group('rejected input', () {
    test('ids that are not plain numbers are refused', () {
      expect(plexItem({'ratingKey': '../1', 'type': 'movie'}), isNull);
      expect(plexItem({'ratingKey': '1', 'type': 'artist'}), isNull);
      expect(plexSectionItem({'key': '1/../2'}), isNull);
      expect(plexNumericId(7), '7');
      expect(plexNumericId('7a'), isNull);
    });

    Map<String, dynamic> media(List<Map<String, dynamic>> parts) => {
      'container': 'mkv',
      'Part': parts,
    };

    test('stacked, missing and inaccessible files are not sources', () {
      expect(
        plexMediaSource(
          media([
            {'id': 1, 'container': 'mkv'},
            {'id': 2, 'container': 'mkv'},
          ]),
        ),
        isNull,
      );
      expect(
        plexMediaSource(
          media([
            {'id': 1, 'container': 'mkv', 'exists': false},
          ]),
        ),
        isNull,
      );
      expect(
        plexMediaSource(
          media([
            {'id': 1, 'container': 'mkv', 'accessible': false},
          ]),
        ),
        isNull,
      );
      expect(
        plexMediaSource(
          media([
            {'id': 1, 'container': 'm/kv'},
          ]),
        ),
        isNull,
      );
    });

    test('a file Plex has not analysed yet still plays as a plain file', () {
      final source = plexMediaSource({
        'Part': [
          {'id': 4},
        ],
      })!;
      expect(source['Id'], '4_file');
      expect(source.containsKey('Container'), isFalse);
    });

    test('source ids round-trip and reject anything else', () {
      expect(plexPartFromSourceId('12_mkv'), (partId: '12', container: 'mkv'));
      expect(plexPartFromSourceId('12'), isNull);
      expect(plexPartFromSourceId('x_mkv'), isNull);
      expect(plexPartFromSourceId('12_m.kv'), isNull);
    });
  });

  group('HDR and legacy ids', () {
    test('Dolby Vision and PQ transfer reach the shared stream keys', () {
      final source = plexMediaSource({
        'container': 'mkv',
        'Part': [
          {
            'id': 9,
            'container': 'mkv',
            'Stream': [
              {
                'streamType': 1,
                'codec': 'hevc',
                'width': 3840,
                'height': 2160,
                'colorTrc': 'smpte2084',
                'DOVIPresent': true,
                'DOVIProfile': 8,
              },
            ],
          },
        ],
      })!;
      final video = (source['MediaStreams'] as List).first as Map;
      expect(video['ColorTransfer'], 'smpte2084');
      expect(video['VideoRange'], 'DOVI');
      expect(video['DvProfile'], 8);
    });

    test('legacy agent guids still give exact ids', () {
      expect(
        plexExternalIds({
          'guid': 'com.plexapp.agents.imdb://tt0063350?lang=en',
        }),
        {'imdb:tt0063350'},
      );
      expect(
        plexExternalIds({
          'guid': 'com.plexapp.agents.themoviedb://10331?lang=en',
        }),
        {'tmdb:10331'},
      );
      expect(
        plexExternalIds({'guid': 'com.plexapp.agents.thetvdb://81189?lang=en'}),
        {'tvdb:81189'},
      );
      expect(plexExternalIds({'guid': 'local://12'}), isEmpty);
    });
  });
}
