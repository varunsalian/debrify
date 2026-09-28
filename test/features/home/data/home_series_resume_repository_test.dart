import 'dart:async';

import 'package:debrify/features/home/data/home_series_resume_repository.dart';
import 'package:debrify/features/home/models/home_series_resume_signals.dart';
import 'package:debrify/models/advanced_search_selection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/models/trakt_continue_watching_item.dart';
import 'package:flutter_test/flutter_test.dart';

const show = StremioMeta(id: 'tt123', type: 'series', name: 'Exact Title');
const selected = AdvancedSearchSelection(
  imdbId: 'tt123',
  title: 'Show',
  isSeries: true,
  season: 2,
  episode: 3,
  traktProgressPercent: 42,
  traktSource: true,
);
TraktContinueWatchingItem card({
  String id = 'tt123',
  int? timestamp = 1000,
  String type = 'series',
}) => TraktContinueWatchingItem(
  meta: StremioMeta(id: id, type: type, name: 'Card'),
  traktContentType: 'shows',
  season: 2,
  episode: 3,
  progress: 42,
  pausedAtMs: timestamp,
);

class Fixture {
  bool owner = true, view = true;
  final calls = <String>[];
  final logs = <String>[];
  final selectedItems = <TraktContinueWatchingItem>[];
  String? gateStep, failureStep;
  final entered = Completer<void>(), release = Completer<void>();
  final error = StateError('read failure');
  AdvancedSearchSelection? resolved = selected;
  List<TraktContinueWatchingItem> items = [card()];
  Map<String, dynamic>? byId = {
    'season': 2,
    'episode': 3,
    'positionMs': 500,
    'durationMs': 1000,
    'updatedAt': 1000,
    'finished': true,
  };
  Map<String, dynamic>? byTitle = {'season': 4, 'episode': 5};
  HomeSimklResumeSignal? paused = (
    season: 2,
    episode: 3,
    progress: 58,
    pausedAt: DateTime.utc(2026),
  );
  ({int season, int episode})? next = (season: 2, episode: 4);

  Future<void> step(String name) async {
    calls.add(name);
    if (failureStep == name) throw error;
    if (gateStep == name) {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
  }

  late final repository = HomeSeriesResumeRepository(
    selectTraktItem: (item, current) async {
      selectedItems.add(item);
      await step('select');
      return resolved;
    },
    readTraktShows: () async {
      await step('feed');
      return items;
    },
    resolveTraktShow: (id) async {
      await step('resolve:$id');
      return resolved;
    },
    readSimklPaused: (id) async {
      await step('paused:$id');
      return paused;
    },
    readSimklNext: (id) async {
      await step('next:$id');
      return next;
    },
    readLocalById: (id) async {
      await step('id:$id');
      return byId;
    },
    readLocalByTitle: (title) async {
      await step('title:$title');
      return byTitle;
    },
    isOwnerCurrent: () => owner,
    log: logs.add,
  );

  Future<Object?> read(String path, {StremioMeta item = show}) =>
      switch (path) {
        'cached' => repository.traktSelection(
          item,
          cached: card(),
          isCurrent: () => view,
        ),
        'feed' => repository.traktSelection(item, isCurrent: () => view),
        'cachedPosition' => repository.traktPosition(
          item,
          cached: card(),
          isCurrent: () => view,
        ),
        'resolve' => repository.traktPosition(item, isCurrent: () => view),
        'local' => repository.local(
          item,
          item.progressId ?? item.id,
          isCurrent: () => view,
        ),
        'paused' => repository.simklPaused(item, isCurrent: () => view),
        _ => repository.simklNext(item, isCurrent: () => view),
      };
}

void main() {
  test(
    'cached Trakt signal keeps exact selection and activity time without feed',
    () async {
      final f = Fixture();
      final cached = card(timestamp: 9876);
      final result = await f.repository.traktSelection(
        show,
        cached: cached,
        isCurrent: () => true,
      );
      expect(result!.sel, same(selected));
      expect(result.tsMs, 9876);
      expect(f.selectedItems.single, same(cached));
      expect(f.calls, ['select']);
      expect(f.logs.first, contains('trakt-home-card-hit'));
      expect(f.logs.last, contains('trakt-home-card-selection'));
    },
  );

  test(
    'live Trakt signal chooses first exact ID and keeps that item timestamp',
    () async {
      final first = card(timestamp: 2000);
      final f = Fixture()
        ..items = [card(id: 'TT123'), first, card(timestamp: 3000)];
      final result = await f.repository.traktSelection(
        show,
        isCurrent: () => true,
      );
      expect(result!.tsMs, 2000);
      expect(result.sel, same(selected));
      expect(f.selectedItems.single, same(first));
      expect(f.calls, ['feed', 'select']);
      expect(f.logs.map((v) => v.split(' ')[1]), [
        'trakt-live-lookup',
        'trakt-live-match',
      ]);
    },
  );

  test('live Trakt miss and null selection do not invent a position', () async {
    final f = Fixture()..items = [card(id: 'TT123'), card(id: 'tt124')];
    expect(await f.read('feed'), isNull);
    expect(f.calls, ['feed']);
    f.resolved = null;
    expect(await f.read('cached'), isNull);
    expect(await f.read('cachedPosition'), isNull);
    expect(await f.read('resolve'), isNull);
  });

  test(
    'Trakt progress identity overrides raw catalog ID without normalization',
    () async {
      const item = StremioMeta(
        id: 'catalog-id',
        imdbId: 'tt456',
        type: 'series',
        name: 'Show',
      );
      final f = Fixture()..items = [card(id: 'catalog-id'), card(id: 'tt456')];
      await f.read('feed', item: item);
      expect(f.selectedItems.single.id, 'tt456');
      await f.read('resolve', item: item);
      expect(f.calls.last, 'resolve:tt456');
    },
  );

  test(
    'cached Trakt movies resolve; uncached movies and empty IDs skip reads',
    () async {
      final f = Fixture();
      const movie = StremioMeta(id: 'tt123', type: 'movie', name: 'Movie');
      expect(await f.read('cached', item: movie), isNotNull);
      expect(await f.read('cachedPosition', item: movie), isNotNull);
      expect(f.calls, ['select', 'select']);
      for (final item in [
        movie,
        const StremioMeta(id: '', type: 'series', name: 'Empty'),
      ]) {
        expect(await f.read('feed', item: item), isNull);
        expect(await f.read('resolve', item: item), isNull);
      }
      expect(f.calls, ['select', 'select']);
    },
  );

  test(
    'Trakt label keeps nullable coordinates and uses the live resolver',
    () async {
      final f = Fixture()
        ..resolved = const AdvancedSearchSelection(
          imdbId: 'tt123',
          title: 'Show',
          isSeries: true,
          episode: 7,
        );
      expect(await f.read('cachedPosition'), (
        started: true,
        season: null,
        episode: 7,
      ));
      expect(await f.read('resolve'), (
        started: true,
        season: null,
        episode: 7,
      ));
      expect(f.calls, ['select', 'resolve:tt123']);
    },
  );

  test(
    'local canonical record wins and preserves finished, percentage and timestamp',
    () async {
      final f = Fixture();
      expect(await f.read('local'), (
        season: 2,
        episode: 3,
        pct: 50.0,
        tsMs: 1000,
        finished: true,
      ));
      expect(f.calls, ['id:tt123']);
    },
  );

  test(
    'incomplete local coordinates replace the whole record with title fallback',
    () async {
      final f = Fixture()
        ..byId = {'season': 2, 'finished': true, 'positionMs': 999}
        ..byTitle = {
          'season': 4,
          'episode': 5,
          'position': 25,
          'duration': 100,
          'updatedAt': 345.9,
        };
      expect(await f.read('local'), (
        season: 4,
        episode: 5,
        pct: 25.0,
        tsMs: 345,
        finished: false,
      ));
      expect(f.calls, ['id:tt123', 'title:Exact Title']);
    },
  );

  test(
    'native/custom identities never fall back by title, including malformed custom prefix',
    () async {
      for (final id in ['tmdb:123', 'simkl:123', 'custom-series:malformed']) {
        final f = Fixture()..byId = null;
        expect(
          await f.repository.local(show, id, isCurrent: () => true),
          isNull,
        );
        expect(f.calls, ['id:$id']);
      }
    },
  );

  test(
    'local missing or non-integer coordinates return null after fallback',
    () async {
      for (final value in [
        null,
        {'season': 2.0, 'episode': 3},
        {'season': 2},
      ]) {
        final f = Fixture()
          ..byId = null
          ..byTitle = value;
        expect(await f.read('local'), isNull);
      }
    },
  );

  test(
    'local milliseconds take precedence including zero; percentage is clamped',
    () async {
      for (final (position, duration, expected) in [
        (0, 100, 0.0),
        (-10, 100, 0.0),
        (150, 100, 100.0),
        (40, 0, null),
      ]) {
        final f = Fixture()
          ..byId = {
            'season': 2,
            'episode': 3,
            'positionMs': position,
            'durationMs': duration,
            'position': 77,
            'duration': 100,
            'updatedAt': -1,
            'finished': 'true',
          };
        expect(await f.read('local'), (
          season: 2,
          episode: 3,
          pct: expected,
          tsMs: null,
          finished: false,
        ));
      }
    },
  );

  for (final source in ['paused', 'next']) {
    test(
      'Simkl $source keeps supported IDs, raw signal and series-only eligibility',
      () async {
        final f = Fixture();
        for (final id in ['tt123', 'tmdb:123', 'simkl:123']) {
          final result = await f.read(
            source,
            item: StremioMeta(id: id, type: 'series', name: 'Show'),
          );
          expect(result, source == 'paused' ? f.paused : f.next);
          expect(f.calls.last, '$source:$id');
        }
        for (final item in [
          const StremioMeta(id: 'tt123', type: 'movie', name: 'Movie'),
          for (final id in [
            '',
            'channel:1',
            'custom-series:abc',
            'tmdb:series:123',
          ])
            StremioMeta(id: id, type: 'series', name: 'Show'),
        ]) {
          expect(await f.read(source, item: item), isNull);
        }
        expect(f.calls, hasLength(3));
      },
    );
  }

  const paths = [
    'cached',
    'feed',
    'cachedPosition',
    'resolve',
    'local',
    'paused',
    'next',
  ];
  for (final path in paths) {
    for (final retirement in ['owner', 'view']) {
      test('$path rejects $retirement retirement before any read', () async {
        final f = Fixture();
        if (retirement == 'owner') {
          f.owner = false;
        } else {
          f.view = false;
        }
        expect(await f.read(path), isNull);
        expect(f.calls, isEmpty);
      });
    }
  }

  const stages = [
    ('cached', 'select'),
    ('feed', 'feed'),
    ('feed', 'select'),
    ('cachedPosition', 'select'),
    ('resolve', 'resolve:tt123'),
    ('local', 'id:tt123'),
    ('local', 'title:Exact Title'),
    ('paused', 'paused:tt123'),
    ('next', 'next:tt123'),
  ];
  for (final (path, stage) in stages) {
    for (final retirement in ['owner', 'view']) {
      test(
        '$path rejects late $stage result after $retirement retirement',
        () async {
          final f = Fixture()..gateStep = stage;
          if (stage == 'title:Exact Title' || stage == 'id:tt123') {
            f.byId = null;
          }
          final pending = f.read(path);
          await f.entered.future;
          final issued = List.of(f.calls);
          if (retirement == 'owner') {
            f.owner = false;
          } else {
            f.view = false;
          }
          f.release.complete();
          expect(await pending, isNull);
          expect(f.calls, issued);
        },
      );
    }
    test('$path preserves $stage errors', () async {
      final f = Fixture()..failureStep = stage;
      if (stage == 'title:Exact Title') f.byId = null;
      await expectLater(f.read(path), throwsA(same(f.error)));
    });
  }

  test(
    'one view retiring does not cancel a concurrent read for another view',
    () async {
      final f = Fixture()..gateStep = 'paused:tt123';
      var firstCurrent = true;
      final first = f.repository.simklPaused(
        show,
        isCurrent: () => firstCurrent,
      );
      final second = f.repository.simklPaused(show, isCurrent: () => true);
      await f.entered.future;
      firstCurrent = false;
      f.release.complete();
      expect(await first, isNull);
      expect(await second, f.paused);
      expect(f.calls, ['paused:tt123', 'paused:tt123']);
    },
  );
}
