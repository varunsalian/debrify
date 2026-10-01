import 'package:flutter/material.dart';
import '../../../models/stremio_addon.dart';
import '../../../models/home_collection_rows.dart';
import '../../../widgets/home/spotlight_board.dart';
import '../../../widgets/home/spotlight_catalog_card_cache.dart';
import '../application/home_stage_metadata.dart';
import 'home_stage_rows.dart';
import 'home_spotlight_shelf.dart';
import 'home_stage_rails.dart';
import 'home_stage_section.dart';
import 'home_stage_favorites.dart';
import 'home_display_section.dart';
import 'home_continuation_menu.dart';
import 'home_item_actions.dart';
import 'home_catalog_item_actions.dart';

typedef HomeSpotlightRowsDeps = ({
  List<CatalogSection> Function() sections,
  List<List<FocusNode>> Function() rowNodes,
  HomeCatalogItemActions items,
  void Function(HomeCollectionSection, StremioMeta) openCollection,
});

/// Projects Home rails and cached catalog cards into Spotlight shelves.
class HomeSpotlightRows {
  HomeSpotlightRows(
    this._deps,
    this._stageRailsSection,
    this._stageSection,
    this._displaySection,
    this._continuationMenu,
    this._stageFavorites,
    this._itemActions,
  );
  final HomeSpotlightRowsDeps _deps;
  final HomeStageRails _stageRailsSection;
  final HomeStageSection _stageSection;
  final HomeDisplaySection _displaySection;
  final HomeContinuationMenu _continuationMenu;
  final HomeStageFavorites _stageFavorites;
  final HomeItemActions _itemActions;

  late final spotlightCatalogCards = SpotlightCatalogCardCache(
    wideArtwork: homeStageWideArtwork,
    onOpen: (item, addon) => _itemActions.openItem(item, addon),
  );

  List<SpotlightShelf> get spotlightShelves => [
    for (final rail in _stageRailsSection.canvasRails)
      spotlightShelfForRail(rail),
  ];

  SpotlightShelf spotlightShelfForRail(HomeRail rail) =>
      buildHomeSpotlightShelf(
        rail,
        railKey: _stageSection.canvasRailKeyOf(rail),
        landscape: _displaySection.homeLandscapeCards,
        hideCollectionNames: _displaySection.hideHomeCollectionNames,
        sections: _deps.sections(),
        rowNodes: _deps.rowNodes(),
        catalogTag: _deps.items.sourceTag,
        onSeeAll: _deps.items.openSeeAll,
        onCollectionOpen: _deps.openCollection,
        onContinuationOptions: _continuationMenu.openCwCardMenu,
        favoriteShelf: _stageFavorites.spotlightFavShelf,
        catalogCard: (item, addon) => spotlightCatalogCards.resolve(
          item,
          addon,
          landscape: _displaySection.homeLandscapeCards,
        ),
      );
}
