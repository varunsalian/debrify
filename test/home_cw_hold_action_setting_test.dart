import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Hold to Quick Play defaults off and persists changes', () async {
    expect(await StorageService.getHomeCwHoldToQuickPlay(), isFalse);

    await StorageService.setHomeCwHoldToQuickPlay(true);
    expect(await StorageService.getHomeCwHoldToQuickPlay(), isTrue);

    await StorageService.setHomeCwHoldToQuickPlay(false);
    expect(await StorageService.getHomeCwHoldToQuickPlay(), isFalse);
  });

  test('clearing Home settings resets Hold to Quick Play', () async {
    await StorageService.setHomeCwHoldToQuickPlay(true);

    await StorageService.clearAllHomePageSettings();

    expect(await StorageService.getHomeCwHoldToQuickPlay(), isFalse);
  });

  test('Hide Home card titles and ratings defaults off and persists', () async {
    expect(await StorageService.getHomeHideCardTitlesAndRatings(), isFalse);

    await StorageService.setHomeHideCardTitlesAndRatings(true);
    expect(await StorageService.getHomeHideCardTitlesAndRatings(), isTrue);

    await StorageService.clearAllHomePageSettings();
    expect(await StorageService.getHomeHideCardTitlesAndRatings(), isFalse);
  });

  test('Hide Home catalog add-on names defaults off and persists', () async {
    expect(await StorageService.getHomeHideCatalogAddonNames(), isFalse);

    await StorageService.setHomeHideCatalogAddonNames(true);
    expect(await StorageService.getHomeHideCatalogAddonNames(), isTrue);

    await StorageService.clearAllHomePageSettings();
    expect(await StorageService.getHomeHideCatalogAddonNames(), isFalse);
  });
}
