import 'package:debrify/services/storage/home_appearance_storage.dart';
import 'package:debrify/services/storage/home_page_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Spotlight focus details persist and reset with Home settings', () async {
    expect(await HomeAppearanceStorage.getSpotlightFocusDetails(), isTrue);
    await HomeAppearanceStorage.setSpotlightFocusDetails(true);
    expect(await HomeAppearanceStorage.getSpotlightFocusDetails(), isTrue);
    await HomeAppearanceStorage.setSpotlightFocusDetails(false);
    expect(await HomeAppearanceStorage.getSpotlightFocusDetails(), isFalse);
    await HomePageStorage.clearAllHomePageSettings();
    expect(await HomeAppearanceStorage.getSpotlightFocusDetails(), isTrue);
  });

  test('Hold to Quick Play defaults off and persists changes', () async {
    expect(await HomePageStorage.getHomeCwHoldToQuickPlay(), isFalse);

    await HomePageStorage.setHomeCwHoldToQuickPlay(true);
    expect(await HomePageStorage.getHomeCwHoldToQuickPlay(), isTrue);

    await HomePageStorage.setHomeCwHoldToQuickPlay(false);
    expect(await HomePageStorage.getHomeCwHoldToQuickPlay(), isFalse);
  });

  test('clearing Home settings resets Hold to Quick Play', () async {
    await HomePageStorage.setHomeCwHoldToQuickPlay(true);

    await HomePageStorage.clearAllHomePageSettings();

    expect(await HomePageStorage.getHomeCwHoldToQuickPlay(), isFalse);
  });

  test('Hide Home card titles and ratings defaults off and persists', () async {
    expect(await HomeAppearanceStorage.getHomeHideCardTitlesAndRatings(), isFalse);

    await HomeAppearanceStorage.setHomeHideCardTitlesAndRatings(true);
    expect(await HomeAppearanceStorage.getHomeHideCardTitlesAndRatings(), isTrue);

    await HomePageStorage.clearAllHomePageSettings();
    expect(await HomeAppearanceStorage.getHomeHideCardTitlesAndRatings(), isFalse);
  });

  test('Hide Home catalog add-on names defaults off and persists', () async {
    expect(await HomeAppearanceStorage.getHomeHideCatalogAddonNames(), isFalse);

    await HomeAppearanceStorage.setHomeHideCatalogAddonNames(true);
    expect(await HomeAppearanceStorage.getHomeHideCatalogAddonNames(), isTrue);

    await HomePageStorage.clearAllHomePageSettings();
    expect(await HomeAppearanceStorage.getHomeHideCatalogAddonNames(), isFalse);
  });

  test('Hide Home collection names defaults off and persists', () async {
    expect(await HomeAppearanceStorage.getHomeHideCollectionNames(), isFalse);

    await HomeAppearanceStorage.setHomeHideCollectionNames(true);
    expect(await HomeAppearanceStorage.getHomeHideCollectionNames(), isTrue);

    await HomePageStorage.clearAllHomePageSettings();
    expect(await HomeAppearanceStorage.getHomeHideCollectionNames(), isFalse);
  });
}
