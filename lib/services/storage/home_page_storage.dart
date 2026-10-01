import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/storage/home_appearance_storage.dart';

final class HomePageStorage {
  const HomePageStorage._();

  // Home page default keys
  static const String _homeDefaultSourceTypeKey = 'home_default_source_type';
  static const String _homeDefaultAddonUrlKey = 'home_default_addon_url';
  static const String _homeDefaultCatalogIdKey = 'home_default_catalog_id';
  static const String _homeDefaultTraktListTypeKey = 'home_default_trakt_list_type';
  static const String _homeDefaultTraktContentTypeKey = 'home_default_trakt_content_type';
  static const String _homeHideProviderCardsKey = 'home_hide_provider_cards';
  static const String _homeContinueWatchingEnabledKey = 'home_continue_watching_enabled';
  static const String _homeCwHoldToQuickPlayKey = 'home_cw_hold_to_quick_play';
  static const String _homeCwMergedRowsKeyPrefix = 'home_cw_merge_';
  static const String _homeFavoritesOpenFolderKey = 'home_favorites_open_folder';
  static const String _homeCardOrientationKey = 'home_card_orientation';

  // Startup auto-launch was removed; only `StartupStorage.clearAllStartupSettings` remains
  // (used by Reset) to wipe the old persisted keys.

  // Home Page Default Settings
  static Future<String?> getHomeDefaultSourceType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultSourceTypeKey);
  }

  static Future<void> setHomeDefaultSourceType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultSourceTypeKey);
    } else {
      await prefs.setString(_homeDefaultSourceTypeKey, value);
    }
  }

  static Future<String?> getHomeDefaultAddonUrl() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultAddonUrlKey);
  }

  static Future<void> setHomeDefaultAddonUrl(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultAddonUrlKey);
    } else {
      await prefs.setString(_homeDefaultAddonUrlKey, value);
    }
  }

  static Future<String?> getHomeDefaultCatalogId() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultCatalogIdKey);
  }

  static Future<void> setHomeDefaultCatalogId(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultCatalogIdKey);
    } else {
      await prefs.setString(_homeDefaultCatalogIdKey, value);
    }
  }

  static Future<String?> getHomeDefaultTraktListType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultTraktListTypeKey);
  }

  static Future<void> setHomeDefaultTraktListType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultTraktListTypeKey);
    } else {
      await prefs.setString(_homeDefaultTraktListTypeKey, value);
    }
  }

  static Future<String?> getHomeDefaultTraktContentType() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeDefaultTraktContentTypeKey);
  }

  static Future<void> setHomeDefaultTraktContentType(String? value) async {
    final prefs = await ProfilePreferences.instance();
    if (value == null) {
      await prefs.remove(_homeDefaultTraktContentTypeKey);
    } else {
      await prefs.setString(_homeDefaultTraktContentTypeKey, value);
    }
  }

  static Future<bool> getHomeHideProviderCards() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeHideProviderCardsKey) ?? true;
  }

  static Future<void> setHomeHideProviderCards(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeHideProviderCardsKey, value);
  }

  static Future<bool> getHomeContinueWatchingEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeContinueWatchingEnabledKey) ?? true;
  }

  static Future<void> setHomeContinueWatchingEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeContinueWatchingEnabledKey, value);
  }

  /// Whether holding a Continue Watching card should immediately Quick Play
  /// instead of opening the Play / Remove action menu. Off by default so the
  /// removal action remains discoverable until the user opts into the faster
  /// gesture.
  static Future<bool> getHomeCwHoldToQuickPlay() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_homeCwHoldToQuickPlayKey) ?? false;
  }

  static Future<void> setHomeCwHoldToQuickPlay(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_homeCwHoldToQuickPlayKey, value);
  }

  /// Whether [provider]'s home Continue Watching shelf combines Movies and
  /// Shows into ONE recency-ordered row instead of two. [provider] is one of
  /// 'local', 'trakt', 'simkl', 'mdblist'. Off by default (two rows, the
  /// original layout).
  static Future<bool> getHomeCwMergedRows(String provider) async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('$_homeCwMergedRowsKeyPrefix$provider') ?? false;
  }

  static Future<void> setHomeCwMergedRows(String provider, bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('$_homeCwMergedRowsKeyPrefix$provider', value);
  }

  static Future<String> getHomeFavoritesTapAction() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeFavoritesOpenFolderKey) ?? 'choose';
  }

  static Future<void> setHomeFavoritesTapAction(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_homeFavoritesOpenFolderKey, value);
  }

  /// Landscape is the DEFAULT (since 0.8.4): the absence of the key means
  /// landscape, so only an explicit 'portrait' choice reads as portrait.
  static Future<HomeCardOrientation> getHomeCardOrientation() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getString(_homeCardOrientationKey) == 'portrait'
        ? HomeCardOrientation.portrait
        : HomeCardOrientation.landscape;
  }

  static Future<void> setHomeCardOrientation(
    HomeCardOrientation orientation,
  ) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_homeCardOrientationKey, orientation.name);
  }

  static Future<void> clearAllHomePageSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_homeDefaultSourceTypeKey);
    await prefs.remove(_homeDefaultAddonUrlKey);
    await prefs.remove(_homeDefaultCatalogIdKey);
    await prefs.remove(_homeHideProviderCardsKey);
    await prefs.remove(_homeContinueWatchingEnabledKey);
    await prefs.remove(_homeCwHoldToQuickPlayKey);
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}local');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}trakt');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}simkl');
    await prefs.remove('${_homeCwMergedRowsKeyPrefix}mdblist');
    await prefs.remove(_homeFavoritesOpenFolderKey);
    await prefs.remove('home_animations_enabled');
    await prefs.remove('home_animation_style');
    await prefs.remove(_homeCardOrientationKey);
    await prefs.remove(HomeAppearanceStorage.homeHideCardTitlesAndRatingsKey);
    await prefs.remove(HomeAppearanceStorage.homeHideCatalogAddonNamesKey);
    await prefs.remove(HomeAppearanceStorage.homeHideCollectionNamesKey);
    await prefs.remove('spotlight_focus_details');
  }
}
