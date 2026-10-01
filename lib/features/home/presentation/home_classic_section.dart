import 'package:flutter/material.dart';
import '../../../models/home_collection_rows.dart';
import '../../../widgets/home/home_theme.dart';
import '../models/home_catalog_search_status.dart';
import 'home_catalog_search_status_strip.dart';
import 'home_board_section.dart';
import 'home_board_focus.dart';
import 'home_board_deferred.dart';
import 'home_board_paging.dart';
import 'home_board_media.dart';
import 'home_display_section.dart';
import 'home_classic_board.dart';
import 'home_classic_rows.dart';
import 'home_catalog_row.dart';
import 'home_stage_rows.dart';
import 'home_stage_rails.dart';
import 'home_stage_geometry.dart';
import 'home_saved_content_section.dart';
import 'home_saved_content_rows.dart';
import 'home_continuation_projection.dart';
import 'home_continuation_menu.dart';
import 'home_continuation_rows.dart';
import 'home_hero_section.dart';
import 'home_hero_preview.dart';
import 'home_hero_live.dart';
import 'home_classic_geometry.dart';
import 'home_catalog_item_actions.dart';

typedef HomeClassicSectionDeps = ({
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
  HomeBoardMedia Function() media,
  int Function() artworkWidth,
  int Function() artworkHeight,
  int Function() heroIdentity,
  VoidCallback sidebar,
  HomeCatalogItemActions items,
});

/// Classic board composition and catalog-cell interaction wiring. Sizing
/// comes from [HomeClassicGeometry].
class HomeClassicSection {
  HomeClassicSection(
    this._deps,
    this._geometry,
    this._boardSection,
    this._boardFocus,
    this._boardDeferred,
    this._boardPaging,
    this._catalogSection,
    this._displaySection,
    this._stageRailsSection,
    this._stageGeometry,
    this._savedSection,
    this._savedRows,
    this._continuationProjection,
    this._continuationMenu,
    this._continuationRows,
    this._heroSection,
    this._heroPreview,
    this._heroLive,
  );
  final HomeClassicSectionDeps _deps;
  final HomeClassicGeometry _geometry;
  final HomeBoardSection _boardSection;
  final HomeBoardFocus _boardFocus;
  final HomeBoardDeferred _boardDeferred;
  final HomeBoardPaging _boardPaging;
  final HomeCatalogSearchStatus _catalogSection;
  final HomeDisplaySection _displaySection;
  final HomeStageRails _stageRailsSection;
  final HomeStageGeometry _stageGeometry;
  final HomeSavedContentSection _savedSection;
  final HomeSavedContentRows _savedRows;
  final HomeContinuationProjection _continuationProjection;
  final HomeContinuationMenu _continuationMenu;
  final HomeContinuationRows _continuationRows;
  final HomeHeroSection _heroSection;
  final HomeHeroPreview _heroPreview;
  final HomeHeroLive _heroLive;

  Widget buildClassicBoard() {
    final context = _deps.context();
    final tv = _deps.isTelevision();
    return buildHomeClassicBoard(
      context: context,
      isTelevision: tv,
      tvHeroBudget: _geometry.tvHeroBudget,
      media: () => _deps.media(),
      trailerActive: () => _heroPreview.heroTrailerActive,
      heroActive: () => _heroSection.heroActive,
      readHeroConfiguration: () => (
        compact: _deps.searchMode(),
        isTelevision: tv,
        artworkCacheWidth: tv
            ? (_displaySection.homeBoardMode
                  ? _deps.artworkWidth()
                  : HomeTheme.heroBackdropCacheWidthTv)
            : HomeTheme.heroBackdropCacheWidth,
        artworkCacheHeight: tv
            ? (_displaySection.homeBoardMode
                  ? _deps.artworkHeight()
                  : HomeTheme.heroBackdropCacheHeightTv)
            : null,
        trailerActive: _heroPreview.heroTrailerActive,
      ),
      tint: _heroSection.heroTint,
      trailerShowing: _heroPreview.heroTrailerShowing,
      liveTakeover: _heroLive.heroLiveTakeover,
      showSearchStatus: () =>
          _catalogSection.catalogQuery.isNotEmpty &&
          (_catalogSection.catalogSearching ||
              _catalogSection.catalogFailures > 0),
      searchStatus: _buildSearchStatusStrip,
      rowsBuilder: (_) => _buildClassicRows(),
    );
  }

  Widget _buildClassicRows() {
    // Home uses one globally ordered descriptor list across
    // every row family. Catalog search results never read
    // that Home order.
    final orderedHome = _boardSection.homeRowOrderActive;
    final homeRails = orderedHome
        ? _stageRailsSection.classicHomeRails
        : const <HomeRail>[];
    return HomeClassicRows.fromRails(
      scrollController: _boardSection.boardScroll,
      generation: _boardSection.boardGen,
      catalogRowCount: _boardSection.sections.length,
      rails: orderedHome ? homeRails : null,
      rowIdOf: _stageRailsSection.canvasRailRowId,
      catalog: _buildRow,
      skeleton: _continuationRows.buildTraktSkeletonRow,
      continuation: _continuationRows.buildContinueWatchingRow,
      favorite: _savedRows.buildFavRow,
      showFooter: _boardSection.boardLoadingMore,
      tailPadding: _boardSection.classicAnchorTailPadding,
      footerBuilder: (_) => _buildBoardFooter(),
      isFresh: () =>
          DateTime.now().difference(_boardSection.boardAppliedAt) <
          const Duration(milliseconds: 1800),
    );
  }

  /// Status strip for a streaming catalog search (see the call site in
  /// [buildClassicBoard]). Fixed height so the swap from "searching" bar to the
  /// failure note doesn't reflow the rows under DPAD focus.
  Widget _buildSearchStatusStrip() => buildCatalogSearchStatus(
    _deps.context(),
    searching: _catalogSection.catalogSearching,
    failures: _catalogSection.catalogFailures,
  );

  Widget _buildRow(int rowIndex, {String? homeRowId}) {
    final context = _deps.context();
    final section = _boardSection.sections[rowIndex];
    final nodes = _boardSection.rowNodes[rowIndex];
    final tv = _deps.isTelevision();
    // Bigger, roomier posters on desktop (Stremio-scale); smaller on phones.
    // Titleless cells (Stremio-style) — just the art box + a little headroom
    // for the hover/focus lift. The box follows the Home Cards orientation.
    // Collection rows draw their folders' own tile shape (a brand tile stays
    // wide even when Home cards are portrait) at the same height as every
    // other rail, so the row grammar stays intact.
    final collection = section is HomeCollectionSection ? section : null;
    final cellH = _geometry.railTitleCardH(context);
    final cellAspect =
        collection?.tileAspectRatio ?? _stageGeometry.titleCardAspect;
    final posterW = collection == null
        ? _geometry.railTitleCardW(context)
        : cellH * cellAspect;
    // Rows start straight on the first poster (Stremio-style, no
    // leading See-All tile). DPAD-up from row 0 leaves the board;
    // col-0 DPAD-left drops to the sidebar (handled in HomeBoardCell
    // when onLeftEdge is null).
    VoidCallback up(int col) => homeRowId != null
        ? () => _boardFocus.focusRelativeHomeRail(homeRowId, -1, col)
        : rowIndex == 0
        ? (_savedSection.anyFavVisible
              ? () => _savedSection.focusFavRowAt(
                  _savedSection.favRowCount - 1,
                  col,
                )
              : (_continuationProjection.cwVisible
                    ? () => _continuationMenu.focusCwRow(
                        _continuationProjection.cwRows.length - 1,
                        col,
                      )
                    : () => _boardFocus.leaveBoardTop()))
        : () => _boardFocus.focusRow(rowIndex - 1, col);
    // Down past the last loaded row kicks the next batch load
    // (inside _boardFocus.focusRow) and defers the move until it lands.
    VoidCallback down(int col) => homeRowId != null
        ? () => _boardFocus.focusRelativeHomeRail(homeRowId, 1, col)
        : () {
            if (!_boardFocus.focusRow(rowIndex + 1, col)) {
              _boardDeferred.deferDownMove(rowIndex: rowIndex, column: col);
            }
          };
    return buildHomeCatalogItems(
      section: section,
      nodes: nodes,
      tv: tv,
      header: collection == null || !_displaySection.hideHomeCollectionNames
          ? _geometry.railHeader(
              title: section.title,
              tag: _deps.items.sourceTag(section),
              onSeeAll: () => _deps.items.openSeeAll(section),
            )
          : const SizedBox(height: 8),
      cellH: cellH,
      cellAspect: cellAspect,
      posterW: posterW,
      heroTagFor: (col) => 'poster-${_deps.heroIdentity()}-$rowIndex-$col',
      isBound: _deps.items.isBound,
      artOf: (item) => _stageGeometry.titleArtUrl(item),
      showTitle: () => !_displaySection.hideHomeCardTitlesAndRatings,
      pikpakOnly: () => _deps.items.pikpakOnly,
      onLeftEdge: () => _deps.sidebar(),
      up: up,
      down: down,
      onFocused: (item, col) {
        _heroSection.setHero(item);
        _boardSection.rowCol[rowIndex] = col;
      },
      onOpen: (item, heroTag) =>
          _deps.items.open(section, item, heroTag: heroTag),
      onQuickPlay: (item) => _deps.items.quickPlay(section, item),
      onLoadMore: () => _boardPaging.loadMoreRow(rowIndex),
    );
  }

  /// Bottom-of-board loading indicator shown while more catalog rows stream in.
  Widget _buildBoardFooter() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}
