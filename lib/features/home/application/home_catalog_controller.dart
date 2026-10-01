import '../models/home_board_configuration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/stremio_addon.dart';
import '../../../services/filtered_catalog_pager.dart';
import '../../../services/home_load_progress.dart';
import '../models/home_catalog_plan.dart';
import '../data/home_catalog_repository.dart';
import 'home_board_providers.dart';
import 'home_row_snapshot.dart';
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
  List<CatalogSection>? _rows;

  /// Read-only inventory; legacy row identities are borrowed by presentation.
  /// Only this controller mutates their paging fields and item lists.
  List<CatalogSection> get rows => _rows ?? const [];

  int _generation = 0;
  int get generation => _generation;

  bool owns(int generation) => ref.mounted && generation == _generation;

  @override
  HomeCatalogState build() {
    _repository = ref.watch(homeCatalogRepositoryProvider);
    // Dependency recomputation retires requests, not the retained visible rows.
    _rows ??= List.unmodifiable(session.initialRows);
    ref.onDispose(() => _generation++);
    final initial = session.initialBoard;
    return const HomeCatalogState.empty().copyWith(
      references: initial?.references,
      cursor: initial?.cursor,
      committed: initial,
      refreshing: session.initiallyRefreshing,
      configuration: session.initialConfiguration,
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

  /// Both full loads and settings refresh validate their own request/profile
  /// before accepting configuration; they share this one current value.
  void applyConfiguration(HomeBoardConfiguration configuration) {
    if (!ref.mounted) return;
    state = state.copyWith(configuration: configuration);
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

  List<CatalogSection> rowsForReturn() =>
      rows.map(copyHomeRowForReturn).toList();

  void replaceRows(List<CatalogSection> rows) {
    if (!ref.mounted) return;
    _rows = List.unmodifiable(rows);
    _rowsChanged();
  }

  void _rowsChanged() {
    if (ref.mounted) {
      state = state.copyWith(rowsRevision: state.rowsRevision + 1);
    }
  }

  bool beginRowPage(CatalogSection row, {bool resume = false}) {
    if (!ref.mounted ||
        (row.pagingPaused && !resume) ||
        row.loadingMore ||
        row.exhausted) {
      return false;
    }
    row.loadingMore = true;
    _rowsChanged();
    return true;
  }

  /// The view validates live row/profile ownership before accepting a page.
  /// Metadata precedes focus allocation, including empty resumable windows.
  void acceptRowPage(CatalogSection row, FilteredPage page) {
    if (!ref.mounted) return;
    row.nextSkip = page.nextSkip;
    if (page.exhausted) row.exhausted = true;
    row.pagingPaused = page.items.isEmpty && !page.exhausted;
    _rowsChanged();
  }

  /// Focus nodes are allocated by presentation before items become visible.
  void appendRowItems(CatalogSection row, List<StremioMeta> items) {
    if (!ref.mounted) return;
    row.items.addAll(items);
    _rowsChanged();
  }

  void finishRowPage(CatalogSection row) {
    // A removed view/row must still release its borrowed loading latch. It may
    // be retained by a pending refresh, but disposal must not notify Riverpod.
    row.loadingMore = false;
    _rowsChanged();
  }

  /// Horizontal requests belong to a displayed row, not the board generation:
  /// a refresh may retain that same row. Publication remains identity-guarded.
  Future<FilteredPage> fetchRowPage(
    HomeCatalogReference reference, {
    required int skip,
    required Iterable<String> existingIds,
    required bool Function() isCurrent,
  }) => _repository.fetchRowPage(
    reference,
    skip: skip,
    existingIds: existingIds,
    isCurrent: isCurrent,
  );

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

  /// Fetch and accept a vertical page independently of visible search results.
  /// The view retains loading/focus ownership and decides when to show the rows.
  Future<
    ({
      List<CatalogSection> additions,
      List<CatalogSection> rows,
      bool appendOnly,
    })?
  >
  loadNextRows(
    int batchSize, {
    required int generation,
    required bool Function() isCurrent,
    required bool Function() canContinue,
    required Map<String, StremioAddon> Function() currentAddons,
    required String Function(CatalogSection) rowId,
  }) async {
    final existing = {for (final row in rows) rowId(row): row};
    final additions = await fetchUntilNonEmpty(
      batchSize,
      generation: generation,
      isCurrent: isCurrent,
      canContinue: canContinue,
      previousRows: existing,
      excludeRows: existing.keys.toSet(),
    );
    if (!owns(generation) || !isCurrent()) return null;
    // Commit the accepted cursor even when a covered empty batch pauses paging.
    // Read addons at completion, matching the shared metadata lookup's lifetime.
    commit(currentAddons());
    if (additions.isEmpty) return null;
    final previous = rows;
    final merged = mergeHomeCatalogRows(
      previous: previous,
      additions: additions,
      catalogOrder: state.references.map(homeCatalogRowId).toList(),
      rowId: rowId,
    );
    final appendOnly =
        merged.length == previous.length + additions.length &&
        Iterable<int>.generate(
          previous.length,
        ).every((i) => identical(merged[i], previous[i]));
    replaceRows(merged);
    return (
      additions: List<CatalogSection>.unmodifiable(additions),
      rows: rows,
      appendOnly: appendOnly,
    );
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
