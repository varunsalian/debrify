import 'dart:async';

import 'package:debrify/features/home/data/home_catalog_preferences_repository.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('readers run sequentially and preserve configured ordering', () async {
    final calls = <String>[];
    final disabled = Completer<Set<String>>();
    final extras = Completer<List<HomeExtraRow>>();
    final order = Completer<List<String>>();
    final hero = Completer<HomeHeroSource>();
    final repository = HomeCatalogPreferencesRepository(
      readDisabled: () {
        calls.add('disabled');
        return disabled.future;
      },
      readExtras: () {
        calls.add('extras');
        return extras.future;
      },
      readRowOrder: () {
        calls.add('order');
        return order.future;
      },
      readHeroSource: () {
        calls.add('hero');
        return hero.future;
      },
    );
    final pending = repository.read();
    expect(calls, ['disabled']);
    disabled.complete({'hidden'});
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['disabled', 'extras']);
    extras.complete([
      (id: 'second', title: 'Renamed'),
      (id: 'first', title: ''),
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['disabled', 'extras', 'order']);
    order.complete(['b', 'a']);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['disabled', 'extras', 'order', 'hero']);
    hero.complete((mode: HomeHeroSourceMode.custom, ids: ['hero-b', 'hero-a']));
    final value = await pending;
    expect(value.disabled, {'hidden'});
    expect(value.extras.map((r) => r.id), ['second', 'first']);
    expect(value.extras.first.title, 'Renamed');
    expect(value.rowOrder, ['b', 'a']);
    expect(value.heroSource.mode, HomeHeroSourceMode.custom);
    expect(value.heroSource.ids, ['hero-b', 'hero-a']);
  });

  for (final failing in ['disabled', 'extras', 'order', 'hero']) {
    test(
      'failed $failing read propagates and does not start later readers',
      () async {
        final calls = <String>[];
        final error = StateError('fixture');
        Future<T> read<T>(String name, T result) async {
          calls.add(name);
          if (name == failing) throw error;
          return result;
        }

        final repository = HomeCatalogPreferencesRepository(
          readDisabled: () => read('disabled', <String>{}),
          readExtras: () => read('extras', <HomeExtraRow>[]),
          readRowOrder: () => read('order', <String>[]),
          readHeroSource: () =>
              read('hero', (mode: HomeHeroSourceMode.random, ids: <String>[])),
        );
        await expectLater(repository.read(), throwsA(same(error)));
        final all = ['disabled', 'extras', 'order', 'hero'];
        expect(calls, all.take(all.indexOf(failing) + 1));
      },
    );
  }

  test(
    'published settings are immutable snapshots and each read is fresh',
    () async {
      final disabled = {'hidden'};
      final extras = <HomeExtraRow>[(id: 'row', title: 'Original')];
      final order = ['first'];
      final heroIds = ['hero'];
      final repository = HomeCatalogPreferencesRepository(
        readDisabled: () async => disabled,
        readExtras: () async => extras,
        readRowOrder: () async => order,
        readHeroSource: () async =>
            (mode: HomeHeroSourceMode.auto, ids: heroIds),
      );
      final original = await repository.read();
      disabled.clear();
      extras[0] = (id: 'row', title: 'Renamed');
      order.add('second');
      heroIds.clear();
      expect(original.disabled, {'hidden'});
      expect(original.extras.single.title, 'Original');
      expect(original.rowOrder, ['first']);
      expect(original.heroSource.ids, ['hero']);
      expect(() => original.disabled.clear(), throwsUnsupportedError);
      expect(() => original.extras.clear(), throwsUnsupportedError);
      expect(() => original.rowOrder.clear(), throwsUnsupportedError);
      expect(() => original.heroSource.ids.clear(), throwsUnsupportedError);
      final refreshed = await repository.read();
      expect(refreshed.disabled, isEmpty);
      expect(refreshed.extras.single.title, 'Renamed');
      expect(refreshed.rowOrder, ['first', 'second']);
      expect(refreshed.heroSource.ids, isEmpty);
    },
  );

  test('overlapping reads retain independent partial results', () async {
    final first = Completer<Set<String>>();
    var reads = 0;
    final repository = HomeCatalogPreferencesRepository(
      readDisabled: () =>
          ++reads == 1 ? first.future : Future.value({'second'}),
      readExtras: () async => [],
      readRowOrder: () async => [],
      readHeroSource: () async =>
          (mode: HomeHeroSourceMode.random, ids: <String>[]),
    );
    final earlier = repository.read();
    final later = await repository.read();
    first.complete({'first'});
    expect((await earlier).disabled, {'first'});
    expect(later.disabled, {'second'});
    expect(reads, 2);
  });
}
