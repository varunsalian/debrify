import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:synchronized/synchronized.dart';

final class CollectionAppearanceStorage {
  const CollectionAppearanceStorage._();

  static const tvCollectionListStyles = {
    'spotlight',
    'grid',
    'gallery',
    'filmstrip',
    'journal',
  };
  // One-time alpha rollout, per profile. Later explicit choices must survive.
  static const _collectionSpotlightMigrationKey = 'tv_collection_spotlight_alpha_migrated_v1';
  static final Lock _collectionStyleLock = Lock();

  static Future<String> getTvCollectionListStyle() => _collectionStyleLock.synchronized(() async {
    final prefs = await ProfilePreferences.instance();
    if (prefs.getBool(_collectionSpotlightMigrationKey) != true) {
      await prefs.setString('tv_collection_list_style', 'spotlight');
      await prefs.setBool(_collectionSpotlightMigrationKey, true);
    }
    final value = prefs.getString('tv_collection_list_style');
    return tvCollectionListStyles.contains(value) ? value! : 'spotlight';
  });

  static Future<void> setTvCollectionListStyle(String value) => _collectionStyleLock.synchronized(() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      'tv_collection_list_style',
      tvCollectionListStyles.contains(value) ? value : 'spotlight',
    );
    await prefs.setBool(_collectionSpotlightMigrationKey, true);
  });
}
