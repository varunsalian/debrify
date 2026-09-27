import 'dart:async';

import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/application/home_catalog_dependencies.dart';
import 'package:debrify/features/home/data/home_catalog_repository.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final addon = StremioAddon(
    id: 'fixture',
    name: 'Fixture',
    manifestUrl: 'https://fixture.invalid/manifest.json',
    baseUrl: 'https://fixture.invalid',
    addedAt: DateTime.utc(2026),
  );
  final catalog = StremioAddonCatalog(
    id: 'movies',
    type: 'movie',
    name: 'Movies',
  );
  StremioMeta item(String id) => StremioMeta(id: id, type: 'movie', name: id);

  test(
    'scoped row paging preserves raw offsets and borrows existing ids',
    () async {
      final offsets = <int>[];
      var reads = 0;
      final existing = ['old'];
      final repository = HomeCatalogRepository(
        readAddons: () async => [addon],
        readHides: () {
          reads++;
          return (meta) => meta.id == 'watched';
        },
        fetchPage: (actualAddon, actualCatalog, skip, raw) async {
          expect(actualAddon, same(addon));
          expect(actualCatalog, same(catalog));
          offsets.add(skip);
          if (skip == 40) {
            raw(100);
            return [item('old'), item('watched')];
          }
          if (skip == 140) {
            raw(30);
            return [item('new'), item('new')];
          }
          raw(0);
          return [];
        },
      );
      final container = ProviderContainer.test(
        overrides: [
          homeCatalogRepositoryProvider.overrideWithValue(repository),
        ],
      );
      final key = HomeCatalogSession(
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
      );
      container.listen(homeCatalogProvider(key), (_, _) {});
      final controller = container.read(homeCatalogProvider(key).notifier);
      final result = await controller.fetchRowPage(
        (addon, catalog),
        skip: 40,
        existingIds: existing,
        isCurrent: () => true,
      );
      expect(offsets, [40, 140, 170]);
      expect(result.items.map((meta) => meta.id), ['new']);
      expect(result.nextSkip, 170);
      expect(result.exhausted, isTrue);
      expect(reads, 1);
      expect(existing, ['old']);
    },
  );

  test('retiring between filtered windows prevents another request', () async {
    var active = true;
    var requests = 0;
    final response = Completer<List<StremioMeta>>();
    final repository = HomeCatalogRepository(
      readAddons: () async => [],
      readHides: () =>
          (_) => true,
      fetchPage: (_, _, _, raw) {
        requests++;
        raw(100);
        return response.future;
      },
    );
    final pending = repository.fetchRowPage(
      (addon, catalog),
      skip: 25,
      existingIds: [],
      isCurrent: () => active,
    );
    expect(requests, 1);
    active = false;
    response.complete([item('watched')]);
    final result = await pending;
    expect(requests, 1);
    expect(result.nextSkip, 125);
    expect(result.items, isEmpty);
    expect(
      result.exhausted,
      isFalse,
      reason: 'a retired callback does not report raw exhaustion',
    );
  });

  test(
    'disabled filtering keeps single-window duplicate termination',
    () async {
      var requests = 0;
      final repository = HomeCatalogRepository(
        readAddons: () async => [],
        readHides: () => null,
        fetchPage: (_, _, _, raw) async {
          requests++;
          raw(50);
          return [item('old')];
        },
      );
      final result = await repository.fetchRowPage(
        (addon, catalog),
        skip: 20,
        existingIds: ['old'],
        isCurrent: () => true,
      );
      expect(requests, 1);
      expect(result.nextSkip, 70);
      expect(result.items, isEmpty);
      expect(result.exhausted, isTrue);
    },
  );

  test(
    'fetch errors propagate without changing the caller cursor or items',
    () async {
      final failure = StateError('transient');
      final repository = HomeCatalogRepository(
        readAddons: () async => [],
        readHides: () => null,
        fetchPage: (_, _, _, _) => Future.error(failure),
      );
      final existing = ['old'];
      await expectLater(
        repository.fetchRowPage(
          (addon, catalog),
          skip: 50,
          existingIds: existing,
          isCurrent: () => true,
        ),
        throwsA(same(failure)),
      );
      expect(existing, ['old']);
    },
  );
}
