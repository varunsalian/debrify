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

  /// Cinemeta addon manifest URL - provides metadata for movies and shows
  static const String cinemetaManifestUrl =
      'https://v3-cinemeta.strem.io/manifest.json';

  /// OpenSubtitles addon manifest URL - provides subtitles for movies and shows
  static const String openSubtitlesManifestUrl =
      'https://opensubtitlesv3-pro.dexter21767.com/eyJsYW5ncyI6WyJlbmdsaXNoIl0sInNvdXJjZSI6ImFsbCIsImFpVHJhbnNsYXRlZCI6dHJ1ZSwiYXV0b0FkanVzdG1lbnQiOmZhbHNlfQ==/manifest.json';

  /// Run all necessary migrations based on version change.
  ///
  /// Call this during app initialization, before showing the main UI.
  /// Returns true if migrations were run, false if already up to date.
  static Future<bool> runMigrations() async {
    try {
      final prefs = await SharedPreferences.getInstance();
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
        debugPrint('AppMigrationService: No migration needed');
        return false;
      }

      debugPrint(
        'AppMigrationService: Running migrations '
        '(freshInstall: $isFreshInstall, versionChange: $isVersionChange)',
      );

      // Run migrations
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

  /// Run all migration tasks
  static Future<void> _runAllMigrations({required bool isFreshInstall}) async {
    // Migration 1: Auto-add essential addons
    await _ensureCinemetaAddon();
    await _ensureOpenSubtitlesAddon();
  }

  /// Ensure Cinemeta addon is installed.
  ///
  /// Cinemeta provides metadata (posters, descriptions, cast info) for
  /// movies and TV shows. It's essential for the app to function properly.
  static Future<void> _ensureCinemetaAddon() async {
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
        return;
      }

      // Add Cinemeta addon
      debugPrint('AppMigrationService: Adding Cinemeta addon...');
      final addon = await stremioService.addAddon(cinemetaManifestUrl);
      debugPrint('AppMigrationService: Cinemeta addon added: ${addon.name}');
    } catch (e) {
      // Don't fail migration if addon can't be added (network issues, etc.)
      debugPrint('AppMigrationService: Failed to add Cinemeta addon: $e');
    }
  }

  /// Ensure OpenSubtitles addon is installed.
  ///
  /// OpenSubtitles provides subtitles for movies and TV shows.
  static Future<void> _ensureOpenSubtitlesAddon() async {
    try {
      final stremioService = StremioService.instance;
      final addons = await stremioService.getAddons();

      // Check if OpenSubtitles is already installed (by ID pattern)
      final hasOpenSubtitles = addons.any((addon) =>
          addon.manifestUrl == openSubtitlesManifestUrl ||
          addon.id.toLowerCase().contains('opensubtitles'));

      if (hasOpenSubtitles) {
        debugPrint('AppMigrationService: OpenSubtitles addon already installed');
        return;
      }

      // Add OpenSubtitles addon
      debugPrint('AppMigrationService: Adding OpenSubtitles addon...');
      final addon = await stremioService.addAddon(openSubtitlesManifestUrl);
      debugPrint('AppMigrationService: OpenSubtitles addon added: ${addon.name}');
    } catch (e) {
      // Don't fail migration if addon can't be added (network issues, etc.)
      debugPrint('AppMigrationService: Failed to add OpenSubtitles addon: $e');
    }
  }
}
