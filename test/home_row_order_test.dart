import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:debrify/services/home_row_order.dart';
import 'package:debrify/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('saved order round-trips, deduplicates, and clears', () async {
    await StorageService.setHomeRowOrder([
      'fav:playlist',
      'cw:movies',
      'fav:playlist',
      '',
    ]);
    expect(await StorageService.getHomeRowOrder(), [
      'fav:playlist',
      'cw:movies',
    ]);

    await StorageService.setHomeRowOrder(const []);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('home_row_order_v1'), isNull);
  });

  test(
    'malformed order is tolerated and invalid entries are ignored',
    () async {
      SharedPreferences.setMockInitialValues({
        'home_row_order_v1': jsonEncode([
          'cw:series',
          4,
          '',
          'cw:series',
          'fav:iptv',
        ]),
      });
      expect(await StorageService.getHomeRowOrder(), ['cw:series', 'fav:iptv']);
    },
  );

  test('apply keeps saved missing ids and appends new rows stably', () {
    final reconciled = HomeRowOrder.reconcile(
      const ['missing:addon', 'b', 'a'],
      const ['a', 'b', 'c', 'd'],
    );
    expect(reconciled, ['missing:addon', 'b', 'a', 'c', 'd']);
    expect(
      HomeRowOrder.apply(const ['a', 'b', 'c', 'd'], reconciled, (id) => id),
      ['b', 'a', 'c', 'd'],
    );
  });

  test('new tracker family inherits the slot after its anchor family', () {
    final seeded = HomeRowOrder.insertMissingAfter(
      const [
        'cw:movies',
        'simkl:movies',
        'simkl:shows',
        'fav:playlist',
        'catalog:a',
      ],
      additions: const ['mdblist:movies', 'mdblist:shows'],
      anchors: const ['simkl:movies', 'simkl:shows'],
    );

    expect(seeded, [
      'cw:movies',
      'simkl:movies',
      'simkl:shows',
      'mdblist:movies',
      'mdblist:shows',
      'fav:playlist',
      'catalog:a',
    ]);
  });

  test('explicitly arranged tracker rows are not moved', () {
    final seeded = HomeRowOrder.insertMissingAfter(
      const [
        'mdblist:movies',
        'cw:movies',
        'simkl:movies',
        'simkl:shows',
        'mdblist:shows',
      ],
      additions: const ['mdblist:movies', 'mdblist:shows'],
      anchors: const ['simkl:movies', 'simkl:shows'],
    );

    expect(seeded, [
      'mdblist:movies',
      'cw:movies',
      'simkl:movies',
      'simkl:shows',
      'mdblist:shows',
    ]);
  });

  test('empty saved order remains canonical', () {
    expect(
      HomeRowOrder.insertMissingAfter(
        const [],
        additions: const ['mdblist:movies', 'mdblist:shows'],
        anchors: const ['simkl:movies', 'simkl:shows'],
      ),
      isEmpty,
    );
  });

  test('temporary rows stay after their canonical leading family', () {
    final canonical = HomeRowOrder.insertAfterLeadingRun(
      const ['cw:movies', 'simkl:movies', 'fav:playlist', 'catalog:a'],
      const ['trakt:movies', 'trakt:shows'],
      (id) => id.startsWith('cw:') || id.startsWith('simkl:'),
    );
    expect(canonical, [
      'cw:movies',
      'simkl:movies',
      'trakt:movies',
      'trakt:shows',
      'fav:playlist',
      'catalog:a',
    ]);
  });

  test('one global order projects consistently across layout families', () {
    const canonical = [
      'cw:movies',
      'fav:playlist',
      'iptvlist:sports',
      'traktlist:watchlist',
      'addon:movie:popular',
    ];
    const saved = [
      'addon:movie:popular',
      'cw:movies',
      'traktlist:watchlist',
      'fav:playlist',
      'iptvlist:sports',
    ];
    final ordered = HomeRowOrder.apply(canonical, saved, (id) => id);

    // Classic, Spotlight and the stage layouts consume the same projection.
    expect(ordered, saved);
    // Tonight pins CW into its queue and preserves the remaining projection.
    expect(ordered.where((id) => !id.startsWith('cw:')), [
      'addon:movie:popular',
      'traktlist:watchlist',
      'fav:playlist',
      'iptvlist:sports',
    ]);
  });
}
