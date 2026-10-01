import 'dart:convert';
import 'package:debrify/models/home_preferences.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter/foundation.dart';

final class HomeHeroStorage {
  const HomeHeroStorage._();

  static const String _homeHeroSourceKey = 'home_hero_source_v1';

  /// Where the Spotlight home layout's hero reel comes from.
  ///
  /// Modes: `random` (the DEFAULT — "Surprise me": any installed browsable
  /// catalog, re-rolled each board load), `auto` (the first non-empty board
  /// row) and `custom` (one of [HomeHeroSource.ids], catalog leaves in the
  /// Home Rows grammar `addonId:type:catalogId`; more than one re-rolls among
  /// them each load). Unknown modes and a custom mode with no ids read back
  /// as `random` so a bad write can never wedge the hero. `auto` is an
  /// explicit choice now, so it is STORED — only the default removes the key.
  static Future<HomeHeroSource> getHomeHeroSource() async {
    const fallback = (mode: HomeHeroSourceMode.random, ids: <String>[]);
    final prefs = await ProfilePreferences.instance();
    final json = prefs.getString(_homeHeroSourceKey);
    if (json == null) return fallback;
    try {
      final map = jsonDecode(json) as Map<String, dynamic>;
      final ids = <String>[];
      final seen = <String>{};
      final rawIds = map['ids'];
      if (rawIds is List) {
        for (final e in rawIds) {
          if (e is String && e.isNotEmpty && seen.add(e)) ids.add(e);
        }
      }
      final mode = switch (map['mode']) {
        'auto' => HomeHeroSourceMode.auto,
        'custom' when ids.isNotEmpty => HomeHeroSourceMode.custom,
        _ => HomeHeroSourceMode.random,
      };
      return (mode: mode, ids: ids);
    } catch (e) {
      debugPrint('Error reading home hero source: $e');
      return fallback;
    }
  }

  /// Save the Spotlight hero source (the default `random` + no ids = key
  /// removed; `auto` is stored, or it would read back as the default).
  static Future<void> setHomeHeroSource(HomeHeroSource source) async {
    final prefs = await ProfilePreferences.instance();
    if (source.mode == HomeHeroSourceMode.random && source.ids.isEmpty) {
      await prefs.remove(_homeHeroSourceKey);
    } else {
      await prefs.setString(
        _homeHeroSourceKey,
        jsonEncode({'mode': source.mode.name, 'ids': source.ids}),
      );
    }
  }
}
