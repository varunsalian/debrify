import 'package:debrify/models/home_collection.dart';
import 'package:debrify/services/home_collection_rows.dart';
import 'package:debrify/services/home_list_rows.dart';
import 'package:debrify/services/simkl/simkl_list_source.dart';
import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/filtered_catalog_pager.dart';
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
  StremioMeta item(String id) => StremioMeta(id: id, type: 'movie', name: id);
  CatalogSection row(String id) => CatalogSection(
    title: id,
    addon: addon,
    catalog: StremioAddonCatalog(id: id, type: 'movie', name: id),
    items: [item('old')],
    nextSkip: 100,
  );
  HomeCatalogSession session({List<CatalogSection> rows = const []}) =>
      HomeCatalogSession(
        owner: ProfileSessionMemory.captureOwner(),
        viewIdentity: Object(),
        initialRows: rows,
      );

  late ProviderContainer container;
  late HomeCatalogController controller;
  setUp(() {
    container = ProviderContainer.test();
    final key = session();
    container.listen(homeCatalogProvider(key), (_, _) {});
    controller = container.read(homeCatalogProvider(key).notifier);
  });

  test(
    'inventory copies its container and retains row identities across reorder',
    () {
      final first = row('first');
      final second = row('second');
      final input = [first, second];
      final before = controller.current;
      controller.replaceRows(input);
      input.clear();
      expect(controller.rows, [first, second]);
      expect(() => controller.rows.clear(), throwsUnsupportedError);
      final accepted = controller.current;
      expect(accepted.rowsRevision, greaterThan(before.rowsRevision));
      controller.beginRowPage(first);
      controller.replaceRows([second, first]);
      expect(controller.rows.last, same(first));
      expect(first.loadingMore, isTrue);
      expect(accepted.rowsRevision, before.rowsRevision + 1);
    },
  );

  test(
    'paging guards, paused resume and exhaustion retain their contracts',
    () {
      final section = row('paused')..pagingPaused = true;
      controller.replaceRows([section]);
      final revision = controller.current.rowsRevision;
      expect(controller.beginRowPage(section), isFalse);
      expect(controller.current.rowsRevision, revision);
      expect(controller.beginRowPage(section, resume: true), isTrue);
      expect(controller.beginRowPage(section, resume: true), isFalse);
      controller.acceptRowPage(
        section,
        const FilteredPage(
          items: [],
          nextSkip: 500,
          exhausted: false,
          fetches: 4,
        ),
      );
      expect(section.nextSkip, 500);
      expect(section.pagingPaused, isTrue);
      expect(section.exhausted, isFalse);
      controller.finishRowPage(section);
      expect(controller.beginRowPage(section, resume: true), isTrue);
      controller.acceptRowPage(
        section,
        const FilteredPage(
          items: [],
          nextSkip: 500,
          exhausted: true,
          fetches: 1,
        ),
      );
      controller.finishRowPage(section);
      expect(section.pagingPaused, isFalse);
      expect(controller.beginRowPage(section, resume: true), isFalse);
    },
  );

  test(
    'accepted metadata precedes item publication and notifies revisions',
    () {
      final section = row('catalog');
      controller.replaceRows([section]);
      final stateBefore = controller.current;
      controller.beginRowPage(section);
      final page = FilteredPage(
        items: [item('new')],
        nextSkip: 200,
        exhausted: false,
        fetches: 1,
      );
      controller.acceptRowPage(section, page);
      expect(section.nextSkip, 200);
      expect(
        section.items.map((meta) => meta.id),
        ['old'],
        reason: 'presentation grows focus nodes before accepting new items',
      );
      final metadataRevision = controller.current.rowsRevision;
      controller.appendRowItems(section, page.items);
      expect(section.items.map((meta) => meta.id), ['old', 'new']);
      expect(controller.current.rowsRevision, greaterThan(metadataRevision));
      expect(
        stateBefore.rowsRevision,
        1,
        reason: 'published state never mutates',
      );
      controller.finishRowPage(section);
      expect(section.loadingMore, isFalse);
    },
  );

  test(
    'return snapshots detach items and loading without losing cursor or query',
    () {
      final section = CatalogSection(
        title: 'catalog',
        addon: addon,
        catalog: row('catalog').catalog,
        items: [item('old')],
        nextSkip: 400,
        pagingPaused: true,
        query: 'saved query',
      );
      controller.replaceRows([section]);
      controller.beginRowPage(section, resume: true);
      final snapshot = controller.rowsForReturn().single;
      expect(snapshot.loadingMore, isFalse);
      expect(snapshot.nextSkip, 400);
      expect(snapshot.pagingPaused, isTrue);
      expect(snapshot.query, 'saved query');
      expect(snapshot.addon, same(addon));
      expect(snapshot.items.single, same(section.items.single));
      controller.appendRowItems(section, [item('late')]);
      controller.finishRowPage(section);
      expect(snapshot.items.map((meta) => meta.id), ['old']);
    },
  );

  test(
    'return snapshots preserve synthetic row dispatch and collection tiles',
    () {
      const collection = HomeCollection(id: 'collection', title: 'Collection');
      final folders = HomeCollectionSection(collection: collection);
      final tracker = HomeListSection(
        rowId: 'simkllist:planToWatch',
        title: 'Watchlist',
        items: [item('tracked')],
        simklList: SimklSeeAllList.planToWatch,
      );
      controller.replaceRows([folders, tracker]);
      final copied = controller.rowsForReturn();
      expect(copied.first, isA<HomeCollectionSection>());
      expect(
        (copied.first as HomeCollectionSection).collection,
        same(collection),
      );
      expect(copied.first, isNot(same(folders)));
      expect(copied.last, isA<HomeListSection>());
      final copiedTracker = copied.last as HomeListSection;
      expect(copiedTracker.rowId, tracker.rowId);
      expect(copiedTracker.simklList, tracker.simklList);
      expect(copiedTracker.exhausted, isTrue);
      expect(copiedTracker.items.single, same(tracker.items.single));
      expect(copiedTracker.items, isNot(same(tracker.items)));
    },
  );

  test(
    'bootstrap seeds rows without publication and independent views isolate state',
    () {
      final saved = row('saved');
      final seed = [saved];
      final returning = session(rows: seed);
      var notifications = 0;
      container.listen(
        homeCatalogProvider(returning),
        (_, _) => notifications++,
      );
      final other = container.read(homeCatalogProvider(returning).notifier);
      seed.clear();
      expect(other.rows, [saved]);
      expect(other.current.rowsRevision, 0);
      expect(notifications, 0);
      other.beginRowPage(saved);
      expect(notifications, 1);
      expect(controller.rows, isEmpty);
      expect(controller.current.rowsRevision, 0);
    },
  );

  test(
    'provider recomputation retains accepted rows instead of replaying bootstrap',
    () {
      final seed = row('seed');
      final key = session(rows: [seed]);
      container.listen(homeCatalogProvider(key), (_, _) {});
      final owner = container.read(homeCatalogProvider(key).notifier);
      final accepted = row('accepted');
      owner.replaceRows([accepted]);
      owner.beginRowPage(accepted);
      container.invalidate(homeCatalogProvider(key));
      final rebuilt = container.read(homeCatalogProvider(key).notifier);
      expect(rebuilt, same(owner));
      expect(rebuilt.rows.single, same(accepted));
      expect(accepted.loadingMore, isTrue);
      rebuilt.finishRowPage(accepted);
      expect(accepted.loadingMore, isFalse);
      expect(rebuilt.rows, isNot(contains(seed)));
    },
  );

  test(
    'disposed owner releases pending latch without notifying or accepting data',
    () {
      final local = ProviderContainer();
      final key = session();
      var notifications = 0;
      local.listen(homeCatalogProvider(key), (_, _) => notifications++);
      final owner = local.read(homeCatalogProvider(key).notifier);
      final pending = row('pending');
      owner.replaceRows([pending]);
      owner.beginRowPage(pending);
      local.dispose();
      final before = notifications;
      owner.acceptRowPage(
        pending,
        const FilteredPage(
          items: [],
          nextSkip: 800,
          exhausted: true,
          fetches: 1,
        ),
      );
      owner.appendRowItems(pending, [item('late')]);
      owner.replaceRows([row('new')]);
      owner.finishRowPage(pending);
      expect(pending.loadingMore, isFalse);
      expect(pending.nextSkip, 100);
      expect(pending.items.map((meta) => meta.id), ['old']);
      expect(notifications, before);
    },
  );
}
