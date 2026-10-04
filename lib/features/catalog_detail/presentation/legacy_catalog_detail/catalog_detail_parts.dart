import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_action_layout.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_bound_sources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_content_columns.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_credits_sections.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_hero_sections.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_primary_action.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_rail_sections.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_resources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_root_layout.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_watchlist.dart';

class CatalogDetailParts {
  final CatalogDetailResources resources;
  final CatalogDetailMetadata metadata;
  final CatalogDetailWatchlist watchlist;
  final CatalogDetailPrimaryAction primaryAction;
  final CatalogDetailBoundSources boundSources;
  final CatalogDetailRootLayout rootLayout;
  final CatalogDetailContentColumns contentColumns;
  final CatalogDetailHeroSections heroSections;
  final CatalogDetailCreditsSections creditsSections;
  final CatalogDetailRailSections railSections;
  final CatalogDetailActionLayout actionLayout;
  CatalogDetailParts(CatalogDetailDependencies deps)
    : resources = CatalogDetailResources(),
      metadata = CatalogDetailMetadata(deps),
      watchlist = CatalogDetailWatchlist(deps),
      primaryAction = CatalogDetailPrimaryAction(deps),
      boundSources = CatalogDetailBoundSources(deps),
      rootLayout = CatalogDetailRootLayout(deps),
      contentColumns = CatalogDetailContentColumns(deps),
      heroSections = CatalogDetailHeroSections(deps),
      creditsSections = CatalogDetailCreditsSections(deps),
      railSections = CatalogDetailRailSections(deps),
      actionLayout = CatalogDetailActionLayout(deps);
}
