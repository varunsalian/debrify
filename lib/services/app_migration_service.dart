import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'stremio_service.dart';

/// Service for running app migrations on fresh install or update.
///
/// This service tracks the app version and runs necessary migrations
/// when the version changes (fresh install or update).
class AppMigrationService {
  static const String _lastVersionKey = 'app_last_version';
  static const String _lastBuildNumberKey = 'app_last_build_number';

  /// Set once an essential addon has been confirmed present at least once
  /// (either we added it, or the user already had it). After that we never
  /// auto-add it again, so a deliberate removal by the user is respected.
  /// Until then we keep retrying every launch — this self-heals the case
  /// where the very first launch was offline / the addon was unreachable.
  static const String _cinemetaSeededKey = 'essential_addon_cinemeta_seeded';
  static const String _openSubtitlesSeededKey =
      'essential_addon_opensubtitles_seeded';
  static const String _watchNextSeededKey =
      'essential_addon_watch_next_seeded';

  /// Cinemeta addon manifest URL - provides metadata for movies and shows
  static const String cinemetaManifestUrl =
      'https://v3-cinemeta.strem.io/manifest.json';

  /// OpenSubtitles addon manifest URL - provides subtitles for movies and shows
  static const String openSubtitlesManifestUrl =
      'https://opensubtitlesv3-pro.dexter21767.com/eyJsYW5ncyI6WyJlbmdsaXNoIl0sInNvdXJjZSI6ImFsbCIsImFpVHJhbnNsYXRlZCI6dHJ1ZSwiYXV0b0FkanVzdG1lbnQiOmZhbHNlfQ==/manifest.json';

  /// Watch Next addon manifest URL - provides "watch next" recommendations
  static const String watchNextManifestUrl =
      'https://099757617587-watch-next.baby-beamup.club/manifest.json';

  /// Run all necessary migrations based on version change.
  ///
  /// Call this during app initialization, before showing the main UI.
  /// Returns true if version-gated migrations were run, false otherwise.
  static Future<bool> runMigrations() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Essential addons are seeded independently of the version gate: a
      // user whose first launch was offline must still get Cinemeta once
      // they're back online, even though the version hasn't changed. The
      // per-addon "seeded" flag (set only once the addon is confirmed
      // present) stops us from ever re-adding one the user removed.
      await _ensureEssentialAddons(prefs);

      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;
      final currentBuildNumber = packageInfo.buildNumber;

      final lastVersion = prefs.getString(_lastVersionKey);
      final lastBuildNumber = prefs.getString(_lastBuildNumberKey);

      debugPrint(
        'AppMigrationService: Current version: $currentVersion+$currentBuildNumber, '
        'Last version: $lastVersion+$lastBuildNumber',
      );

      // Check if this is a fresh install or version change
      final isFreshInstall = lastVersion == null;
      final isVersionChange = lastVersion != currentVersion ||
          lastBuildNumber != currentBuildNumber;

      if (!isFreshInstall && !isVersionChange) {
        debugPrint('AppMigrationService: No version-gated migration needed');
        return false;
      }

      debugPrint(
        'AppMigrationService: Running migrations '
        '(freshInstall: $isFreshInstall, versionChange: $isVersionChange)',
      );

      // Run version-gated migrations
      await _runAllMigrations(isFreshInstall: isFreshInstall);

      // Update stored version
      await prefs.setString(_lastVersionKey, currentVersion);
      await prefs.setString(_lastBuildNumberKey, currentBuildNumber);

      debugPrint('AppMigrationService: Migrations complete');
      return true;
    } catch (e) {
      debugPrint('AppMigrationService: Error running migrations: $e');
      return false;
    }
  }

  /// Run version-gated migration tasks (one-time data migrations tied to an
  /// app update). Essential-addon seeding is intentionally NOT here — it runs
  /// every launch via [_ensureEssentialAddons] until it succeeds once.
  static Future<void> _runAllMigrations({required bool isFreshInstall}) async {
    // No version-gated migrations at present.
  }

  /// Seed the essential addons that the app needs to function. Runs on every
  /// launch but is a cheap no-op once each addon has been seeded once.
  static Future<void> _ensureEssentialAddons(SharedPreferences prefs) async {
    await _ensureCinemetaAddon(prefs);
    await _ensureOpenSubtitlesAddon(prefs);
    await _ensureWatchNextAddon(prefs);
  }

  /// Ensure Cinemeta addon is installed.
  ///
  /// Cinemeta provides metadata (posters, descriptions, cast info) for
  /// movies and TV shows. It's essential for the app to function properly.
  static Future<void> _ensureCinemetaAddon(SharedPreferences prefs) async {
    // Already seeded once — never auto-add again (respects user removal).
    if (prefs.getBool(_cinemetaSeededKey) ?? false) return;

    try {
      final stremioService = StremioService.instance;
      final addons = await stremioService.getAddons();

      // Check if Cinemeta is already installed (by manifest URL or ID)
      final hasCinemeta = addons.any((addon) =>
          addon.manifestUrl == cinemetaManifestUrl ||
          addon.id == 'cinemeta' ||
          addon.id == 'com.stremio.cinemeta');

      if (hasCinemeta) {
        debugPrint('AppMigrationService: Cinemeta addon already installed');
        await prefs.setBool(_cinemetaSeededKey, true);
        return;
      }

      // Add Cinemeta addon
      debugPrint('AppMigrationService: Adding Cinemeta addon...');
      final addon = await stremioService.addAddon(cinemetaManifestUrl);
      debugPrint('AppMigrationService: Cinemeta addon added: ${addon.name}');
      // Only mark seeded on a confirmed success, so an offline/unreachable
      // first launch is retried on the next launch instead of silently
      // leaving the user without metadata until the next app update.
      await prefs.setBool(_cinemetaSeededKey, true);
    } catch (e) {
      // Don't fail migration if addon can't be added (network issues, etc.).
      // Leave the seeded flag unset so we retry next launch.
      debugPrint('AppMigrationService: Failed to add Cinemeta addon: $e');
    }
  }

  /// Ensure OpenSubtitles addon is installed.
  ///
  /// OpenSubtitles provides subtitles for movies and TV shows.
  static Future<void> _ensureOpenSubtitlesAddon(SharedPreferences prefs) async {
    // Already seeded once — never auto-add again (respects user removal).
    if (prefs.getBool(_openSubtitlesSeededKey) ?? false) return;

    try {
      final stremioService = StremioService.instance;
      final addons = await stremioService.getAddons();

      // Check if OpenSubtitles is already installed (by ID pattern)
      final hasOpenSubtitles = addons.any((addon) =>
          addon.manifestUrl == openSubtitlesManifestUrl ||
          addon.id.toLowerCase().contains('opensubtitles'));

      if (hasOpenSubtitles) {
        debugPrint('AppMigrationService: OpenSubtitles addon already installed');
        await prefs.setBool(_openSubtitlesSeededKey, true);
        return;
      }

      // Add OpenSubtitles addon
      debugPrint('AppMigrationService: Adding OpenSubtitles addon...');
      final addon = await stremioService.addAddon(openSubtitlesManifestUrl);
      debugPrint('AppMigrationService: OpenSubtitles addon added: ${addon.name}');
      await prefs.setBool(_openSubtitlesSeededKey, true);
    } catch (e) {
      // Don't fail migration if addon can't be added (network issues, etc.).
      // Leave the seeded flag unset so we retry next launch.
      debugPrint('AppMigrationService: Failed to add OpenSubtitles addon: $e');
    }
  }

  /// Ensure the Watch Next addon is installed.
  ///
  /// Provides "watch next" recommendations on the detail screen.
  static Future<void> _ensureWatchNextAddon(SharedPreferences prefs) async {
    // Already seeded once — never auto-add again (respects user removal).
    if (prefs.getBool(_watchNextSeededKey) ?? false) return;

    try {
      final stremioService = StremioService.instance;
      final addons = await stremioService.getAddons();

      // Check if Watch Next is already installed (by manifest URL or ID)
      final hasWatchNext = addons.any((addon) =>
          addon.manifestUrl == watchNextManifestUrl ||
          addon.id == 'community.watch.next');

      if (hasWatchNext) {
        debugPrint('AppMigrationService: Watch Next addon already installed');
        await prefs.setBool(_watchNextSeededKey, true);
        return;
      }

      // Add Watch Next addon
      debugPrint('AppMigrationService: Adding Watch Next addon...');
      final addon = await stremioService.addAddon(watchNextManifestUrl);
      debugPrint('AppMigrationService: Watch Next addon added: ${addon.name}');
      await prefs.setBool(_watchNextSeededKey, true);
    } catch (e) {
      // Don't fail migration if addon can't be added (network issues, etc.).
      // Leave the seeded flag unset so we retry next launch.
      debugPrint('AppMigrationService: Failed to add Watch Next addon: $e');
    }
  }
}
