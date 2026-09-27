import '../../../models/stremio_addon.dart';
import '../../../models/home_preferences.dart';
import 'home_board_configuration.dart';
import 'home_catalog_state.dart';

/// Completed Home data; interactive resources belong to each screen instance.
typedef HomeReturnSnapshot = ({
  List<CatalogSection> sections,
  HomeCatalogSnapshot board,
  HomeBoardConfiguration configuration,
  CatalogSection? hero,
  bool heroResolutionPending,
  HomeCardOrientation cardOrientation,
  bool hideCardTitlesAndRatings,
  bool hideCatalogAddonNames,
  bool hideCollectionNames,
  DateTime loadedAt,
  double scrollOffset,
});
