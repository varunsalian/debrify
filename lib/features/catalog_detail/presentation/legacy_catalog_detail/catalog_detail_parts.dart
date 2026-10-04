import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_bound_sources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_dependencies.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_metadata.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_primary_action.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_resources.dart';
import 'package:debrify/features/catalog_detail/presentation/legacy_catalog_detail/catalog_detail_watchlist.dart';

class CatalogDetailParts {
  final CatalogDetailResources resources;
  final CatalogDetailMetadata metadata;
  final CatalogDetailWatchlist watchlist;
  final CatalogDetailPrimaryAction primaryAction;
  final CatalogDetailBoundSources boundSources;
  CatalogDetailParts(CatalogDetailDependencies deps)
    : resources = CatalogDetailResources(),
      metadata = CatalogDetailMetadata(deps),
      watchlist = CatalogDetailWatchlist(deps),
      primaryAction = CatalogDetailPrimaryAction(deps),
      boundSources = CatalogDetailBoundSources(deps);
}
