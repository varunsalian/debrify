import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/stremio_addon.dart';
import '../models/home_catalog_plan.dart';
import '../data/home_catalog_repository.dart';
import 'home_catalog_dependencies.dart';
import '../models/home_catalog_state.dart';
import '../models/home_catalog_session.dart';

final homeCatalogProvider = NotifierProvider.autoDispose
    .family<HomeCatalogController, HomeCatalogState, HomeCatalogSession>(
      HomeCatalogController.new,
      retry: (count, error) => null,
      dependencies: [homeCatalogRepositoryProvider],
    );

/// Owns one view's catalog requests, paging flags and accepted snapshot.
/// The caller supplies profile/mounted acceptance and route continuation policy.
class HomeCatalogController extends Notifier<HomeCatalogState> {
  HomeCatalogController(this.session);
  final HomeCatalogSession session;
  late HomeCatalogRepository _repository;
  int _generation = 0;
  int get generation => _generation;

  bool owns(int generation) => ref.mounted && generation == _generation;

  @override
  HomeCatalogState build() {
    _repository = ref.watch(homeCatalogRepositoryProvider);
    ref.onDispose(() => _generation++);
    final initial = session.initialBoard;
    return const HomeCatalogState.empty().copyWith(
      references: initial?.references,
      cursor: initial?.cursor,
      committed: initial,
      refreshing: session.initiallyRefreshing,
    );
  }

  // Pending legacy refresh loops can finish after their view is removed. They
  // see an exhausted inventory, without reading disposed provider state.
  HomeCatalogState get current =>
      ref.mounted ? state : const HomeCatalogState.empty();

  int beginLoad() {
    if (!ref.mounted) return _generation;
    final generation = ++_generation;
    // Fresh Home seeds this state during construction, before its first frame.
    // Starting that request must not notify providers from widget initState.
    if (!state.refreshing || state.loadingMore) {
      state = state.copyWith(refreshing: true, loadingMore: false);
    }
    return generation;
  }

  /// A timeout retires pending batches but leaves refresh ownership active
  /// until the caller has restored its accepted snapshot and finished the load.
  int? retireLoad(int generation) {
    if (!owns(generation)) return null;
    return ++_generation;
  }

  void finishLoad(int generation) {
    if (owns(generation) && state.refreshing) {
      state = state.copyWith(refreshing: false);
    }
  }

  bool beginPage(int generation) {
    if (!owns(generation) ||
        state.refreshing ||
        state.loadingMore ||
        !state.hasMore) {
      return false;
    }
    state = state.copyWith(loadingMore: true);
    return true;
  }

  void finishPage(int generation) {
    if (owns(generation) && state.loadingMore) {
      state = state.copyWith(loadingMore: false);
    }
  }

  void install(List<HomeCatalogReference> references) {
    if (!ref.mounted) return;
    state = state.copyWith(references: references, cursor: 0);
  }

  List<HomeCatalogReference> reserve(int count) {
    if (!ref.mounted) return const [];
    final end = (state.cursor + count).clamp(0, state.references.length);
    final batch = state.references.sublist(state.cursor, end);
    state = state.copyWith(cursor: end);
    return batch;
  }

  Future<List<StremioAddon>> readAddons() => _repository.readAddons();

  /// Retain synchronous reservation and the repository's completion boundary.
  /// Generation ownership is checked before reserving; publication additionally
  /// requires the caller's mounted/profile acceptance check.
  Future<List<CatalogSection>> fetchBatch(
    int count, {
    required int generation,
    required bool Function() isCurrent,
    Map<String, CatalogSection> previousRows = const {},
    void Function(CatalogSection)? onSection,
  }) => Future<List<CatalogSection>>.sync(() {
    if (!owns(generation)) return const <CatalogSection>[];
    final batch = reserve(count);
    return _repository.fetchBatch(
      batch,
      previousRows: previousRows,
      isCurrent: () => owns(generation) && isCurrent(),
      onSection: onSection,
    );
  });

  /// Empty or already-present rows do not end vertical paging. A covered route
  /// may pause only after an accepted empty batch, retaining its reserved cursor.
  Future<List<CatalogSection>> fetchUntilNonEmpty(
    int batchSize, {
    required int generation,
    required bool Function() isCurrent,
    required bool Function() canContinue,
    Map<String, CatalogSection> previousRows = const {},
    Set<String> excludeRows = const {},
    void Function(CatalogSection)? onSection,
    void Function()? onBatchComplete,
  }) async {
    while (owns(generation) && isCurrent() && state.hasMore) {
      final batch = await fetchBatch(
        batchSize,
        generation: generation,
        isCurrent: isCurrent,
        previousRows: previousRows,
        onSection: onSection,
      );
      if (!owns(generation) || !isCurrent()) return const [];
      onBatchComplete?.call();
      final additions = batch
          .where(
            (row) => !excludeRows.contains(
              homeCatalogRowId((row.addon, row.catalog)),
            ),
          )
          .toList();
      if (additions.isNotEmpty) return additions;
      if (!canContinue()) return const [];
    }
    return const [];
  }

  void commit(Map<String, StremioAddon> addons) {
    if (!ref.mounted) return;
    state = state.copyWith(
      committed: HomeCatalogSnapshot(state.references, state.cursor, addons),
    );
  }

  /// Restoring a return snapshot or timeout recovery never adopts an in-flight
  /// reservation. The caller restores its shared metadata lookup from addons.
  void restore(HomeCatalogSnapshot snapshot) {
    if (!ref.mounted) return;
    state = state.copyWith(
      references: snapshot.references,
      cursor: snapshot.cursor,
      committed: snapshot,
    );
  }
}
