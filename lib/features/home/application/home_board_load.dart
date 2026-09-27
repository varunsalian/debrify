import 'dart:async';

import '../../../models/stremio_addon.dart';
import '../../../services/home_collection_rows.dart';
import '../../../services/home_list_rows.dart';
import '../../../services/home_load_progress.dart';
import '../data/home_board_services.dart';
import '../data/home_catalog_preferences_repository.dart';
import '../data/home_collections_repository.dart';
import '../models/home_board_configuration.dart';
import '../models/home_catalog_plan.dart';
import 'home_catalog_controller.dart';
import 'home_catalog_plan.dart';

/// One load operation, including tracker previews that can outlive its catalog
/// phase. The view finishes the operation at the existing deadline/finally point.
/// This transient operation owns no persistent or competing catalog state.
class HomeBoardLoad {
  HomeBoardLoad({
    required this.catalog,
    required this.preferences,
    required this.collections,
    required this.services,
  });

  final HomeCatalogController catalog;
  final HomeCatalogPreferencesRepository preferences;
  final HomeCollectionsRepository collections;
  final HomeBoardServices services;
  var _finished = false;
  var _lists = <HomeListSection>[];

  void finish() => _finished = true;

  List<HomeCollectionSection> _collectionRows() {
    final configuration = catalog.current.configuration;
    return [
      for (final collection in configuration.collections)
        if (collection.enabled &&
            collection.folders.isNotEmpty &&
            !configuration.preferences.disabled.contains(collection.rowId))
          HomeCollectionSection(collection: collection),
    ];
  }

  /// Callbacks run synchronously at their old publication points. Null completed
  /// rows mean progressive publication already supplied the visible/cache rows.
  Future<void> run({
    required int generation,
    required bool Function() isHome,
    required bool Function() isCurrent,
    required bool Function() useSavedOrder,
    required bool Function() canContinue,
    required bool Function() Function() captureBatchAcceptance,
    required int batchSize,
    required int previouslyLoaded,
    required Map<String, CatalogSection> previousRows,
    required List<HomeListSection> previousLists,
    HomeLoadProgress? progress,
    required void Function() onResetCatalogs,
    required void Function(HomeCatalogPlan, List<StremioAddon>) onInventory,
    required void Function() onCommitBatch,
    required void Function(List<HomeListSection>) onLateLists,
    required void Function(List<CatalogSection>?) onCompleted,
  }) async {
    final settings = await preferences.read();
    final savedCollections = await collections.read();
    final signature = await collections.signature(savedCollections);
    // A retired operation must not commit settings or start another tracker fan-out.
    if (!isCurrent()) return;
    catalog.applyConfiguration(
      HomeBoardConfiguration(
        preferences: settings,
        collections: savedCollections,
        collectionsSignature: signature,
        hideWatched: services.hideWatched(),
      ),
    );
    if (progress != null) {
      catalog.install(const []);
      onResetCatalogs();
      progress.collections(_collectionRows());
    }
    final extras = catalog.current.configuration.preferences.extras;
    if (isHome() && extras.any((row) => HomeExtraRowIds.isTracker(row.id))) {
      final enabled = extras.map((row) => row.id).toSet();
      _lists = previousLists
          .where((row) => enabled.contains(row.rowId))
          .toList();
      progress?.lists(_lists);
      unawaited(
        services
            .resolveLists(
              extras,
              previous: _lists,
              isCurrent: isCurrent,
              onUpdate: (rows) {
                if (!isCurrent()) return;
                _lists = rows;
                if (!_finished) {
                  progress?.lists(rows);
                  return;
                }
                onLateLists(rows);
              },
            )
            .catchError((_) => _lists),
      );
    }
    // Keep the existing bounded wait and its disabled-path timing.
    if (services.hideWatched()) {
      services.startWatched();
      await services.firstWatchedSnapshot().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {},
      );
      if (!isCurrent()) return;
    }
    final addons = await catalog.readAddons();
    if (!isCurrent()) return;
    // Settings may have changed during awaits; consult the accepted live value.
    final configuration = catalog.current.configuration;
    final plan = planHomeCatalogs(
      addons,
      disabled: configuration.preferences.disabled,
      claimed: services.claimedCatalogs(
        configuration.collections,
        addons,
        disabledRows: configuration.preferences.disabled,
        showsCollectionRows: isHome(),
      ),
      rowOrder: useSavedOrder() ? configuration.preferences.rowOrder : null,
    );
    catalog.install(plan.references);
    onInventory(plan, addons);
    final first = await catalog.fetchUntilNonEmpty(
      batchSize,
      generation: generation,
      isCurrent: captureBatchAcceptance(),
      canContinue: () => progress == null || canContinue(),
      previousRows: previousRows,
      onSection: progress?.catalog,
      onBatchComplete: progress == null ? null : onCommitBatch,
    );
    // Preserve the old vertical extent and per-batch acceptance capture.
    while (catalog.owns(generation) &&
        catalog.current.cursor < previouslyLoaded &&
        catalog.current.hasMore) {
      first.addAll(
        await catalog.fetchBatch(
          batchSize,
          generation: generation,
          isCurrent: captureBatchAcceptance(),
          previousRows: previousRows,
        ),
      );
    }
    if (!isCurrent()) return;
    if (progress != null) {
      progress.lists(_lists);
      progress.flush(allowEmpty: true);
      onCompleted(null);
      return;
    }
    final collectionRows = isHome()
        ? _collectionRows()
        : const <HomeCollectionSection>[];
    onCompleted([
      for (final row in collectionRows)
        if (row.collection.pinToTop) row,
      ..._lists,
      for (final row in collectionRows)
        if (!row.collection.pinToTop) row,
      ...first,
    ]);
  }
}
