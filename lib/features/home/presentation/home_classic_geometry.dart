import 'package:flutter/material.dart';
import '../../../models/home_collection_rows.dart';
import '../../../models/stremio_addon.dart';
import 'home_catalog_row_header.dart';
import 'home_classic_row_metrics.dart';
import 'home_display_section.dart';

typedef HomeClassicGeometryDeps = ({
  BuildContext Function() context,
  bool Function() isTelevision,
  bool Function() searchMode,
});

/// Classic board sizing: poster and card sizes, the TV hero budget, row
/// extents and the row header. Pure layout from the display preferences.
class HomeClassicGeometry {
  HomeClassicGeometry(this._deps, this._display);
  final HomeClassicGeometryDeps _deps;
  final HomeDisplaySection _display;

  /// Poster width for a board rail. On TV the logical canvas can be as short as
  /// 540px (a 1080p panel at density 320 → devicePixelRatio 2.0), where a poster
  /// tuned for a 720-logical canvas leaves no room for a row (plus its header and
  /// the next row's header) under the hero. So scale the poster with the screen
  /// height.
  double railPosterW(BuildContext context) => homeRailPosterWidth(
    context,
    isTelevision: _deps.isTelevision(),
    searchResults: _deps.searchMode(),
  );

  Size railTitleCardSize(BuildContext context) => homeClassicCardSize(
    posterWidth: railPosterW(context),
    landscape: _display.homeLandscapeCards,
  );

  double railTitleCardW(BuildContext context) =>
      railTitleCardSize(context).width;
  double railTitleCardH(BuildContext context) =>
      railTitleCardSize(context).height;

  double tvHeroBudget(double boardH) => homeClassicHeroBudget(
    boardHeight: boardH,
    cardHeight: railTitleCardH(_deps.context()),
    isTelevision: _deps.isTelevision(),
    searchResults: _deps.searchMode(),
  );

  double classicCatalogRowExtent(
    BuildContext context, {
    CatalogSection? section,
  }) => measureHomeClassicRowExtent(
    context,
    hideHeader:
        _display.hideHomeCollectionNames && section is HomeCollectionSection,
    hideSourceTags: _display.hideHomeCatalogAddonNames,
    titleStyle: () => homeCatalogRowTitleStyle(_deps.context(), fontSize: 15),
    cardHeight: () => railTitleCardH(context),
  );

  Widget railHeader({
    required String title,
    String? tag,
    VoidCallback? onSeeAll,
  }) => buildHomeCatalogRowHeader(
    _deps.context(),
    isTelevision: _deps.isTelevision(),
    title: title,
    tag: tag,
    onSeeAll: onSeeAll,
  );
}
