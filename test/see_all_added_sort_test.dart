import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/simkl/simkl_item_transformer.dart';
import 'package:debrify/services/trakt/trakt_item_transformer.dart';
import 'package:debrify/widgets/see_all/see_all_sort.dart';
import 'package:flutter_test/flutter_test.dart';

StremioMeta _meta(String name, int? added) =>
    StremioMeta(id: name, type: 'movie', name: name, addedAtMs: added);

void main() {
  group('byAddedDate', () {
    test('newest first, oldest last', () {
      final list = [_meta('b', 200), _meta('a', 100), _meta('c', 300)];
      list.sort(byAddedDate(newest: true));
      expect(list.map((m) => m.name), ['c', 'b', 'a']);

      list.sort(byAddedDate(newest: false));
      expect(list.map((m) => m.name), ['a', 'b', 'c']);
    });

    test('undated items sink to the end in BOTH directions', () {
      // The trap: treating a missing date as 0 would make "oldest" open on
      // every item the tracker never dated.
      final list = [_meta('dated', 100), _meta('undated', null)];
      list.sort(byAddedDate(newest: true));
      expect(list.last.name, 'undated');

      list.sort(byAddedDate(newest: false));
      expect(list.last.name, 'undated');
    });

    test('same-second ties fall back to A-Z so the order is stable', () {
      // Bulk-imported lists routinely share a timestamp to the second.
      final list = [_meta('zulu', 100), _meta('alpha', 100)];
      list.sort(byAddedDate(newest: true));
      expect(list.map((m) => m.name), ['alpha', 'zulu']);
    });

    test('undated ties also fall back to A-Z', () {
      final list = [_meta('zulu', null), _meta('alpha', null)];
      list.sort(byAddedDate(newest: true));
      expect(list.map((m) => m.name), ['alpha', 'zulu']);
    });
  });

  group('settleDeferredSort', () {
    // Mirrors the screens' private sort enum.
    const natural = 'natural';
    const addedNewest = 'addedNewest';
    const az = 'az';

    test('holds the remembered sort while the list has no dates', () {
      // Discover opens Trakt on Continue Watching / Simkl on Trending — the
      // stored pick must survive that first undated list.
      final r = settleDeferredSort(
        deferred: addedNewest,
        current: natural,
        natural: natural,
        listHasDates: false,
      );
      expect(r.sort, natural);
      expect(r.deferred, addedNewest, reason: 'still waiting for a dated list');
    });

    test('claims it once dated rows arrive', () {
      // The list switch that got here reset the sort to natural; that reset is
      // exactly what the remembered pick is allowed to overwrite.
      final r = settleDeferredSort(
        deferred: addedNewest,
        current: natural,
        natural: natural,
        listHasDates: true,
      );
      expect(r.sort, addedNewest);
      expect(r.deferred, isNull, reason: 'restored once, not on every list');
    });

    test('never overrides a sort the user picked in the meantime', () {
      final r = settleDeferredSort(
        deferred: addedNewest,
        current: az,
        natural: natural,
        listHasDates: true,
      );
      expect(r.sort, az);
      expect(r.deferred, isNull);
    });

    test('is a no-op when nothing was deferred', () {
      final r = settleDeferredSort(
        deferred: null,
        current: az,
        natural: natural,
        listHasDates: true,
      );
      expect(r.sort, az);
      expect(r.deferred, isNull);
    });
  });

  group('hasAddedDates', () {
    test('false for catalogue rows, true once anything carries a date', () {
      expect(hasAddedDates([_meta('a', null), _meta('b', null)]), isFalse);
      expect(hasAddedDates([_meta('a', null), _meta('b', 1)]), isTrue);
      expect(hasAddedDates(const []), isFalse);
    });
  });

  group('row date extraction', () {
    test('Trakt reads listed_at off a watchlist row', () {
      final ms = TraktItemTransformer.rowDateMs(<String, dynamic>{
        'listed_at': '2026-07-27T01:07:00Z',
        'movie': <String, dynamic>{'title': 'x'},
      });
      expect(
        ms,
        DateTime.parse('2026-07-27T01:07:00Z').millisecondsSinceEpoch,
      );
    });

    test('a History episode row keeps its date when retyped to the show', () {
      // History show rows arrive episode-shaped: the episode carries no imdb,
      // so the list source retypes the row to 'show'. Stripping it down to
      // {'show': ...} would drop watched_at and leave every show in History
      // undated while the movies beside them kept theirs.
      final row = <String, dynamic>{
        'watched_at': '2026-07-27T01:07:00Z',
        'type': 'episode',
        'episode': <String, dynamic>{
          'title': 'ep',
          'ids': <String, dynamic>{'imdb': null},
        },
        'show': <String, dynamic>{
          'title': 'Show',
          'ids': <String, dynamic>{'imdb': 'tt1'},
        },
      };
      final meta = TraktItemTransformer.transformItem(
        {...row, 'type': 'show'},
        inferredType: 'show',
      );
      expect(meta, isNotNull);
      expect(meta!.name, 'Show');
      expect(
        meta.addedAtMs,
        DateTime.parse('2026-07-27T01:07:00Z').millisecondsSinceEpoch,
      );
    });

    test('Trakt returns null for a plain content row (trending/popular)', () {
      final ms = TraktItemTransformer.rowDateMs(<String, dynamic>{
        'title': 'x',
        'ids': <String, dynamic>{'imdb': 'tt1'},
      });
      expect(ms, isNull);
    });

    test('Simkl prefers added_to_watchlist_at over last_watched_at', () {
      // Watching a title must not move it in a "date added" order.
      final ms = SimklItemTransformer.rowDateMs(<String, dynamic>{
        'added_to_watchlist_at': '2010-01-20T20:09:04Z',
        'last_watched_at': '2014-11-06T22:05:52Z',
      });
      expect(
        ms,
        DateTime.parse('2010-01-20T20:09:04Z').millisecondsSinceEpoch,
      );
    });

    test('Simkl returns null for a flat catalogue row', () {
      final ms = SimklItemTransformer.rowDateMs(<String, dynamic>{
        'title': 'x',
        'ids': <String, dynamic>{'imdb': 'tt1'},
      });
      expect(ms, isNull);
    });
  });
}
