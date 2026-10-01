import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/stremio_addon.dart';
import '../../../utils/platform_util.dart';
import '../models/home_catalog_search_status.dart';
import 'home_board_loading.dart' show kBoardBatchSize;
import 'home_board_publication.dart';
import 'home_board_section.dart';
import 'home_stage_section.dart';

typedef HomeBoardPagingDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  Object? Function() scope,
  String Function(CatalogSection) rowId,
  VoidCallback completeDeferredDown,
  Future<void> Function() refreshBoundSources,
});

/// Board-batch and catalog-row pagination, including deferred route returns.
class HomeBoardPaging {
  HomeBoardPaging(
    this._deps,
    this._boardSection,
    this._catalogSection,
    this._boardPublication,
    this._stageSection,
  );
  final HomeBoardPagingDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeCatalogSearchStatus _catalogSection;
  final HomeBoardPublication _boardPublication;
  final HomeStageSection _stageSection;

  void resumeDeferredHomePagination() {
    if (!_boardSection.homePaginationDeferred ||
        _boardSection.boardRefreshing ||
        !_deps.mounted() ||
        !(ModalRoute.of(_deps.context())?.isCurrent ?? true)) {
      return;
    }
    _boardSection.resumePagination();
    if (_boardSection.boardHasMore) unawaited(loadMoreBoard());
  }

  /// After a batch lands, if the board still doesn't fill the viewport (so the
  /// user can't scroll to trigger more) keep pulling batches until it does or
  /// the board is exhausted. No-ops outside board mode (search sets no cursor).
  void maybeAutoFillBoard({bool resumeDeferred = false}) {
    if (!_boardSection.canPageHome ||
        !_boardSection.boardHasMore ||
        _boardSection.boardLoadingMore) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_boardSection.canPageHome ||
          !_boardSection.boardHasMore ||
          _boardSection.boardLoadingMore) {
        return;
      }
      if (resumeDeferred) resumeDeferredHomePagination();
      if (_boardSection.boardLoadingMore) return;
      if (!_boardSection.boardScroll.hasClients) return;
      final pos = _boardSection.boardScroll.position;
      if (pos.maxScrollExtent <= 0 || pos.pixels >= pos.maxScrollExtent - 600) {
        loadMoreBoard();
      }
    });
  }

  /// Fire off the next batch as the user nears the bottom of the board.
  void onBoardScroll() {
    if (_boardSection.boardScroll.hasClients) {
      _boardSection.rememberScroll(_boardSection.boardScroll.offset);
    }
    if (!_boardSection.canPageHome ||
        !_boardSection.boardHasMore ||
        _boardSection.boardLoadingMore) {
      return;
    }
    if (!_boardSection.boardScroll.hasClients) return;
    final pos = _boardSection.boardScroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      loadMoreBoard();
    }
  }

  /// Load and append the next batch of board rows (deduped against re-entry).
  Future<bool> loadMoreBoard() async {
    if (!_boardSection.canPageHome) return false;
    final context = _deps.context();
    if (_boardSection.boardRefreshing) {
      if (PlatformUtil.isAndroidTvCached && _boardSection.boardHasMore) {
        _boardSection.deferPagination();
      }
      return false;
    }
    if (_boardSection.boardLoadingMore ||
        _boardSection.boardCursor >= _boardSection.boardRefs.length) {
      return false;
    }
    // Bind this append to the load generation that owns the current cursor —
    // if a full reload lands mid-fetch, the stale batch must not append onto
    // (or advance) the fresh board.
    final gen = _boardSection.boardLoadGen;
    final scope = _deps.scope();
    var appended = false;
    if (!_boardSection.homeCatalogController.beginPage(gen)) return false;
    _deps.setState(() {});
    try {
      final page = await _boardSection.homeCatalogController.loadNextRows(
        kBoardBatchSize,
        generation: gen,
        isCurrent: () =>
            _deps.mounted() &&
            gen == _boardSection.boardLoadGen &&
            scope == _deps.scope(),
        canContinue: () =>
            !PlatformUtil.isAndroidTvCached || _boardSection.canPageHome,
        currentAddons: () => _boardSection.addonsById,
        rowId: _deps.rowId,
      );
      if (!context.mounted ||
          gen != _boardSection.boardLoadGen ||
          scope != _deps.scope()) {
        return false;
      }
      if (page != null) {
        // Only fold into the live view when the board is still what's
        // shown. If a catalog search started while this batch was in flight,
        // `_boardSection.sections`/`_boardSection.rowNodes` now hold search results — appending board rows
        // there would corrupt the search view. They'll reappear on _restoreHome.
        if (_catalogSection.catalogQuery.isEmpty &&
            !_catalogSection.catalogSearching) {
          if (page.appendOnly &&
              !(PlatformUtil.isAndroidTvCached &&
                  !(ModalRoute.of(context)?.isCurrent ?? true))) {
            appendSections(page.additions);
          } else {
            _boardPublication.publishHomeProgress(page.rows, false, gen, scope);
          }
          appended = true;
          // A DPAD-down past the last row may be waiting on this batch —
          // classic's deferred move, and the stage layouts' rail advance.
          _deps.completeDeferredDown();
          _stageSection.maybeCompleteStageAdvance();
        }
      }
    } finally {
      if (_deps.mounted() &&
          gen == _boardSection.boardLoadGen &&
          scope == _deps.scope()) {
        _deps.setState(
          () => _boardSection.homeCatalogController.finishPage(gen),
        );
        maybeAutoFillBoard();
      }
    }
    return appended;
  }

  /// Append newly-loaded board rows without disturbing the rows already shown:
  /// grow the per-row focus nodes in lockstep with [_boardSection.sections].
  void appendSections(List<CatalogSection> more) {
    _boardSection.boardViewport.appendRows(more);
    _deps.setState(() => _boardSection.appendRows(more));
    unawaited(_deps.refreshBoundSources());
  }

  /// Fetch the next page for a single catalog row and append it in place, so
  /// rows grow without bound as the user scrolls right (Stremio-style). Only
  /// board rows paginate; search-result rows are single-shot. Safe to call
  /// repeatedly — [CatalogSection.loadingMore]/[CatalogSection.exhausted] guard
  /// re-entrancy and the end of the catalog.
  Future<void> loadMoreRow(int rowIndex, {bool resume = false}) async {
    // While a catalog search is active, `_boardSection.sections` holds search results, which
    // don't paginate — leave them alone.
    if (_catalogSection.catalogQuery.isNotEmpty ||
        _catalogSection.catalogSearching) {
      return;
    }
    if (rowIndex < 0 || rowIndex >= _boardSection.sections.length) return;
    final section = _boardSection.sections[rowIndex];
    final scope = _deps.scope();
    int currentIndex() =>
        !_deps.mounted() ||
            scope != _deps.scope() ||
            _catalogSection.catalogQuery.isNotEmpty ||
            _catalogSection.catalogSearching
        ? -1
        : _boardSection.sections.indexWhere((row) => identical(row, section));
    if (!_boardSection.homeCatalogController.beginRowPage(
      section,
      resume: resume,
    )) {
      return;
    }
    // Android TV: flip the guard silently. The setState exists to show the
    // classic row's tail spinner, but it fires on the exact keypress that
    // crossed the row-end threshold — a full-screen rebuild landing on the
    // input frame, which an Amlogic box renders as the cursor hitching every
    // time a row pages. The spinner is a nicety; the page landing repaints
    // either way.
    if (!PlatformUtil.isAndroidTvCached || resume) _deps.setState(() {});
    try {
      // Dedup against what we already have: some addons return valid ids but
      // repeat entries, and some ignore `skip` entirely. The pager advances
      // `skip` by the addon's RAW counts so paging never under-advances into a
      // false "exhausted", and with hide-watched on it tops the window up so a
      // page of watched titles doesn't end the row early.
      final page = await _boardSection.homeCatalogController.fetchRowPage(
        (section.addon, section.catalog),
        skip: section.nextSkip,
        existingIds: section.items.map((item) => item.id),
        isCurrent: () => currentIndex() >= 0,
      );
      // Progressive arrivals can move the SAME row. Only a removed/replaced
      // row or a changed session invalidates its page, not a new numeric index.
      final index = currentIndex();
      if (index < 0) return;
      _boardSection.homeCatalogController.acceptRowPage(section, page);
      final fresh = page.items;
      if (fresh.isEmpty) return;
      // Grow this row's focus nodes in lockstep with the new items.
      _boardSection.boardViewport.appendItems(index, fresh.length);
      _deps.setState(
        () =>
            _boardSection.homeCatalogController.appendRowItems(section, fresh),
      );
      // A DPAD-right that ran off the end of this row may be waiting on it.
      _stageSection.maybeCompleteStageRight();
      unawaited(_deps.refreshBoundSources());
    } catch (_) {
      // Transient fetch failure — leave the row as-is so a later scroll retries.
    } finally {
      if (currentIndex() >= 0) {
        _deps.setState(
          () => _boardSection.homeCatalogController.finishRowPage(section),
        );
      } else {
        _boardSection.homeCatalogController.finishRowPage(section);
      }
    }
  }
}
