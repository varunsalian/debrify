import 'dart:async';
import 'package:flutter/material.dart';
import '../../../ui/core/retry_message.dart';
import '../../../widgets/skeleton_poster.dart' show BrandLoadingStage;
import '../../search/presentation/catalog_search_section.dart';
import 'home_board_section.dart';
import 'home_board_loading.dart';
import 'home_board_paging.dart';
import 'home_board_focus.dart';
import 'home_board_content.dart';
import 'home_board_frame.dart';
import 'home_display_section.dart';
import 'home_spotlight_section.dart';
import 'home_spotlight_rows.dart';
import 'home_saved_content_section.dart';
import 'home_continuation_projection.dart';

typedef HomeBoardRenderingDeps = ({
  bool Function() mounted,
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  bool Function() discoverMode,
  bool Function() profileCurrent,
  Map<String, Widget Function()> Function() layouts,
  Widget Function() classic,
  Widget Function() searchSpotlight,
});

/// Board frame, layout selection and its explicit catalog continuation actions.
class HomeBoardRendering {
  HomeBoardRendering(
    this._deps,
    this._boardSection,
    this._boardLoading,
    this._boardPaging,
    this._boardFocus,
    this._catalogSection,
    this._displaySection,
    this._spotlightSection,
    this._spotlightRows,
    this._savedSection,
    this._continuationProjection,
  );
  final HomeBoardRenderingDeps _deps;
  final HomeBoardSection _boardSection;
  final HomeBoardLoading _boardLoading;
  final HomeBoardPaging _boardPaging;
  final HomeBoardFocus _boardFocus;
  final CatalogSearchSection _catalogSection;
  final HomeDisplaySection _displaySection;
  final HomeSpotlightSection _spotlightSection;
  final HomeSpotlightRows _spotlightRows;
  final HomeSavedContentSection _savedSection;
  final HomeContinuationProjection _continuationProjection;

  Future<void> continueHomeCatalogs({required bool moreCatalogs}) async {
    final gen = _boardSection.boardLoadGen;
    bool current() =>
        _deps.mounted() &&
        gen == _boardSection.boardLoadGen &&
        _deps.profileCurrent();
    final actionNode = moreCatalogs
        ? _boardFocus.catalogMoreNode
        : _boardFocus.catalogContinueNode;
    final ownedFocus = actionNode.hasFocus;
    final operation = _boardSection.catalogContinuationController.start(
      moreCatalogs: moreCatalogs,
      boardLoading: _boardSection.boardLoadingMore,
      rows: _boardSection.sections,
      hasMoreCatalogs: () => _boardSection.boardHasMore,
      isCurrent: current,
      loadMoreCatalogs: () async {
        await _boardPaging.loadMoreBoard();
      },
      resumeRow: (section) async {
        final i = _boardSection.sections.indexOf(section);
        if (i >= 0) await _boardPaging.loadMoreRow(i, resume: true);
      },
    );
    if (operation == null) return;
    try {
      await operation;
    } finally {
      _boardFocus.catalogFocus.restoreAfterCompletion(
        actionNode,
        ownedFocus: ownedFocus,
        isCurrent: current,
        onRestore: _boardFocus.restoreCatalogContinuationFocus,
      );
    }
  }

  Widget buildBoard() {
    final pending = [
      for (var i = 0; i < _boardSection.sections.length; i++)
        if (_boardSection.sections[i].pagingPaused &&
            !_boardSection.sections[i].exhausted)
          i,
    ];
    final hasMoreCatalogs = _boardSection.boardHasMore;
    final busy =
        _boardSection.catalogContinuing ||
        _boardSection.boardLoadingMore ||
        pending.any((i) => _boardSection.sections[i].loadingMore);
    return buildHomeBoardFrame(
      loading: _boardSection.loading,
      hasError: _boardSection.error != null,
      hasCatalogs: _boardSection.sections.isNotEmpty,
      catalogsEmpty: _boardSection.sections.every((s) => s.items.isEmpty),
      continuationVisible: _continuationProjection.cwVisible,
      favoritesVisible: _savedSection.anyFavVisible,
      hasPausedRows: pending.isNotEmpty,
      hasMoreCatalogs: hasMoreCatalogs,
      busy: busy,
      continueNode: _boardFocus.catalogContinueNode,
      moreNode: _boardFocus.catalogMoreNode,
      onRestoreFocus: _boardFocus.restoreCatalogContinuationFocus,
      onContinueRows: () => continueHomeCatalogs(moreCatalogs: false),
      onMoreCatalogs: () => continueHomeCatalogs(moreCatalogs: true),
      content: buildBoardContent,
      message: message,
    );
  }

  Widget buildBoardContent() {
    if (!_boardSection.loading &&
        !_spotlightSection.spotlightEntryRevealed &&
        _deps.isTelevision() &&
        !_deps.searchMode() &&
        !_deps.discoverMode() &&
        _catalogSection.catalogQuery.isEmpty &&
        !_catalogSection.catalogSearching &&
        _displaySection.homeStyleEffective == 'spotlight') {
      if (_spotlightSection.spotlightHero.isEmpty &&
          (_boardSection.boardRefreshing ||
              _spotlightSection.heroSourceResolving)) {
        return BrandLoadingStage(isTelevision: true);
      }
      // Reveal once: background refreshes must not hide an already usable
      // board. Hero success enters on the hero; exhaustion enters on a card.
      _spotlightSection.spotlightEntryRevealed = true;
      _boardFocus.autoFocusSettled = false;
      _boardFocus.maybeAutoFocusBoard();
    }
    return buildHomeBoardContent(
      loading: _boardSection.loading,
      isTelevision: _deps.isTelevision(),
      error: _boardSection.error,
      continuationVisible: _continuationProjection.cwVisible,
      catalogsEmpty: _boardSection.sections.isEmpty,
      favoritesVisible: _savedSection.anyFavVisible,
      traktReserving: _continuationProjection.traktReserving,
      query: _catalogSection.catalogQuery,
      searchFailures: _catalogSection.catalogState.failures,
      searchMode: _deps.searchMode(),
      style: _displaySection.homeStyleEffective,
      spotlightHasContent: () =>
          _spotlightRows.spotlightShelves.any((s) => s.items.isNotEmpty),
      layouts: _deps.layouts(),
      searchSpotlight: _deps.searchSpotlight,
      classic: _deps.classic,
      onRetry: () => unawaited(_boardLoading.load()),
      message: message,
    );
  }

  Widget message(
    IconData icon,
    String title,
    String body, {
    VoidCallback? onRetry,
  }) => buildRetryMessage(
    _deps.context(),
    icon,
    title,
    body,
    isTelevision: _deps.isTelevision(),
    onRetry: onRetry,
  );
}
