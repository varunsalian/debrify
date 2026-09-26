import 'dart:async';

import 'package:debrify/features/home/data/home_catalog_repository.dart';
import 'package:debrify/features/home/models/home_catalog_plan.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:flutter_test/flutter_test.dart';

final source = StremioAddon(
  id: 'fixture',
  name: 'Fixture',
  manifestUrl: 'https://fixture.invalid/manifest.json',
  baseUrl: 'https://fixture.invalid',
  addedAt: DateTime.utc(2026),
);
HomeCatalogReference reference(String id) =>
    (source, StremioAddonCatalog(id: id, type: 'movie', name: id));
StremioMeta item(String id) => StremioMeta(id: id, type: 'movie', name: id);

HomeCatalogRepository repository(
  Future<List<StremioMeta>> Function(
    StremioAddon,
    StremioAddonCatalog,
    int,
    void Function(int),
  )
  fetch, {
  bool Function(StremioMeta)? Function()? readHides,
}) => HomeCatalogRepository(
  readAddons: () async => [source],
  fetchPage: fetch,
  readHides: readHides ?? () => null,
);

void main() {
  test(
    'rows load concurrently, publish on completion and return in source order',
    () async {
      final a = Completer<List<StremioMeta>>();
      final b = Completer<List<StremioMeta>>();
      final secondPublished = Completer<void>();
      final started = <String>[];
      final published = <String>[];
      final subject = repository((addon, catalog, skip, raw) {
        expect(addon, same(source));
        expect(skip, 0);
        started.add(catalog.id);
        raw(1);
        return catalog.id == 'a' ? a.future : b.future;
      });
      final pending = subject.fetchBatch(
        [reference('a'), reference('b')],
        isCurrent: () => true,
        onSection: (row) {
          published.add(row.catalog.id);
          if (row.catalog.id == 'b') secondPublished.complete();
        },
      );
      expect(started, ['a', 'b']);
      b.complete([item('second')]);
      await secondPublished.future;
      expect(published, ['b']);
      a.complete([item('first')]);
      final rows = await pending;
      expect(published, ['b', 'a']);
      expect(rows.map((r) => r.catalog.id), ['a', 'b']);
      expect(rows.map((r) => r.nextSkip), [1, 1]);
    },
  );

  test(
    'failed and exhausted catalogs do not hide successful neighbors',
    () async {
      final subject = repository((_, catalog, __, ___) async {
        if (catalog.id == 'bad') throw StateError('fixture');
        return catalog.id == 'empty' ? [] : [item(catalog.id)];
      });
      final published = <String>[];
      final rows = await subject.fetchBatch(
        [
          reference('before'),
          reference('bad'),
          reference('empty'),
          reference('after'),
        ],
        isCurrent: () => true,
        onSection: (r) => published.add(r.catalog.id),
      );
      expect(rows.map((r) => r.catalog.id), ['before', 'after']);
      expect(published, ['before', 'after']);
    },
  );

  test(
    'unchanged cached rows retain identity and cursor without requests',
    () async {
      final ref = reference('cached');
      final previous = CatalogSection(
        title: 'Cached',
        addon: ref.$1,
        catalog: ref.$2,
        items: [item('old')],
        nextSkip: 120,
        exhausted: true,
      );
      final subject = repository(
        (_, __, ___, ____) => throw StateError('Unexpected fetch'),
      );
      final published = <CatalogSection>[];
      final rows = await subject.fetchBatch(
        [ref],
        previousRows: {homeCatalogRowId(ref): previous},
        isCurrent: () => true,
        onSection: published.add,
      );
      expect(rows.single, same(previous));
      expect(published.single, same(previous));
      expect(rows.single.nextSkip, 120);
      expect(rows.single.exhausted, isTrue);
      rows.add(previous);
      expect(
        rows,
        hasLength(2),
        reason: 'vertical refresh callers own their result list',
      );
    },
  );

  test('retirement drops a pending row before publication', () async {
    var active = true;
    final response = Completer<List<StremioMeta>>();
    final subject = repository((_, __, ___, ____) => response.future);
    final published = <CatalogSection>[];
    final pending = subject.fetchBatch(
      [reference('late')],
      isCurrent: () => active,
      onSection: published.add,
    );
    active = false;
    response.complete([item('late')]);
    expect(await pending, isEmpty);
    expect(published, isEmpty);
  });

  test(
    'retired cached and uncached rows start no fetch or publication',
    () async {
      final ref = reference('cached');
      final previous = CatalogSection(
        title: 'Cached',
        addon: ref.$1,
        catalog: ref.$2,
        items: [item('old')],
      );
      final subject = repository(
        (_, __, ___, ____) => throw StateError('Unexpected fetch'),
      );
      final published = <CatalogSection>[];
      expect(
        await subject.fetchBatch(
          [ref, reference('new')],
          previousRows: {homeCatalogRowId(ref): previous},
          isCurrent: () => false,
          onSection: published.add,
        ),
        isEmpty,
      );
      expect(published, isEmpty);
    },
  );

  test('filtered empty windows retain raw cursor and resumable row', () async {
    final skips = <int>[];
    final subject = repository(
      (_, __, skip, raw) async {
        skips.add(skip);
        raw(5);
        return [item('$skip')];
      },
      readHides: () =>
          (_) => true,
    );
    final rows = await subject.fetchBatch([
      reference('watched'),
    ], isCurrent: () => true);
    expect(skips, [0, 5, 10, 15]);
    expect(rows.single.items, isEmpty);
    expect(rows.single.nextSkip, 20);
    expect(rows.single.pagingPaused, isTrue);
    expect(rows.single.exhausted, isFalse);
  });

  test(
    'retirement between filtered windows prevents another request',
    () async {
      var active = true;
      var calls = 0;
      final subject = repository(
        (_, __, ___, raw) async {
          calls++;
          raw(1);
          active = false;
          return [item('hidden')];
        },
        readHides: () =>
            (_) => true,
      );
      expect(
        await subject.fetchBatch([
          reference('watched'),
        ], isCurrent: () => active),
        isEmpty,
      );
      expect(calls, 1);
    },
  );

  test(
    'filter is read per row and callback failure remains isolated',
    () async {
      var filtering = false;
      var filterReads = 0;
      final subject = repository(
        (_, catalog, skip, raw) async {
          filtering = true;
          raw(1);
          return [item('${catalog.id}-$skip')];
        },
        readHides: () {
          filterReads++;
          return filtering ? (_) => true : null;
        },
      );
      final observed = <CatalogSection>[];
      final rows = await subject.fetchBatch(
        [reference('first'), reference('second')],
        isCurrent: () => true,
        onSection: (row) {
          observed.add(row);
          if (row.catalog.id == 'first') {
            throw StateError('Publication fixture');
          }
        },
      );
      expect(filterReads, 2);
      expect(observed.first.items, hasLength(1));
      expect(rows.single.catalog.id, 'second');
      expect(rows.single.items, isEmpty);
      expect(rows.single.pagingPaused, isTrue);
    },
  );
}
