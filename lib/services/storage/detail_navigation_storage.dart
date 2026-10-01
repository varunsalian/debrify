import 'package:debrify/services/profiles/profile_preferences.dart';

final class DetailNavigationStorage {
  const DetailNavigationStorage._();

  static Future<bool> getSeriesBrowserDenseView() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('series_browser_dense_view') ?? false;
  }

  static Future<void> setSeriesBrowserDenseView(bool dense) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('series_browser_dense_view', dense);
  }

  /// Route series & movies to the merged detail+episodes page (the Stremio-styled
  /// single screen) instead of the separate detail → episodes flow. On by
  /// default; can be turned off per-device via [setMergedSeriesPageEnabled].
  static Future<bool> getMergedSeriesPageEnabled() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool('merged_series_page_enabled') ?? true;
  }

  static Future<void> setMergedSeriesPageEnabled(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool('merged_series_page_enabled', enabled);
  }
}
