import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/filtered_catalog_pager.dart';

void main() {
  test(
    'switch off ends failed fetches without a retryable paused page',
    () async {
      var calls = 0;
      final page = await fetchFilteredPage((skip, raw) async {
        calls++;
        return [];
      }, skip: 40);
      expect(page.exhausted, isTrue);
      expect(page.nextSkip, 40);
      expect(calls, 1);
    },
  );

  test('switch off terminates addons repeating already seen titles', () async {
    final page = await fetchFilteredPage(
      (skip, raw) async {
        raw(20);
        return [StremioMeta(id: 'tt1', type: 'movie', name: 'One')];
      },
      skip: 20,
      seenIds: {'tt1'},
    );
    expect(page.items, isEmpty);
    expect(page.exhausted, isTrue);
    expect(page.nextSkip, 40);
    expect(page.fetches, 1);
  });

  test(
    'transport failure retains its cursor without declaring exhaustion',
    () async {
      final page = await fetchFilteredPage(
        (skip, raw) async => [],
        skip: 40,
        hides: (_) => false,
      );
      expect(page.items, isEmpty);
      expect(page.nextSkip, 40);
      expect(page.exhausted, isFalse);
      expect(page.fetches, 1);
    },
  );

  test('initial top-up deduplicates addons that ignore skip', () async {
    final page = await fetchFilteredPage(
      (skip, onRaw) async {
        onRaw(2);
        return [
          StremioMeta(id: 'tt1', type: 'movie', name: 'One'),
          StremioMeta(id: 'tt2', type: 'movie', name: 'Two'),
        ];
      },
      skip: 0,
      hides: (m) => m.id == 'tt2',
    );
    expect(page.items.map((m) => m.id).toList(), ['tt1']);
  });

  test('raw nonempty window with no valid metas is not exhaustion', () async {
    final page = await fetchFilteredPage(
      (skip, onRaw) async {
        onRaw(10);
        if (skip == 0) return <StremioMeta>[];
        return [StremioMeta(id: 'tt1', type: 'movie', name: 'One')];
      },
      skip: 0,
      hides: (_) => false,
      minItems: 1,
    );
    expect(page.items.map((m) => m.id).toList(), ['tt1']);
    expect(page.exhausted, isFalse);
  });

  test(
    'four watched windows still leave a later unwatched page reachable',
    () async {
      Future<List<StremioMeta>> fetch(
        int skip,
        void Function(int) onRaw,
      ) async {
        onRaw(10);
        return [
          for (var i = skip; i < skip + 10; i++)
            StremioMeta(id: 'tt$i', type: 'movie', name: '$i'),
        ];
      }

      final page = await fetchFilteredPage(
        fetch,
        skip: 0,
        hides: (m) => int.parse(m.id.substring(2)) < 40,
      );
      expect(page.items, isEmpty);
      expect(page.exhausted, isFalse);
      expect(page.nextSkip, 40);
      final next = await fetchFilteredPage(
        fetch,
        skip: page.nextSkip,
        hides: (m) => int.parse(m.id.substring(2)) < 40,
      );
      expect(next.items, isNotEmpty);
    },
  );
}
