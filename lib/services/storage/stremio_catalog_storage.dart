import 'dart:convert';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/utils/json_isolate.dart';
import 'package:flutter/foundation.dart';

final class StremioCatalogStorage {
  const StremioCatalogStorage._();
  static const String _stremioTvLocalCatalogsKey = 'stremio_tv_local_catalogs_v1';
  static const String _stremioTvCatalogRepoUrlsKey = 'stremio_tv_catalog_repo_urls_v1';

  // ==========================================================================
  // Stremio TV Local Catalogs
  // ==========================================================================

  /// Get all locally imported catalogs for Stremio TV.
  static Future<List<Map<String, dynamic>>> getStremioTvLocalCatalogs() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_stremioTvLocalCatalogsKey);
    if (json == null) return [];

    try {
      final list = await decodeJsonAsync(json) as List<dynamic>;
      return list.whereType<Map<String, dynamic>>().toList();
    } catch (e) {
      debugPrint('Error reading Stremio TV local catalogs: $e');
      return [];
    }
  }

  /// Save all locally imported catalogs for Stremio TV.
  static Future<void> setStremioTvLocalCatalogs(
    List<Map<String, dynamic>> catalogs,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (catalogs.isEmpty) {
      await prefs.remove(_stremioTvLocalCatalogsKey);
    } else {
      await prefs.setString(_stremioTvLocalCatalogsKey, jsonEncode(catalogs));
    }
  }

  /// The picker keeps its captured namespace while waiting for snapshots.
  /// Recheck at the actual commit and propagate persistence/budget refusal.
  static Future<bool> _setStremioTvLocalCatalogsIfCurrent(
    List<Map<String, dynamic>> catalogs,
    bool Function() canContinue,
  ) async {
    if (!canContinue()) return false;
    final prefs = await ProfilePreferences.instance();
    return ProfilePreferences.synchronizeExternalMutation(() async {
      if (!canContinue()) return false;
      return catalogs.isEmpty
          ? await prefs.remove(_stremioTvLocalCatalogsKey)
          : await prefs.setString(
              _stremioTvLocalCatalogsKey,
              jsonEncode(catalogs),
            );
    }, marksMutation: false);
  }

  /// Add a single local catalog. Returns false if a catalog with the same ID
  /// already exists.
  static Future<bool> addStremioTvLocalCatalog(
    Map<String, dynamic> catalog, {
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return false;
    final existing = await getStremioTvLocalCatalogs();
    if (canContinue?.call() == false) return false;
    final id = catalog['id'] as String?;
    if (id == null) return false;
    if (existing.any((c) => c['id'] == id)) return false;
    existing.add(catalog);
    if (canContinue != null) {
      return _setStremioTvLocalCatalogsIfCurrent(existing, canContinue);
    }
    await setStremioTvLocalCatalogs(existing);
    return true;
  }

  /// Remove a local catalog by its ID.
  static Future<void> removeStremioTvLocalCatalog(String catalogId) async {
    final existing = await getStremioTvLocalCatalogs();
    existing.removeWhere((c) => c['id'] == catalogId);
    await setStremioTvLocalCatalogs(existing);
  }

  /// Update an existing local catalog by its ID (replaces the entry in-place).
  static Future<bool> updateStremioTvLocalCatalog(
    Map<String, dynamic> catalog, {
    bool Function()? canContinue,
  }) async {
    if (canContinue?.call() == false) return false;
    final existing = await getStremioTvLocalCatalogs();
    if (canContinue?.call() == false) return false;
    final id = catalog['id'] as String?;
    if (id == null) return false;
    final idx = existing.indexWhere((c) => c['id'] == id);
    if (idx < 0) return false;
    existing[idx] = catalog;
    if (canContinue != null) {
      return _setStremioTvLocalCatalogsIfCurrent(existing, canContinue);
    }
    await setStremioTvLocalCatalogs(existing);
    return true;
  }

  // --------------------------------------------------------------------------
  // Stremio TV Catalog Repo URLs
  // --------------------------------------------------------------------------

  /// Get saved catalog repository URLs.
  static Future<List<String>> getStremioTvCatalogRepoUrls() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getStringList(_stremioTvCatalogRepoUrlsKey) ?? [];
  }

  /// Set catalog repository URLs.
  static Future<void> setStremioTvCatalogRepoUrls(List<String> urls) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setStringList(_stremioTvCatalogRepoUrlsKey, urls);
  }

  /// Add a catalog repository URL. Returns false if already present.
  static Future<bool> addStremioTvCatalogRepoUrl(String url) async {
    final urls = await getStremioTvCatalogRepoUrls();
    if (urls.contains(url)) return false;
    urls.add(url);
    await setStremioTvCatalogRepoUrls(urls);
    return true;
  }

  /// Remove a catalog repository URL.
  static Future<void> removeStremioTvCatalogRepoUrl(String url) async {
    final urls = await getStremioTvCatalogRepoUrls();
    urls.remove(url);
    await setStremioTvCatalogRepoUrls(urls);
  }
}
