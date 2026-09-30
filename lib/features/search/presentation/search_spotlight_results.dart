import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import 'dart:async';
import 'catalog_search_section.dart';
import 'search_spotlight_board.dart' as board;
import '../../home/presentation/home_display_section.dart';
import '../../home/presentation/home_hero_preview.dart';
import '../../home/presentation/home_spotlight_section.dart';
import '../../home/presentation/home_item_actions.dart';
import '../../home/presentation/home_catalog_actions.dart';

typedef SearchSpotlightResultsDeps = ({
  BuildContext Function() context,
  List<CatalogSection> Function() sections,
  List<List<FocusNode>> Function() rowNodes,
  int Function() failures,
  VoidCallback leaveTop,
  void Function(CatalogSection, StremioMeta) openSection,
  bool Function() pikpakOnly,
  String? Function(CatalogSection) catalogTag,
  void Function(CatalogSection) seeAll,
  Future<void> Function(int) loadMoreRow,
});

/// Composes the dedicated Search Spotlight board from live search state.
class SearchSpotlightResults {
  SearchSpotlightResults(
    this._deps,
    this._catalogSection,
    this._displaySection,
    this._heroPreview,
    this._spotlightSection,
    this._itemActions,
    this._catalogActions,
  );
  final SearchSpotlightResultsDeps _deps;
  final CatalogSearchSection _catalogSection;
  final HomeDisplaySection _displaySection;
  final HomeHeroPreview _heroPreview;
  final HomeSpotlightSection _spotlightSection;
  final HomeItemActions _itemActions;
  final HomeCatalogActions _catalogActions;

  Widget buildSearchSpotlightBoard() => board.buildSearchSpotlightBoard(
    context: _deps.context(),
    sections: List<CatalogSection>.of(_deps.sections()),
    rowNodes: _deps.rowNodes(),
    boardKey: _spotlightSection.spotlightKey,
    heroNode: _spotlightSection.spotlightHeroNode,
    query: _catalogSection.catalogQuery,
    searching: _catalogSection.catalogSearching,
    failures: _deps.failures(),
    landscape: _displaySection.homeLandscapeCards,
    showCardTitlesAndRatings: !_displaySection.hideHomeCardTitlesAndRatings,
    expandFocusedCard: _displaySection.spotlightFocusDetails,
    trailersEnabled: _heroPreview.heroTrailerEnabled,
    trailerVolume: _heroPreview.heroTrailerVolume,
    onExitTop: _deps.leaveTop,
    onTrailerStop: _heroPreview.clearHeroTrailer,
    onHeroOpen: _itemActions.openItem,
    onOpen: _deps.openSection,
    onPlay: _deps.pikpakOnly() ? null : _catalogActions.onCatalogPlay,
    sourceTag: _deps.catalogTag,
    onSeeAll: _deps.seeAll,
    onLoadMore: (section) {
      final current = _deps.sections().indexOf(section);
      if (current >= 0) unawaited(_deps.loadMoreRow(current));
    },
  );
}
