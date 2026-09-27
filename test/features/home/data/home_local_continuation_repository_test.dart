import 'dart:async';

import 'package:debrify/features/home/data/home_local_continuation_repository.dart';
import 'package:debrify/models/custom_series_identity.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/tracking_source.dart';
import 'package:flutter_test/flutter_test.dart';

HomeLocalContinuationRepository repository({
  required Future<List<Map<String, dynamic>>> Function() items,
  Future<List<StremioAddon>> Function()? addons,
  Future<Map<String, dynamic>?> Function(String)? episode,
  Future<Map<String, dynamic>?> Function(String)? movie,
}) => HomeLocalContinuationRepository(
  readProgressSource: () async => WatchProgressSource.local,
  readEnabled: () async => true,
  readItems: items,
  readAddons: addons ?? () => throw StateError('Unexpected addon read'),
  readEpisode: episode ?? (_) async => null,
  readMovie: movie ?? (_) async => null,
);

void main() {
  test(
    'joins recency order with exact progress, episode and remaining-time rules',
    () async {
      final calls = <String>[];
      final subject = repository(
        items: () async => [
          {},
          {'imdbId': ''},
          {'imdbId': 'tt1', 'contentType': 'series', 'title': 'Series'},
          {
            'imdbId': 'tt2',
            'posterUrl': 'poster',
            'year': '2026',
            'addonId': 'saved',
          },
          {'imdbId': 'tt3', 'contentType': 'series'},
          {'imdbId': 'tt4'},
          {'imdbId': 'tt5'},
        ],
        episode: (id) async {
          calls.add('episode:$id');
          return id == 'tt1'
              ? {
                  'finished': true,
                  'positionMs': 60000,
                  'durationMs': 180001,
                  'season': 2,
                  'episode': 5,
                }
              : {'positionMs': 100, 'durationMs': 0, 'season': 0, 'episode': 1};
        },
        movie: (id) async {
          calls.add('movie:$id');
          return switch (id) {
            'tt2' => {'positionMs': 150000, 'durationMs': 100000},
            'tt4' => {'positionMs': -100, 'durationMs': 100000},
            _ => null,
          };
        },
      );
      final result = (await subject.load(isCurrent: () => true))!;
      expect(calls, [
        'episode:tt1',
        'movie:tt2',
        'episode:tt3',
        'movie:tt4',
        'movie:tt5',
      ]);
      expect(result.items.map((m) => m.id), [
        'tt1',
        'tt2',
        'tt3',
        'tt4',
        'tt5',
      ]);
      expect(result.items[1].name, 'Untitled');
      expect(result.items[1].poster, 'poster');
      expect(result.items[1].year, '2026');
      expect(result.progress, {'tt1': 1.0, 'tt2': 1.0, 'tt4': 0.0});
      expect(result.episode, {'tt1': 'S2 · E5'});
      expect(result.episodeRefs, {'tt1': (season: 2, episode: 5)});
      expect(result.remainingMinutes, {'tt1': 3});
      expect(result.addonIds['tt2'], 'saved');
      expect(result.ids, {'tt1', 'tt2', 'tt3', 'tt4', 'tt5'});
      expect(() => result.items.clear(), throwsUnsupportedError);
      expect(() => result.progress.clear(), throwsUnsupportedError);
      expect(() => result.episode.clear(), throwsUnsupportedError);
      expect(() => result.episodeRefs.clear(), throwsUnsupportedError);
      expect(() => result.remainingMinutes.clear(), throwsUnsupportedError);
      expect(() => result.addonIds.clear(), throwsUnsupportedError);
      expect(() => result.ids.clear(), throwsUnsupportedError);
    },
  );

  test(
    'custom identity resolves first matching addon and native ids stay native',
    () async {
      final addon = StremioAddon(
        id: 'custom',
        name: 'Custom',
        manifestUrl: 'https://fixture.invalid/manifest.json',
        baseUrl: 'https://fixture.invalid',
        addedAt: DateTime.utc(2026),
      );
      final custom = CustomSeriesIdentity(
        addon.portableConfigurationKey,
        'cut',
      ).id;
      var reads = 0;
      final result = (await repository(
        items: () async => [
          {'imdbId': custom, 'contentType': 'series', 'addonId': 'obsolete'},
          {'imdbId': 'tmdb:movie:42'},
        ],
        addons: () async {
          reads++;
          return [addon];
        },
      ).load(isCurrent: () => true))!;
      expect(reads, 1);
      expect(result.items.first.id, 'cut');
      expect(result.items.first.imdbId, custom);
      expect(result.items.first.sourceAddon, same(addon));
      expect(result.addonIds[custom], addon.portableConfigurationKey);
      expect(result.items.last.id, 'tmdb:movie:42');
      expect(result.items.last.imdbId, isNull);
    },
  );

  for (final stage in ['before', 'history', 'addons', 'episode', 'movie']) {
    test('retirement at $stage stops the next implicit profile read', () async {
      var active = stage != 'before';
      final trace = <String>[];
      Future<T> read<T>(String name, T value) async {
        trace.add(name);
        if (stage == name) active = false;
        return value;
      }

      final custom = const CustomSeriesIdentity('source', 'series').id;
      final subject = repository(
        items: () => read('history', [
          {'imdbId': custom, 'contentType': 'series'},
          {'imdbId': 'tt2'},
          {'imdbId': 'tt3'},
        ]),
        addons: () => read('addons', <StremioAddon>[]),
        episode: (_) => read('episode', <String, dynamic>{}),
        movie: (_) => read('movie', <String, dynamic>{}),
      );
      expect(await subject.load(isCurrent: () => active), isNull);
      final order = ['history', 'addons', 'episode', 'movie'];
      expect(
        trace,
        stage == 'before' ? [] : order.take(order.indexOf(stage) + 1),
      );
    });
  }

  test(
    'pending record failure propagates without returning a partial join',
    () async {
      final pending = Completer<Map<String, dynamic>?>();
      final failure = StateError('unavailable');
      final requests = <String>[];
      final subject = repository(
        items: () async => [
          {'imdbId': 'tt1'},
          {'imdbId': 'tt2'},
        ],
        movie: (id) {
          requests.add(id);
          return pending.future;
        },
      );
      final load = subject.load(isCurrent: () => true);
      final expectation = expectLater(load, throwsA(same(failure)));
      await Future<void>.delayed(Duration.zero);
      expect(requests, ['tt1']);
      pending.completeError(failure);
      await expectation;
      expect(requests, ['tt1']);
    },
  );
}
