import 'package:debrify/features/home/application/home_board_providers.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/home_page_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'default dependency preserves stored keys, defaults and style normalization',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      ProfileRuntime.debugReset();
      ProfileRuntime.initializeLegacy();
      addTearDown(ProfileRuntime.debugReset);
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer.test();
      final repo = container.read(homeDisplayPreferencesRepositoryProvider);
      expect(await repo.read(isCurrent: () => true), (
        orientation: HomeCardOrientation.landscape,
        hideTitlesAndRatings: false,
        hideCatalogAddonNames: false,
        hideCollectionNames: false,
        spotlightFocusDetails: true,
        animationsEnabled: false,
        animationStyle: 'snowy_mountain',
      ));
      await HomePageStorage.setHomeCardOrientation(
        HomeCardOrientation.portrait,
      );
      await HomeAppearanceStorage.setHomeHideCardTitlesAndRatings(true);
      await HomeAppearanceStorage.setHomeHideCatalogAddonNames(true);
      await HomeAppearanceStorage.setHomeHideCollectionNames(true);
      await HomeAppearanceStorage.setSpotlightFocusDetails(true);
      await HomeAppearanceStorage.setHomeAnimationsEnabled(true);
      await HomeAppearanceStorage.setHomeAnimationStyle('midnight_rain');
      final saved = (await repo.read(isCurrent: () => true))!;
      expect(saved, (
        orientation: HomeCardOrientation.portrait,
        hideTitlesAndRatings: true,
        hideCatalogAddonNames: true,
        hideCollectionNames: true,
        spotlightFocusDetails: true,
        animationsEnabled: true,
        animationStyle: 'midnight_rain',
      ));
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('home_animation_style', 'invalid');
      expect(
        (await repo.read(isCurrent: () => true))!.animationStyle,
        'snowy_mountain',
      );
    },
  );
}
