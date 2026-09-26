import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/stremio_service.dart';
import '../../../services/watched_filter.dart';
import '../data/home_catalog_repository.dart';

final homeCatalogRepositoryProvider = Provider<HomeCatalogRepository>(
  (ref) => HomeCatalogRepository(
    readAddons: StremioService.instance.getCatalogAddons,
    fetchPage: (addon, catalog, skip, onRawCount) => StremioService.instance
        .fetchCatalog(addon, catalog, skip: skip, onRawCount: onRawCount),
    readHides: () => WatchedFilter.predicate,
  ),
  dependencies: const [],
);
