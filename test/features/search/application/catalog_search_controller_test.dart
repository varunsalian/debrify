import 'dart:async';

import 'package:debrify/features/search/application/catalog_search_controller.dart';
import 'package:debrify/features/search/application/catalog_search_dependencies.dart';
import 'package:debrify/features/search/models/catalog_search_row.dart';
import 'package:debrify/features/search/models/catalog_search_state.dart';
import 'package:debrify/features/search/models/search_session.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_catalog_search_repository.dart';

StremioAddon addon(String id, {int count = 2}) => StremioAddon(
  id: id,
  name: id,
  baseUrl: 'https://$id.invalid',
  manifestUrl: 'https://$id.invalid/manifest.json',
  catalogs: [
    for (var i = 0; i < count; i++)
      StremioAddonCatalog(
        id: '$i',
        type: 'movie',
        name: '$i',
        extraSupported: const ['search'],
      ),
    const StremioAddonCatalog(id: 'browse', type: 'movie', name: 'Browse'),
  ],
);

CatalogSearchRow row(StremioAddon a, StremioAddonCatalog c, String q) =>
    CatalogSearchRow(
      addon: a,
      catalog: c,
      items: [StremioMeta(id: 'catalog-${c.id}', type: 'movie', name: q)],
      query: q,
      nextSkip: 17,
    );

void main() {
  late ProviderContainer container;
  late FakeCatalogSearchRepository repository;
  late SearchSession session;
  late CatalogSearchController controller;
  late ProviderSubscription<CatalogSearchState> subscription;
  CatalogSearchState current() => subscription.read();
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  setUp(() {
    repository = FakeCatalogSearchRepository()..addons = [addon('one')];
    repository.fetch = (a, c, q) async => row(a, c, q);
    session = SearchSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container = ProviderContainer.test(
      overrides: [
        catalogSearchRepositoryProvider.overrideWith((ref, key) => repository),
      ],
    );
    subscription = container.listen(catalogSearchProvider(session), (_, _) {});
    controller = container.read(catalogSearchProvider(session).notifier);
  });

  test('construction does not dispatch search or preferences writes', () {
    expect(current().query, '');
    expect(repository.requests, isEmpty);
    expect(repository.writes, isEmpty);
  });

  for (final batch in [false, true]) {
    test('completion ordering and publication: batch=$batch', () async {
      final first = Completer<CatalogSearchRow?>();
      final second = Completer<CatalogSearchRow?>();
      repository.fetch = (a, c, q) =>
          c.id == '0' ? first.future : second.future;
      final action = controller.search('movies', batchResults: batch);
      await settle();
      final a = repository.addons.first;
      second.complete(row(a, a.catalogs[1], 'movies'));
      await settle();
      expect(current().rows.map((r) => r.catalog.id), batch ? [] : ['1']);
      expect(current().searching, isTrue);
      first.complete(row(a, a.catalogs[0], 'movies'));
      expect(await action, CatalogSearchCompletion.accepted);
      expect(
        current().rows.map((r) => r.catalog.id),
        batch ? ['0', '1'] : ['1', '0'],
      );
      expect(current().searching, isFalse);
      expect(current().rows.first.query, 'movies');
      expect(current().rows.first.nextSkip, 17);
      expect(() => current().rows.clear(), throwsUnsupportedError);
      expect(() => current().rows.first.items.clear(), throwsUnsupportedError);
    });

    test(
      'an old result or failure cannot clear new loading: batch=$batch',
      () async {
        final old = Completer<CatalogSearchRow?>();
        final next = Completer<CatalogSearchRow?>();
        repository.fetch = (a, c, q) => q == 'old' ? old.future : next.future;
        final oldAction = controller.search('old', batchResults: batch);
        await settle();
        final newAction = controller.search('new', batchResults: batch);
        await settle();
        old.completeError(StateError('old failed'));
        expect(await oldAction, CatalogSearchCompletion.stale);
        expect(current().query, 'new');
        expect(current().searching, isTrue);
        expect(current().failures, 0);
        next.complete(null);
        expect(await newAction, CatalogSearchCompletion.accepted);
        expect(current().rows, isEmpty);
        expect(current().searching, isFalse);
      },
    );
  }

  test('disabled addons and browse-only catalogs issue no requests', () async {
    repository.addons = [addon('one'), addon('two')];
    repository.disabled = {'one'};
    await controller.search('movies', batchResults: true);
    expect(repository.requests.map((r) => '${r.addon}:${r.catalog}'), [
      'two:0',
      'two:1',
    ]);
  });

  test(
    'fan-out stays bounded at ten while retaining all catalog order',
    () async {
      repository.addons = [addon('many', count: 23)];
      final pending = <String, Completer<CatalogSearchRow?>>{};
      repository.fetch = (a, c, q) => (pending[c.id] = Completer()).future;
      final action = controller.search('movies', batchResults: true);
      await settle();
      expect(pending.length, 10);
      for (var start = 0; start < 23; start += 10) {
        final entries = pending.entries.toList();
        pending.clear();
        for (final entry in entries) {
          final a = repository.addons.first;
          entry.value.complete(
            row(a, a.catalogs[int.parse(entry.key)], 'movies'),
          );
        }
        await settle();
        expect(pending.length, lessThanOrEqualTo(10));
      }
      expect(await action, CatalogSearchCompletion.accepted);
      expect(repository.requests.length, 23);
      expect(
        current().rows.map((r) => r.catalog.id),
        List.generate(23, (i) => '$i'),
      );
    },
  );

  test('partial failures retain successful rows without retry', () async {
    repository.fetch = (a, c, q) async {
      if (c.id == '0') throw StateError('source unavailable');
      return row(a, c, q);
    };
    await controller.search('movies', batchResults: true);
    expect(current().rows.map((r) => r.catalog.id), ['1']);
    expect(current().failures, 1);
    await container.pump();
    expect(repository.requests.length, 2);
  });

  test(
    'total source failure is distinct from empty successful catalogs',
    () async {
      repository.fetch = (a, c, q) async =>
          throw StateError('source unavailable');
      await controller.search('movies', batchResults: false);
      expect(current().failures, 2);
      expect(current().rows, isEmpty);
      controller.clear();
      expect(current().query, isEmpty);
      expect(current().failures, 2); // Existing Home restore contract.
      repository.fetch = (a, c, q) async => null;
      await controller.search('next', batchResults: false);
      expect(current().failures, 0);
      expect(current().rows, isEmpty);
    },
  );

  test(
    'preferences failure finishes once without dispatching catalog requests',
    () async {
      repository.read = () async => throw StateError('unavailable');
      expect(
        await controller.search('movies', batchResults: true),
        CatalogSearchCompletion.failed,
      );
      expect(current().searching, isFalse);
      expect(repository.requests, isEmpty);
      await container.pump();
      expect(repository.requests, isEmpty);
    },
  );

  for (final cancel in ['clear', 'profile', 'dispose']) {
    test('$cancel rejects late results', () async {
      final pending = Completer<CatalogSearchRow?>();
      repository.fetch = (a, c, q) => pending.future;
      final action = controller.search('movies', batchResults: true);
      await settle();
      if (cancel == 'clear') controller.clear();
      if (cancel == 'profile') repository.isCurrent = false;
      if (cancel == 'dispose') {
        subscription.close();
        await container.pump();
        expect(container.exists(catalogSearchProvider(session)), isFalse);
      }
      pending.complete(
        row(
          repository.addons.first,
          repository.addons.first.catalogs.first,
          'movies',
        ),
      );
      expect(await action, CatalogSearchCompletion.stale);
      if (cancel == 'clear') expect(current().rows, isEmpty);
    });
  }

  test('two mounted views retain independent catalog states', () async {
    final other = SearchSession(owner: session.owner, viewIdentity: Object());
    final otherSubscription = container.listen(
      catalogSearchProvider(other),
      (_, _) {},
    );
    await controller.search('first', batchResults: true);
    await container
        .read(catalogSearchProvider(other).notifier)
        .search('second', batchResults: false);
    expect(current().query, 'first');
    expect(otherSubscription.read().query, 'second');
  });
}
