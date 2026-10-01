import 'package:debrify/services/profiles/profile_preferences.dart';

final class HomeAppearanceStorage {
  const HomeAppearanceStorage._();
  // Shared within lib/services/storage/.
  static const String homeHideCardTitlesAndRatingsKey = 'home_hide_card_titles_and_ratings';
  // Shared within lib/services/storage/.
  static const String homeHideCatalogAddonNamesKey = 'home_hide_catalog_addon_names';
  // Shared within lib/services/storage/.
  static const String homeHideCollectionNamesKey = 'home_hide_collection_names';

  // Shared within lib/services/storage/.
  static const String tvHomeStyleKey = 'tv_home_style';

  /// Every shipping TV Home layout. 'canvas' is the product default;
  /// 'classic' is the original hero + scrolling rows. The rest are the
  /// alternate stages (see `_buildAtriumBoard` and friends in search_screen).
  ///
  /// Coercion is TOTAL and both ways: a value written by a newer build and
  /// read by an older one — or the long-removed 'shelf' — lands on 'canvas'
  /// rather than rendering nothing.
  static const Set<String> kTvHomeStyles = {
    'canvas',
    'classic',
    'atrium',
    'mosaic',
    'promenade',
    'deck',
    'tonight',
    'spotlight',
  };

  /// TV Home layout. Phone/desktop and the Search tab never read it.
  /// Synchronous mirror of `tvHomeStyle`, kept so a Look can read
  /// the current value without an await. Additive: every existing caller
  /// still goes through the async getter, which now also refreshes this.
  static String tvHomeStyleCached = 'canvas';

  static Future<String> getTvHomeStyle() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(tvHomeStyleKey);
    return tvHomeStyleCached = kTvHomeStyles.contains(raw) ? raw! : 'canvas';
  }

  static Future<void> setTvHomeStyle(String style) async {
    final normalized = kTvHomeStyles.contains(style) ? style : 'canvas';
    // Mirror BEFORE the await, so anything reading synchronously on the next
    // frame sees the choice. Existing async readers are unaffected.
    tvHomeStyleCached = normalized;
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(tvHomeStyleKey, normalized);
  }

  /// Keeps Home artwork clean by suppressing the title and rating painted on
  /// content cards. Row headings, hero identity, progress and context metadata
  /// are separate presentation and remain visible.
  static Future<bool> getHomeHideCardTitlesAndRatings() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(homeHideCardTitlesAndRatingsKey) ?? false;
  }

  static Future<void> setHomeHideCardTitlesAndRatings(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(homeHideCardTitlesAndRatingsKey, value);
  }

  /// Suppresses the source/add-on pill beside Home catalog row headings.
  /// The catalog title itself remains visible so the row keeps its identity.
  static Future<bool> getHomeHideCatalogAddonNames() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(homeHideCatalogAddonNamesKey) ?? false;
  }

  static Future<void> setHomeHideCatalogAddonNames(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(homeHideCatalogAddonNamesKey, value);
  }

  /// Suppresses collection row headings on Home without changing catalog
  /// titles or their add-on provenance labels.
  static Future<bool> getHomeHideCollectionNames() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(homeHideCollectionNamesKey) ?? false;
  }

  static Future<void> setHomeHideCollectionNames(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(homeHideCollectionNamesKey, value);
  }

  static Future<bool> getHomeAnimationsEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('home_animations_enabled') ?? false;
  }

  static Future<void> setHomeAnimationsEnabled(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('home_animations_enabled', value);
  }

  static Future<String> getHomeAnimationStyle() async {
    final prefs = await ProfilePreferences.instance();
    return switch (prefs.getString('home_animation_style')) {
      'midnight_rain' => 'midnight_rain',
      'moonlit_ocean' => 'moonlit_ocean',
      'snowy_mountain' => 'snowy_mountain',
      _ => 'snowy_mountain',
    };
  }

  static Future<void> setHomeAnimationStyle(String value) async {
    if (!const {
      'snowy_mountain',
      'midnight_rain',
      'moonlit_ocean',
    }.contains(value)) {
      throw ArgumentError.value(value);
    }
    final prefs = await ProfilePreferences.instance();
    await prefs.setString('home_animation_style', value);
  }

  static Future<bool> getSpotlightFocusDetails() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('spotlight_focus_details') ?? true;
  }

  static Future<void> setSpotlightFocusDetails(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('spotlight_focus_details', value);
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    tvHomeStyleCached = 'canvas';
  }
}
