import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/storage_service.dart';
import '../data/home_display_preferences_repository.dart';

final homeDisplayPreferencesRepositoryProvider =
    Provider<HomeDisplayPreferencesRepository>(
      (ref) => HomeDisplayPreferencesRepository(
        readFocusDetails: StorageService.getSpotlightFocusDetails,
        readAnimationsEnabled: StorageService.getHomeAnimationsEnabled,
        readAnimationStyle: StorageService.getHomeAnimationStyle,
        readOrientation: StorageService.getHomeCardOrientation,
        readHideTitles: StorageService.getHomeHideCardTitlesAndRatings,
        readHideAddonNames: StorageService.getHomeHideCatalogAddonNames,
        readHideCollectionNames: StorageService.getHomeHideCollectionNames,
      ),
      dependencies: const [],
    );
