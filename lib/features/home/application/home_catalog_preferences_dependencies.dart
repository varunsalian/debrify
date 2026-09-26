import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/storage_service.dart';
import '../data/home_catalog_preferences_repository.dart';

final homeCatalogPreferencesRepositoryProvider =
    Provider<HomeCatalogPreferencesRepository>(
      (ref) => HomeCatalogPreferencesRepository(
        readDisabled: StorageService.getHomeDisabledSections,
        readExtras: StorageService.getHomeExtraRows,
        readRowOrder: StorageService.getHomeRowOrder,
        readHeroSource: StorageService.getHomeHeroSource,
      ),
      dependencies: const [],
    );
