import 'package:debrify/features/sources/data/service_source_search_repository.dart';
import 'package:debrify/features/sources/models/source_search_request.dart';
import 'package:debrify/features/sources/models/source_search_result.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/services/iptv_source_search.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/stremio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import '../fakes/fake_source_search_services.dart';

Torrent row(String name) => Torrent(
  rowid: 0,
  infohash: name,
  name: name,
  sizeBytes: 0,
  createdUnix: 0,
  seeders: 0,
  leechers: 0,
  completed: 0,
  scrapedDate: 0,
);
AdvancedSearchSelection selection({
  bool custom = false,
  String? video,
  bool series = true,
  int? episode = 2,
}) => AdvancedSearchSelection(
  imdbId: 'tt-fixture',
  title: 'Fixture',
  isSeries: series,
  season: 1,
  episode: episode,
  contentType: series ? 'series' : 'movie',
  stremioAddonKey: custom ? 'origin-config' : null,
  stremioCatalogId: custom ? 'private-parent' : null,
  stremioVideoId: video,
);

void main() {
  late FakeSourceSearchServices fake;
  late List<String> events;
  late List<List<Torrent>> batches;
  late List<IptvSourceResult> statuses;
  late bool active;
  setUp(() {
    fake = FakeSourceSearchServices();
    events = [];
    batches = [];
    statuses = [];
    active = true;
  });
  Future<SourceSearchResult?> run({
    AdvancedSearchSelection? chosen,
    String? keyword,
    List<int> seasons = const [],
  }) => fake.repository.search(
    SourceSearchRequest(
      selection: chosen ?? selection(),
      keyword: keyword,
      availableSeasons: seasons,
    ),
    shouldContinue: () => active,
    onBatch: (source, rows) {
      events.add('batch:$source');
      batches.add(rows);
    },
    onIptvResult: (result) {
      events.add('iptv:${result.key}');
      statuses.add(result);
    },
  );

  test(
    'keyword keeps exact query, ordering and synthetic rows, without IPTV',
    () async {
      final pending = run(keyword: '  Exact QUERY  ');
      expect(fake.calls, ['keyword']);
      expect(fake.arguments, {'query': '  Exact QUERY  ', 'preserve': true});
      final rows = [row('one')];
      fake.batch!('engine', rows);
      rows.clear();
      expect(batches.single.single.name, 'one');
      expect(() => batches.single.clear(), throwsUnsupportedError);
      fake.main.complete({
        'torrents': [row('final')],
      });
      final result = (await pending)!;
      expect(result.torrents.single.name, 'final');
      expect(result.addonStatuses, isEmpty);
      expect(result.iptv, isEmpty);
      fake.batch!('late', [row('late')]);
      expect(batches, hasLength(1));
    },
  );

  test(
    'IPTV starts alongside IMDb, emits status before batch, and completion waits for both',
    () async {
      final seasons = [1, 3];
      final pending = run(chosen: selection(episode: null), seasons: seasons);
      seasons.clear();
      expect(fake.calls, ['iptv', 'imdb']);
      expect(fake.arguments, {
        'defer': true,
        'id': 'tt-fixture',
        'movie': false,
        'season': 1,
        'episode': null,
        'type': 'series',
        'seasons': [1, 3],
        'preserve': true,
        'addon': null,
        'video': null,
      });
      final rows = [row('iptv')];
      final status = IptvSourceResult('playlist', 'Playlist', 'Ready', rows);
      fake.iptvResult!(status);
      expect(events, ['iptv:playlist', 'batch:playlist']);
      rows.clear();
      expect(statuses.single.torrents.single.name, 'iptv');
      var done = false;
      pending.then((_) => done = true);
      const addon = AddonSearchStatus(
        addonId: 'a',
        name: 'Addon',
        sourceKey: 'stremio:a',
        count: 1,
      );
      fake.main.complete({
        'torrents': [row('main')],
        'addonStatuses': [addon],
      });
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      fake.iptv.complete([
        IptvSourceResult('playlist', 'Playlist', 'Ready', [row('iptv')]),
      ]);
      final result = (await pending)!;
      expect(result.torrents.map((row) => row.name), ['main', 'iptv']);
      expect(result.addonStatuses, [addon]);
      expect(() => result.iptv.single.torrents.clear(), throwsUnsupportedError);
      fake.iptvResult!(status);
      fake.batch!('late', [row('late')]);
      expect(events, ['iptv:playlist', 'batch:playlist']);
      expect(fake.shouldContinue!(), isFalse);
    },
  );

  test(
    'explicit custom video ID is trimmed and passed exactly without IMDb guessing',
    () async {
      final pending = run(
        chosen: selection(custom: true, video: ' arbitrary/video:id '),
      );
      expect(fake.calls, ['imdb']);
      expect(fake.arguments['video'], 'arbitrary/video:id');
      expect(fake.arguments['addon'], 'origin-config');
      expect(fake.arguments['seasons'], isNull);
      fake.main.complete({'torrents': []});
      await pending;
    },
  );

  for (final available in [false, true]) {
    test(
      'custom episode resolution precedes search; available=$available',
      () async {
        final pending = run(chosen: selection(custom: true));
        expect(fake.calls, ['resolve']);
        expect(fake.arguments, {
          'resolveAddon': 'origin-config',
          'resolveCatalog': 'private-parent',
          'resolveSeason': 1,
          'resolveEpisode': 2,
        });
        fake.video.complete(available ? 'resolved-custom-id' : null);
        await Future<void>.delayed(Duration.zero);
        if (available) {
          expect(fake.calls, ['resolve', 'imdb']);
          expect(fake.arguments['video'], 'resolved-custom-id');
          fake.main.complete({'torrents': []});
        } else {
          expect(fake.calls, ['resolve']);
        }
        expect((await pending)!.torrents, isEmpty);
      },
    );
  }

  test(
    'unavailable custom selection suppresses the legacy test override too',
    () async {
      var calls = 0;
      final repo = ServiceSourceSearchRepository(
        owner: ProfileSessionMemory.captureOwner(),
        searchOverride: (_) async {
          calls++;
          return {'torrents': []};
        },
      );
      final result = await repo.search(
        SourceSearchRequest(selection: selection(custom: true, episode: null)),
        onBatch: (_, _) {},
        onIptvResult: (_) {},
        shouldContinue: () => true,
      );
      expect(result!.torrents, isEmpty);
      expect(calls, 0);
    },
  );

  for (final retire in ['query', 'profile']) {
    test(
      '$retire during episode resolution prevents downstream RPCs',
      () async {
        final pending = run(chosen: selection(custom: true));
        if (retire == 'query') {
          active = false;
        } else {
          ProfileSessionMemory.clearAll();
        }
        fake.video.complete('resolved');
        expect(await pending, isNull);
        expect(fake.calls, ['resolve']);
      },
    );
    test(
      '$retire suppresses callbacks, completion and late main errors',
      () async {
        final pending = run();
        if (retire == 'query') {
          active = false;
        } else {
          ProfileSessionMemory.clearAll();
        }
        fake.batch!('late', [row('late')]);
        fake.iptvResult!(
          IptvSourceResult('late', 'Late', 'Ready', [row('late')]),
        );
        fake.main.completeError(StateError('fixture'));
        expect(await pending, isNull);
        fake.iptv.completeError(StateError('late IPTV'));
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);
      },
    );
  }

  test(
    'current main failure propagates once and observes late IPTV failure',
    () async {
      final pending = run();
      final assertion = expectLater(pending, throwsStateError);
      fake.main.completeError(StateError('main'));
      await assertion;
      fake.iptv.completeError(StateError('IPTV'));
      await Future<void>.delayed(Duration.zero);
      expect(fake.shouldContinue!(), isFalse);
      expect(fake.calls, ['iptv', 'imdb']);
    },
  );

  test(
    'current IPTV failure remains an error after the main result succeeds',
    () async {
      final pending = run();
      final assertion = expectLater(pending, throwsStateError);
      fake.iptv.completeError(StateError('IPTV'));
      fake.main.complete({'torrents': []});
      await assertion;
    },
  );

  test('retired initial action does not resolve metadata or search', () async {
    final repo = fake.repository;
    ProfileSessionMemory.clearAll();
    expect(await run(chosen: selection(custom: true)), isNull);
    expect(repo.isCurrent, isFalse);
    expect(fake.calls, isEmpty);
  });
}
