import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/home_collection_rows.dart';
import 'package:debrify/services/home_load_progress.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogSection catalog(String id) => CatalogSection(
  title: id,
  addon: HomeCollectionSection.placeholderAddon,
  catalog: StremioAddonCatalog(id: id, type: 'movie', name: id),
  items: [StremioMeta(id: id, type: 'movie', name: id)],
  nextSkip: 100,
);

HomeCollectionSection collection() => HomeCollectionSection(
  collection: const HomeCollection(
    id: 'local',
    title: 'Local',
    folders: [HomeCollectionFolder(id: 'folder', title: 'Folder', sources: [])],
  ),
);

void main() {
  testWidgets(
    'a profile session change retires accepted and queued callbacks',
    (tester) async {
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeCommitted(
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
      );
      addTearDown(ProfileRuntime.debugReset);
      final scope = ProfileRuntime.scope.value;
      final publications = <List<CatalogSection>>[];
      final progress = HomeLoadProgress(
        isCurrent: () => scope == ProfileRuntime.scope.value,
        rowId: (row) => row.catalog.id,
        onPublish: (rows, _) => publications.add(rows),
      );
      addTearDown(progress.dispose);
      progress.catalogOrder(['first', 'queued', 'late']);
      progress.catalog(catalog('first'));
      progress.catalog(catalog('queued'));
      ProfileRuntime.publish(
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 2),
      );
      await tester.pump(const Duration(milliseconds: 32));
      progress.catalog(catalog('late'));
      progress.flush();
      expect(publications, hasLength(1));
      expect(publications.single.single.catalog.id, 'first');
    },
  );
  test(
    'partial-batch recovery fills canonical slots without replacing paged rows',
    () {
      final local = collection();
      final fast = catalog('fast')..nextSkip = 200;
      final slow = catalog('slow');
      final later = catalog('later');
      final merged = mergeHomeCatalogRows(
        previous: [local, fast],
        additions: [slow, catalog('fast'), later],
        catalogOrder: ['slow', 'fast', 'later'],
        rowId: (row) => row.catalog.id,
      );
      expect(merged, [local, slow, fast, later]);
      expect(merged[2].nextSkip, 200);
    },
  );
  testWidgets('local rows and fast catalogs publish without slow siblings', (
    tester,
  ) async {
    final publications = <List<CatalogSection>>[];
    final firstFlags = <bool>[];
    final progress = HomeLoadProgress(
      isCurrent: () => true,
      rowId: (row) => row.catalog.id,
      onPublish: (rows, first) {
        publications.add(rows);
        firstFlags.add(first);
      },
    );
    addTearDown(progress.dispose);
    final local = collection();
    progress.collections([local]);
    expect(publications.single, [local]);
    progress.catalogOrder(['slow', 'fast']);
    final fast = catalog('fast');
    progress.catalog(fast);
    await tester.pump(const Duration(milliseconds: 32));
    expect(publications.last, [local, fast]);
    final slow = catalog('slow');
    progress.catalog(slow);
    await tester.pump(const Duration(milliseconds: 32));
    expect(publications.last, [local, slow, fast]);
    expect(firstFlags, [true, false, false]);
    progress.flush();
    expect(publications, hasLength(3));
  });

  for (final transition in [
    'supersede',
    'profile switch',
    'logout',
    'dispose',
  ]) {
    testWidgets('$transition rejects queued and late publications', (
      tester,
    ) async {
      var current = true;
      final publications = <List<CatalogSection>>[];
      final progress = HomeLoadProgress(
        isCurrent: () => current,
        rowId: (row) => row.catalog.id,
        onPublish: (rows, _) => publications.add(rows),
      );
      addTearDown(progress.dispose);
      progress.catalogOrder(['one', 'two', 'late']);
      progress.catalog(catalog('one'));
      progress.catalog(catalog('two'));
      if (transition == 'dispose') {
        progress.dispose();
      } else {
        current = false;
      }
      await tester.pump(const Duration(milliseconds: 100));
      progress.catalog(catalog('late'));
      progress.flush(allowEmpty: true);
      expect(publications, hasLength(1));
      expect(publications.single.single.catalog.id, 'one');
    });
  }

  testWidgets('late arrivals retain horizontally paginated row objects', (
    tester,
  ) async {
    late List<CatalogSection> visible;
    final progress = HomeLoadProgress(
      isCurrent: () => true,
      rowId: (row) => row.catalog.id,
      onPublish: (rows, _) => visible = rows,
    );
    addTearDown(progress.dispose);
    progress.catalogOrder(['first', 'second']);
    final first = catalog('first');
    progress.catalog(first);
    first.items.add(
      const StremioMeta(id: 'page2', type: 'movie', name: 'Page 2'),
    );
    first.nextSkip = 200;
    progress.catalog(catalog('second'));
    await tester.pump(const Duration(milliseconds: 32));
    expect(visible.first, same(first));
    expect(visible.first.nextSkip, 200);
    expect(visible.first.items.last.id, 'page2');
  });

  testWidgets('empty final results publish only when loading finishes', (
    tester,
  ) async {
    final publications = <List<CatalogSection>>[];
    final progress = HomeLoadProgress(
      isCurrent: () => true,
      rowId: (row) => row.catalog.id,
      onPublish: (rows, _) => publications.add(rows),
    );
    addTearDown(progress.dispose);
    progress.collections([]);
    progress.lists([]);
    expect(publications, isEmpty);
    progress.flush(allowEmpty: true);
    expect(publications.single, isEmpty);
  });
}
