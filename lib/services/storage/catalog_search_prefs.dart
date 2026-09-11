import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../profiles/profile_preferences.dart';

/// Profile-scoped Search addon exclusions; runtime/source selection stays with callers.
class CatalogSearchPrefs {
  CatalogSearchPrefs._();

  static const String _catalogSearchDisabledAddonsKey =
      'catalog_search_disabled_addons_v1';

  static const Set<String> ownedKeys = {_catalogSearchDisabledAddonsKey};

  /// Get the set of addon IDs the user has DISABLED for catalog search on the
  /// Search tab (empty = every searchable addon is queried).
  static Future<Set<String>> getCatalogSearchDisabledAddons() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_catalogSearchDisabledAddonsKey);
    if (json == null) return {};
    try {
      final list = jsonDecode(json) as List<dynamic>;
      return list.cast<String>().toSet();
    } catch (e) {
      debugPrint('Error reading catalog search disabled addons: $e');
      return {};
    }
  }

  /// Save the set of addon IDs disabled for catalog search.
  static Future<void> setCatalogSearchDisabledAddons(
    Set<String> disabled,
  ) async {
    final prefs = await ProfilePreferences.instance();
    if (disabled.isEmpty) {
      await prefs.remove(_catalogSearchDisabledAddonsKey);
    } else {
      await prefs.setString(
        _catalogSearchDisabledAddonsKey,
        jsonEncode(disabled.toList()),
      );
    }
  }
}
