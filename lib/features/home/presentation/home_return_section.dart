import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/home_return_snapshot.dart';
import '../application/home_row_snapshot.dart';
import '../application/home_board_dependencies.dart';
import '../data/home_board_services.dart';
import 'home_board_section.dart';
import 'home_board_rows.dart';
import 'home_board_focus.dart';
import 'home_board_paging.dart';
import 'home_board_publication.dart';
import 'home_board_configuration_section.dart';
import 'home_display_section.dart';
import 'home_spotlight_section.dart';

typedef HomeReturnDeps = ({
  bool Function() mounted,
  bool Function() searchMode,
  bool Function() discoverMode,
  Object Function() owner,
  Object Function() currentOwner,
  Object? Function() scope,
  Future<void> Function() refreshPikpakOnly,
});

/// Preserves and restores the mounted Home view's accepted return snapshot.
class HomeReturnSection {
  HomeReturnSection(
    this._ref,
    this._deps,
    this._boardSection,
    this._boardRows,
    this._boardFocus,
    this._boardPaging,
    this._boardPublication,
    this._boardConfiguration,
    this._displaySection,
    this._spotlightSection,
    this._ready,
  );
  final WidgetRef _ref;
  final HomeReturnDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeBoardRows _boardRows;
  final HomeBoardFocus _boardFocus;
  final HomeBoardPaging _boardPaging;
  final HomeBoardPublication _boardPublication;
  final HomeBoardConfigurationSection _boardConfiguration;
  final HomeDisplaySection _displaySection;
  final HomeSpotlightSection _spotlightSection;
  final ValueNotifier<bool> _ready;

  Future<void> restoreHomeSnapshot(HomeReturnSnapshot snapshot) async {
    _boardSection.recordReturnRevision();
    _boardSection.recordHomeLoadedAt(snapshot.loadedAt);
    _spotlightSection.spotlightHeroOverride = snapshot.hero;
    _boardSection.addonsById
      ..clear()
      ..addAll(snapshot.board.addons);
    _boardSection.finishLoading();
    _spotlightSection.spotlightEntryRevealed = true;
    if (snapshot.heroResolutionPending) {
      unawaited(
        _spotlightSection.resolveSpotlightHeroSource(
          _boardSection.addonsById.values.toList(),
        ),
      );
    }
    _boardRows.applySections(_boardSection.homeSections);
    _ready.value = true;
    _boardFocus.maybeAutoFocusBoard();
    _boardPaging.maybeAutoFillBoard();
    unawaited(_deps.refreshPikpakOnly());
    if (_boardSection.trackerExtrasEnabled) {
      final generation = _boardSection.boardLoadGen;
      final owner = _deps.owner();
      unawaited(
        _ref
            .read(homeBoardServicesProvider)
            .resolveReturnLists(
              _boardSection.homeExtras,
              previousRows: _boardSection.homeSections,
              isCurrent: () =>
                  _deps.mounted() &&
                  generation == _boardSection.boardLoadGen &&
                  owner == _deps.currentOwner(),
              onUpdate: (rows) {
                if (!_deps.mounted() ||
                    generation != _boardSection.boardLoadGen ||
                    owner != _deps.currentOwner()) {
                  return;
                }
                _boardPublication.publishHomeProgress(
                  HomeBoardServices.replaceLists(
                    _boardSection.homeSections,
                    rows,
                  ),
                  false,
                  generation,
                  _deps.scope(),
                );
              },
            ),
      );
    }
    // Re-read local configuration too, including imports that bypass the UI
    // bridge. Continue Watching and favourite loaders still run on each visit.
    await _boardConfiguration.reloadForHomeSettings();
  }

  void preserveHomeSnapshot() {
    final board = _boardSection.committedBoard;
    final loadedAt = _boardSection.homeLoadedAt;
    if (_deps.searchMode() ||
        _deps.discoverMode() ||
        board == null ||
        loadedAt == null ||
        _boardSection.loading ||
        _boardSection.error != null ||
        _boardSection.boardRefreshing ||
        _boardSection.boardLoadingMore ||
        _boardSection.pendingBoardReload) {
      return;
    }
    _boardSection.homeReturnRepository.store((
      sections: _boardSection.homeCatalogController.rowsForReturn(),
      board: board,
      configuration: _boardSection.homeConfiguration,
      hero: _spotlightSection.spotlightHeroOverride == null
          ? null
          : copyHomeRowForReturn(_spotlightSection.spotlightHeroOverride!),
      heroResolutionPending: _spotlightSection.heroSourceResolutionPending,
      cardOrientation: _displaySection.homeCardOrientation,
      hideCardTitlesAndRatings: _displaySection.hideHomeCardTitlesAndRatings,
      hideCatalogAddonNames: _displaySection.hideHomeCatalogAddonNames,
      hideCollectionNames: _displaySection.hideHomeCollectionNames,
      loadedAt: loadedAt,
      scrollOffset: _boardSection.homeLastScroll,
    ), revision: _boardSection.homeReturnRevision);
  }
}
