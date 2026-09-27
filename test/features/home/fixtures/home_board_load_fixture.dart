import 'dart:async';

import 'package:debrify/features/home/application/home_board_load.dart';
import 'package:debrify/features/home/application/home_catalog_controller.dart';
import 'package:debrify/features/home/application/home_catalog_dependencies.dart';
import 'package:debrify/features/home/data/home_board_services.dart';
import 'package:debrify/features/home/data/home_catalog_preferences_repository.dart';
import 'package:debrify/features/home/data/home_catalog_repository.dart';
import 'package:debrify/features/home/data/home_collections_repository.dart';
import 'package:debrify/features/home/models/home_catalog_session.dart';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/home_list_rows.dart';
import 'package:debrify/services/home_load_progress.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/trakt/trakt_list_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

StremioMeta boardItem(String id) =>
    StremioMeta(id: id, type: 'movie', name: id);
HomeListSection trackerRow(String id) => HomeListSection(
  rowId: id,
  title: id,
  items: [boardItem(id)],
  traktChoice: const TraktListChoice.builtin(TraktSeeAllList.watchlist),
);

class BoardLoadFixture {
  BoardLoadFixture() {
    container = ProviderContainer(
      overrides: [
        homeCatalogRepositoryProvider.overrideWithValue(
          HomeCatalogRepository(
            readAddons: () {
              trace.add('addons');
              return readAddons();
            },
            readHides: () => null,
            fetchPage: (_, row, _, raw) async {
              trace.add('fetch:${row.id}');
              final items = await fetch(row.id);
              raw(items.length);
              return items;
            },
          ),
        ),
      ],
    );
    final session = HomeCatalogSession(
      owner: ProfileSessionMemory.captureOwner(),
      viewIdentity: Object(),
    );
    container.listen(homeCatalogProvider(session), (_, _) {});
    catalog = container.read(homeCatalogProvider(session).notifier);
    generation = catalog.beginLoad();
    operation = HomeBoardLoad(
      catalog: catalog,
      preferences: HomeCatalogPreferencesRepository(
        readDisabled: () async {
          trace.add('disabled');
          return {};
        },
        readExtras: () async {
          trace.add('extras');
          return extras;
        },
        readRowOrder: () async {
          trace.add('order');
          return [];
        },
        readHeroSource: () async {
          trace.add('hero');
          return (mode: HomeHeroSourceMode.auto, ids: <String>[]);
        },
      ),
      collections: HomeCollectionsRepository(
        read: () async {
          trace.add('collections');
          return savedCollections;
        },
        signature: (_) async {
          trace.add('signature');
          signatureStarted.complete();
          await signatureBarrier;
          return 'fixture-signature';
        },
        onReadFailure: () => trace.add('collection-failure'),
      ),
      services: HomeBoardServices(
        hideWatched: () => hideWatched,
        startWatched: () {
          trace.add('watched-start');
          watchedStarted.complete();
        },
        firstWatchedSnapshot: () => watchedSnapshot,
        resolveLists:
            (rows, {required previous, required isCurrent, required onUpdate}) {
              trace.add('lists');
              listsUpdate = onUpdate;
              return listsResponse.future;
            },
        claimedCatalogs:
            (
              collections,
              addons, {
              required disabledRows,
              required showsCollectionRows,
            }) {
              trace.add('claimed');
              claimedDisabled = Set.of(disabledRows);
              claimedShowsCollections = showsCollectionRows;
              return {};
            },
      ),
    );
  }

  late final ProviderContainer container;
  late final HomeCatalogController catalog;
  late final HomeBoardLoad operation;
  late final int generation;
  final trace = <String>[];
  final commits = <int>[];
  final lateLists = <List<HomeListSection>>[];
  final published = <List<CatalogSection>>[];
  final signatureStarted = Completer<void>();
  final watchedStarted = Completer<void>();
  final listsResponse = Completer<List<HomeListSection>>();
  void Function(List<HomeListSection>)? listsUpdate;
  Future<void> signatureBarrier = Future.value();
  Future<void> watchedSnapshot = Future.value();
  bool current = true;
  bool isHome = true;
  bool? claimedShowsCollections;
  bool hideWatched = false;
  List<HomeExtraRow> extras = [];
  List<HomeCollection> savedCollections = [];
  Set<String>? claimedDisabled;
  List<CatalogSection>? completedRows;
  bool completed = false;
  HomeLoadProgress? progress;
  final addon = StremioAddon(
    id: 'fixture',
    name: 'Fixture',
    manifestUrl: '',
    baseUrl: '',
    catalogs: [
      for (final id in ['a', 'b', 'c', 'd'])
        StremioAddonCatalog(id: id, type: 'movie', name: id),
    ],
  );
  late Future<List<StremioAddon>> Function() readAddons = () async => [addon];
  Future<List<StremioMeta>> Function(String) fetch = (id) async => [
    boardItem(id),
  ];

  bool accepted() => current && catalog.owns(generation);
  void commit() {
    catalog.commit({'fixture': addon});
    commits.add(catalog.current.cursor);
  }

  Future<void> run({
    bool progressive = false,
    int previouslyLoaded = 0,
    List<HomeListSection> previousLists = const [],
  }) {
    if (progressive) {
      progress = HomeLoadProgress(
        isCurrent: accepted,
        rowId: (row) => '${row.addon.id}:${row.catalog.type}:${row.catalog.id}',
        onPublish: (rows, _) => published.add(rows),
      );
    }
    return operation.run(
      generation: generation,
      isHome: () => isHome,
      isCurrent: accepted,
      useSavedOrder: () => true,
      canContinue: () => true,
      captureBatchAcceptance: () => accepted,
      batchSize: 1,
      previouslyLoaded: previouslyLoaded,
      previousRows: {},
      previousLists: previousLists,
      progress: progress,
      onResetCatalogs: () {
        trace.add('reset');
        commit();
      },
      onInventory: (plan, _) {
        trace.add('inventory');
        if (progress != null) {
          progress!.catalogOrder(
            plan.references
                .map((r) => '${r.$1.id}:${r.$2.type}:${r.$2.id}')
                .toList(),
          );
          commit();
        }
      },
      onCommitBatch: commit,
      onLateLists: lateLists.add,
      onCompleted: (rows) {
        trace.add('completed');
        completed = true;
        completedRows = rows;
        commit();
      },
    );
  }

  void dispose() {
    current = false;
    progress?.dispose();
    operation.finish();
    container.dispose();
  }
}
