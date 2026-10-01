import 'dart:convert';
import 'package:debrify/models/home_collection.dart';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter/foundation.dart';

final class HomeRowsStorage {
  const HomeRowsStorage._();

  static const String _homeDisabledSectionsKey = 'home_disabled_sections_v1';

  /// Get the set of Home-row IDs the user has hidden via the Home Page manager
  /// (empty = every row shown). IDs are fixed-section leaves (e.g. `cw:movies`,
  /// `trakt:shows`, `fav:iptv`) and catalog leaves (`addonId:type:catalogId`).
  static Future<Set<String>> getHomeDisabledSections() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeDisabledSectionsKey);
    if (json == null) return {};
    try {
      final list = jsonDecode(json) as List<dynamic>;
      final disabled = list.cast<String>().toSet();
      final rows = disabled.where((id) => !HomeCollectionRowIds.isFolderList(id)).toSet();
      // Folder-list controls were retired; migrate their hidden flags away.
      if (rows.length != disabled.length) {
        if (rows.isEmpty) {
          await prefs.remove(_homeDisabledSectionsKey);
        } else {
          await prefs.setString(
            _homeDisabledSectionsKey,
            jsonEncode(rows.toList()),
          );
        }
      }
      return rows;
    } catch (e) {
      debugPrint('Error reading home disabled sections: $e');
      return {};
    }
  }

  /// Save the set of hidden Home-row IDs.
  static Future<void> setHomeDisabledSections(Set<String> disabled) async {
    final prefs = await ProfilePreferences.instance();
    final rows = disabled.where((id) => !HomeCollectionRowIds.isFolderList(id)).toSet();
    if (rows.isEmpty) {
      await prefs.remove(_homeDisabledSectionsKey);
    } else {
      await prefs.setString(
        _homeDisabledSectionsKey,
        jsonEncode(rows.toList()),
      );
    }
  }

  static const String _homeExtraRowsKey = 'home_extra_rows_v1';

  /// The OPT-IN extra Home rows (default-off, so the disabled-set above can't
  /// express them): Trakt/Simkl list rows and IPTV custom-list rows. IDs are
  /// `traktlist:<apiValue>`, `traktlist:custom:<id>`, `traktlist:liked:<id>`,
  /// `simkllist:<enumName>`, `iptvlist:<listId>`. [HomeExtraRow.title] is the
  /// display name captured at opt-in time so dynamic rows (custom/liked
  /// lists, IPTV lists) render a header instantly and stay representable in
  /// the Home Rows manager through an API outage; built-in rows ignore it.
  /// Order is NOT meaningful — the board renders extras in canonical order.
  static Future<List<HomeExtraRow>> getHomeExtraRows() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeExtraRowsKey);
    if (json == null) return const [];
    try {
      final list = jsonDecode(json) as List<dynamic>;
      final seen = <String>{};
      final out = <HomeExtraRow>[];
      for (final e in list) {
        if (e is! Map) continue;
        final id = e['id'];
        if (id is! String || id.isEmpty || !seen.add(id)) continue;
        final title = e['title'];
        out.add((id: id, title: title is String ? title : ''));
      }
      return out;
    } catch (e) {
      debugPrint('Error reading home extra rows: $e');
      return const [];
    }
  }

  /// Save the opted-in extra Home rows (empty = key removed).
  static Future<void> setHomeExtraRows(List<HomeExtraRow> rows) async {
    final prefs = await ProfilePreferences.instance();
    if (rows.isEmpty) {
      await prefs.remove(_homeExtraRowsKey);
    } else {
      await prefs.setString(
        _homeExtraRowsKey,
        jsonEncode([
          for (final r in rows) {'id': r.id, 'title': r.title},
        ]),
      );
    }
  }

  static const String _homeRowOrderKey = 'home_row_order_v1';

  /// The user's global Home-row order, expressed with the same stable ids used
  /// by the Home Rows manager. Missing/unavailable ids remain in this list so
  /// reconnecting a tracker or reinstalling an addon restores its old slot.
  /// An empty list means the board's canonical order.
  static Future<List<String>> getHomeRowOrder() async {
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeRowOrderKey);
    if (json == null) return const [];
    try {
      final raw = jsonDecode(json);
      if (raw is! List) return const [];
      final seen = <String>{};
      return [
        for (final value in raw)
          if (value is String && value.isNotEmpty && seen.add(value)) value,
      ];
    } catch (e) {
      debugPrint('Error reading home row order: $e');
      return const [];
    }
  }

  /// Save the user's global Home-row order. Empty restores canonical order.
  static Future<void> setHomeRowOrder(List<String> order) async {
    final prefs = await ProfilePreferences.instance();
    final seen = <String>{};
    final normalized = [
      for (final id in order)
        if (id.isNotEmpty && seen.add(id)) id,
    ];
    if (normalized.isEmpty) {
      await prefs.remove(_homeRowOrderKey);
    } else {
      await prefs.setString(_homeRowOrderKey, jsonEncode(normalized));
    }
  }
}
