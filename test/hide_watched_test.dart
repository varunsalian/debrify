import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/filtered_catalog_pager.dart';
import 'package:debrify/services/hide_watched_prefs.dart';
import 'package:debrify/services/watched_filter.dart';

StremioMeta _meta(String id, {String type = 'movie', String? imdb}) =>
    StremioMeta(id: id, type: type, name: id, imdbId: imdb);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    HideWatchedPrefs.debugReset();
  });

  group('HideWatchedPrefs', () {
    test('defaults to off', () async {
      await HideWatchedPrefs.warmUp();
      expect(HideWatchedPrefs.enabled, isFalse);
    });

    test('setEnabled is cache-first and survives a re-warm', () async {
      await HideWatchedPrefs.warmUp();
      final pending = HideWatchedPrefs.setEnabled(true);
      expect(HideWatchedPrefs.enabled, isTrue);
      await pending;
      HideWatchedPrefs.debugReset();
      expect(HideWatchedPrefs.enabled, isFalse);
      await HideWatchedPrefs.warmUp();
      expect(HideWatchedPrefs.enabled, isTrue);
      expect(await HideWatchedPrefs.read(), isTrue);
    });
  });

  group('WatchedFilter', () {
    test('is the identity when the switch is off', () {
      final items = [_meta('a', imdb: 'tt1'), _meta('b')];
      expect(WatchedFilter.enabled, isFalse);
      expect(identical(WatchedFilter.apply(items), items), isTrue);
      expect(WatchedFilter.predicate, isNull);
      expect(WatchedFilter.hides(items.first), isFalse);
    });

    test('hides nothing before the first watched snapshot', () async {
      await HideWatchedPrefs.setEnabled(true);
      expect(WatchedFilter.enabled, isTrue);
      expect(WatchedFilter.predicate, isNotNull);
      // No snapshot has been published in this test process, so even a
      // matchable title passes through rather than flashing away later.
      expect(WatchedFilter.hides(_meta('tt1', imdb: 'tt1')), isFalse);
      expect(WatchedFilter.apply([_meta('x', imdb: 'tt9')]), hasLength(1));
    });
  });

  group('fetchFilteredPage', () {
    List<StremioMeta> window(int skip, int size, int total) => [
      for (var i = skip; i < skip + size && i < total; i++)
        _meta('tt$i', imdb: 'tt$i'),
    ];

    test('without a predicate it is one plain fetch', () async {
      final calls = <int>[];
      final page = await fetchFilteredPage((skip, onRaw) async {
        calls.add(skip);
        final w = window(skip, 10, 100);
        onRaw(w.length);
        return w;
      }, skip: 0);
      expect(calls, [0]);
      expect(page.items, hasLength(10));
      expect(page.nextSkip, 10);
      expect(page.exhausted, isFalse);
      expect(page.fetches, 1);
    });

    test('tops up across windows until minItems survive', () async {
      final calls = <int>[];
      // Even-numbered titles are "watched".
      bool hides(StremioMeta m) => int.parse(m.id.substring(2)).isEven;
      final page = await fetchFilteredPage(
        (skip, onRaw) async {
          calls.add(skip);
          final w = window(skip, 10, 100);
          onRaw(w.length);
          return w;
        },
        skip: 0,
        hides: hides,
        minItems: 12,
      );
      // 5 survivors per window → three windows to reach 12.
      expect(calls, [0, 10, 20]);
      expect(page.items.length, greaterThanOrEqualTo(12));
      expect(page.items.every((m) => !hides(m)), isTrue);
      expect(page.nextSkip, 30);
      expect(page.exhausted, isFalse);
    });

    test(
      'a raw-empty window is exhaustion; an all-filtered one is not',
      () async {
        final calls = <int>[];
        final page = await fetchFilteredPage(
          (skip, onRaw) async {
            calls.add(skip);
            final w = window(skip, 10, 25); // 25 titles total
            onRaw(w.length);
            return w;
          },
          skip: 0,
          hides: (_) => true, // everything watched
          minItems: 12,
          maxFetches: 10,
        );
        expect(page.items, isEmpty);
        expect(page.exhausted, isTrue);
        expect(calls, [0, 10, 20, 25]);
        expect(page.nextSkip, 25);
      },
    );

    test('honours maxFetches and advances skip by raw counts', () async {
      final page = await fetchFilteredPage(
        (skip, onRaw) async {
          // The addon reports a raw window bigger than what it returns
          // (some ids were invalid and dropped upstream).
          onRaw(20);
          return window(skip, 10, 1000);
        },
        skip: 40,
        hides: (_) => true,
        minItems: 5,
        maxFetches: 2,
      );
      expect(page.fetches, 2);
      expect(page.nextSkip, 80);
      expect(page.exhausted, isFalse);
    });

    test('de-duplicates against seenIds across calls', () async {
      final seen = <String>{'tt1', 'tt2'};
      final page = await fetchFilteredPage(
        (skip, onRaw) async {
          final w = window(0, 5, 5);
          onRaw(w.length);
          return w;
        },
        skip: 0,
        hides: (_) => false,
        minItems: 1,
      );
      expect(page.items.map((m) => m.id), ['tt0', 'tt1', 'tt2', 'tt3', 'tt4']);
      final again = await fetchFilteredPage(
        (skip, onRaw) async {
          final w = window(0, 5, 5);
          onRaw(w.length);
          return w;
        },
        skip: 0,
        hides: (_) => false,
        minItems: 1,
        seenIds: seen,
      );
      expect(again.items.map((m) => m.id), ['tt0', 'tt3', 'tt4']);
      expect(seen, containsAll(['tt0', 'tt3', 'tt4']));
    });
  });
}
