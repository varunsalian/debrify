import 'dart:async';
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../models/stremio_addon.dart';
import '../../../utils/platform_util.dart';
import '../models/home_catalog_plan.dart';
import '../application/home_board_load.dart';
import '../application/home_catalog_preferences_dependencies.dart';
import '../application/home_board_dependencies.dart';
import '../data/home_board_services.dart';
import '../../search/presentation/catalog_search_section.dart';
import 'home_board_section.dart';
import 'home_board_publication.dart';
import 'home_display_section.dart';
import 'home_spotlight_section.dart';

/// Board (homepage) infinite scroll: how many catalog rows to fetch per batch as
/// the user scrolls, and how many items to keep per row. Enumerating catalogs is
/// free (manifest metadata) — only fetching each row's items costs a call — so we
/// list every catalog up front and lazily pull batches on scroll (Stremio-style)
/// instead of a hard global row cap.
const int kBoardBatchSize = 8;

typedef HomeBoardLoadingDeps = ({
  bool Function() mounted,
  void Function(VoidCallback) setState,
  BuildContext Function() context,
  Object? Function() scope,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  String Function(CatalogSection) rowId,
  Future<void> Function() refreshPikpakOnly,
  void Function(List<CatalogSection>, {bool preserveFocus, bool incremental})
  applySections,
  VoidCallback autoFocus,
  void Function({bool resumeDeferred}) autoFill,
});

/// Initial and refresh board loads, preserving deadlines and generation guards.
class HomeBoardLoading {
  HomeBoardLoading(
    this._ref,
    this._deps,
    this._boardSection,
    this._catalogSection,
    this._boardPublication,
    this._displaySection,
    this._spotlightSection,
    this._ready,
  );
  final WidgetRef _ref;
  final HomeBoardLoadingDeps _deps;
  final HomeBoardSection _boardSection;
  final CatalogSearchSection _catalogSection;
  final HomeBoardPublication _boardPublication;
  final HomeDisplaySection _displaySection;
  final HomeSpotlightSection _spotlightSection;
  final ValueNotifier<bool> _ready;

  Future<void> load({bool preserveVisibleRows = false}) async {
    final context = _deps.context();
    _boardSection.homeReturnRevision =
        _boardSection.homeReturnRepository.revision;
    _boardSection.homeLoadedAt = null;
    final previousLists = HomeBoardServices.previousLists(
      _boardSection.homeSections,
    );
    HomeBoardLoad? operation;
    final keepRows =
        preserveVisibleRows &&
        _boardSection.homeSections.isNotEmpty &&
        _boardSection.committedBoard != null;
    final previousBoard = keepRows ? _boardSection.committedBoard : null;
    final previouslyLoaded = previousBoard?.cursor ?? 0;
    final previousRows = <String, CatalogSection>{
      if (keepRows)
        for (final row in _boardSection.homeSections)
          if (!HomeBoardServices.isList(row)) _deps.rowId(row): row,
    };
    // A superseded pagination request may never return. Its finally block is
    // generation-guarded, so it cannot clear a newer request's loading flag.
    final gen = _boardSection.homeCatalogController.beginLoad();
    _boardSection.homePublication.clear();
    final scope = _deps.scope();
    bool current() =>
        _deps.mounted() &&
        gen == _boardSection.boardLoadGen &&
        scope == _deps.scope();
    // Refreshes already preserve visible rows. Only the Android TV initial
    // Home path changes publication behavior; Search, Discover and tvOS keep
    // their existing loading contract.
    final progressive =
        PlatformUtil.isAndroidTvCached &&
        !_deps.searchMode() &&
        !_deps.discoverMode() &&
        !keepRows;
    final progress = progressive
        ? HomeBoardServices.createProgress(
            isCurrent: current,
            rowId: _deps.rowId,
            onPublish: (rows, first) {
              if (first) {
                developer.Timeline.instantSync('Home.contentPublished');
              }
              _boardPublication.publishHomeProgress(rows, first, gen, scope);
            },
          )
        : null;
    if (progressive) developer.Timeline.instantSync('Home.loadStarted');
    var completionGen = gen;
    var expired = false;
    _boardSection.homePaginationDeferred = false;
    _boardSection.progressiveHomeLoadPending = progressive;
    _deps.setState(() {
      if (!keepRows) {
        _boardSection.loading = true;
        _boardSection.classicAnchorTailPadding = 0;
      }
      _boardSection.error = null;
    });
    unawaited(_deps.refreshPikpakOnly());
    try {
      await HomeBoardServices.runWithDeadline(
        retire: () {
          if (!current()) return;
          expired = true;
          _boardSection.progressiveHomeLoadPending = false;
          completionGen =
              _boardSection.homeCatalogController.retireLoad(gen) ?? gen;
          _boardSection.homePublication.retireGeneration(gen, completionGen);
          // Retiring the generation stops stale batches. A refresh timeout
          // must restore the paging state belonging to the still-visible rows.
          final recovery = progress?.hasPublished == true
              ? _boardSection.committedBoard
              : previousBoard;
          if (recovery != null) {
            _boardSection.homeCatalogController.restore(recovery);
            _boardSection.addonsById
              ..clear()
              ..addAll(recovery.addons);
          } else {
            _boardSection.homeCatalogController.install(const []);
          }
        },
        load: () {
          final load = HomeBoardLoad(
            catalog: _boardSection.homeCatalogController,
            preferences: _ref.read(homeCatalogPreferencesRepositoryProvider),
            collections: _boardSection.homeCollectionsRepository,
            services: _ref.read(homeBoardServicesProvider),
          );
          operation = load;
          return load.run(
            generation: gen,
            isHome: () => !_deps.searchMode() && !_deps.discoverMode(),
            isCurrent: current,
            useSavedOrder: () => _boardSection.homeRowOrderActive,
            canContinue: () => _boardSection.canPageHome,
            captureBatchAcceptance: () {
              final batchScope = _deps.scope();
              return () =>
                  _deps.mounted() &&
                  gen == _boardSection.boardLoadGen &&
                  batchScope == _deps.scope();
            },
            batchSize: kBoardBatchSize,
            previouslyLoaded: previouslyLoaded,
            previousRows: previousRows,
            previousLists: previousLists,
            progress: progress,
            onResetCatalogs: () {
              _boardSection.addonsById.clear();
              _boardSection.commitBoardSnapshot();
            },
            onInventory: (plan, addons) {
              // The metadata lookup is also used by Discover and detail opens.
              _boardSection.addonsById
                ..clear()
                ..addAll(plan.addonsById);
              if (progress != null) {
                progress.catalogOrder(
                  _boardSection.boardRefs.map(homeCatalogRowId).toList(),
                );
                _boardSection.commitBoardSnapshot();
              }
              if (!_deps.searchMode() && !_deps.discoverMode()) {
                unawaited(_spotlightSection.resolveSpotlightHeroSource(addons));
              }
            },
            onCommitBatch: _boardSection.commitBoardSnapshot,
            onLateLists: (rows) => _boardPublication.publishHomeProgress(
              HomeBoardServices.replaceLists(_boardSection.homeSections, rows),
              false,
              gen,
              scope,
            ),
            onCompleted: (rows) {
              if (rows == null) {
                _boardSection.commitBoardSnapshot();
                _boardSection.homeLoadedAt = DateTime.now();
                return;
              }
              _boardSection.homeCatalogController.replaceRows(rows);
              _boardSection.commitBoardSnapshot();
              _boardSection.homeLoadedAt = DateTime.now();
              _deps.setState(() => _boardSection.loading = false);
              _ready.value = true;
              // Keep accepted Home data during a catalog search without
              // replacing its visible results or stealing its focus.
              if (_catalogSection.catalogQuery.isNotEmpty ||
                  _catalogSection.catalogSearching) {
                return;
              }
              _deps.applySections(rows, preserveFocus: keepRows);
              _deps.autoFocus();
            },
          );
        },
      );
    } catch (e) {
      if (!context.mounted ||
          completionGen != _boardSection.boardLoadGen ||
          scope != _deps.scope()) {
        return;
      }
      // Mid-search, the error screen must not replace the search results
      // (_buildBoard renders _boardSection.error before anything else) — latch a retry
      // for _restoreHome instead.
      if (_catalogSection.catalogQuery.isNotEmpty ||
          _catalogSection.catalogSearching) {
        _boardSection.pendingBoardReload = true;
        _deps.setState(() => _boardSection.loading = false);
        _ready.value = true;
        return;
      }
      _deps.setState(() {
        if (!keepRows && progress?.hasPublished != true) {
          _boardSection.error = expired
              ? 'Home took too long to load. Please try again.'
              : e.toString();
        }
        _boardSection.loading = false;
      });
      if (expired && keepRows) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: const Text(
              "Couldn't refresh Home. Showing previous rows.",
            ),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () {
                if (_deps.mounted()) unawaited(load(preserveVisibleRows: true));
              },
            ),
          ),
        );
      }
      // Terminal state too — the launch splash must not outlive the board's
      // loading phase just because it ended in an error screen.
      _ready.value = true;
    } finally {
      progress?.dispose();
      operation?.finish();
      if (completionGen == _boardSection.boardLoadGen &&
          scope == _deps.scope()) {
        _boardSection.homeCatalogController.finishLoad(completionGen);
        _boardSection.progressiveHomeLoadPending = false;
        // Empty/failed catalogs can end without another content publication.
        // Rebuild the initial Spotlight gate so its cards fallback is shown.
        if (_deps.mounted() &&
            !_spotlightSection.spotlightEntryRevealed &&
            _deps.isTelevision() &&
            _displaySection.homeStyleEffective == 'spotlight') {
          _deps.setState(() {});
        }
        if (_deps.mounted() && !expired) {
          _deps.autoFill(resumeDeferred: true);
        }
      }
    }
  }
}
