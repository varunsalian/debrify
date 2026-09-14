import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/quick_play_rules.dart';
import '../profiles/profile_preferences.dart';

/// Movie/series Quick Play preferences and their legacy compatibility mirrors.
/// StorageService retains the public facade; ProfilePreferences owns scope guards.
class QuickPlayPolicyPrefs {
  QuickPlayPolicyPrefs._();

  static const String _quickPlayHonorsFiltersKey =
      'quick_play_honors_filters_v1';

  static const String _quickPlaySearchTimeoutKey = 'quick_play_search_timeout';

  static const String _stremioSourcesTimeoutKey = 'stremio_sources_timeout';

  // Quick Play Cache Fallback Settings
  // When enabled, if first torrent is not cached, try next torrents until one works
  static const String _quickPlayTryMultipleTorrentsKey =
      'quick_play_try_multiple_torrents';
  static const String _quickPlayMaxRetriesKey = 'quick_play_max_retries';
  static const String _quickPlayMovieRulesKey = 'quick_play_movie_rules_v2';
  static const String _quickPlaySeriesRulesKey = 'quick_play_series_rules_v2';
  static const String _playButtonModeKey = 'play_button_mode';

  // Series auto-pin: on a series play with no pinned source, search packs
  // first (complete series → season pack), and pin whatever source plays so
  // subsequent episode plays go straight through the bound path.
  /// LEGACY MIRROR ONLY. Written by [setQuickPlayRules] to carry
  /// `preferSeriesPacks` for downgrade builds, and read once by
  /// [_quickPlayRulesFromPrefs] to migrate pre-v2 profiles. Nothing on the live
  /// playback path may read it — see [_seriesAutoPinOnPlayKey].
  static const String _autoBindSeriesPacksKey =
      'auto_bind_series_packs_on_play';

  /// Whether a series play pins the source that played. Split out of
  /// [_autoBindSeriesPacksKey] because that key doubles as the legacy mirror of
  /// `preferSeriesPacks`: turning OFF "Prefer season packs" in Quick Play also
  /// silently disabled all series auto-pinning, so Smart mode never found a pin
  /// and Quick Play lost its fast path. Deliberately does NOT inherit the old
  /// key's value — a `false` there was the packs toggle bleeding through, never
  /// an auto-pin choice (no UI ever wrote it directly).
  static const String _seriesAutoPinOnPlayKey = 'series_auto_pin_on_play';

  static Future<bool> getQuickPlayHonorsFilters() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayHonorsFiltersKey) ?? true;
  }

  static Future<void> setQuickPlayHonorsFilters(bool value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayHonorsFiltersKey, value);
  }

  static Future<String> getPlayButtonMode() async {
    final prefs = await ProfilePreferences.instance();
    final raw = prefs.getString(_playButtonModeKey);
    return (raw == 'smart' || raw == 'always') ? raw! : 'quick';
  }

  static Future<void> setPlayButtonMode(String value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(_playButtonModeKey, value);
  }

  static Future<QuickPlayRules> getQuickPlayRules({
    required bool isMovie,
  }) async {
    final prefs = await ProfilePreferences.instance();
    return _quickPlayRulesFromPrefs(prefs, isMovie: isMovie);
  }

  static QuickPlayRules _quickPlayRulesFromPrefs(
    SharedPreferences prefs, {
    required bool isMovie,
  }) {
    final key = isMovie ? _quickPlayMovieRulesKey : _quickPlaySeriesRulesKey;
    final stored = prefs.getString(key);
    if (stored != null) {
      try {
        final decoded = jsonDecode(stored);
        if (decoded is Map<String, dynamic>) {
          return QuickPlayRules.fromJson(decoded, isMovie: isMovie);
        }
        if (decoded is Map) {
          return QuickPlayRules.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
            isMovie: isMovie,
          );
        }
      } catch (e) {
        debugPrint('Invalid Quick Play profile, using legacy values: $e');
      }
    }

    final defaults = QuickPlayRules.debrifyDefault(isMovie: isMovie);
    final migrated = defaults.copyWith(
      preset: QuickPlayPreset.debrifyDefault,
      useFilters: prefs.getBool(_quickPlayHonorsFiltersKey) ?? true,
      tryNextOnFailure: prefs.getBool(_quickPlayTryMultipleTorrentsKey) ?? true,
      maxAttempts: prefs.getInt(_quickPlayMaxRetriesKey) ?? 5,
      preferSeriesPacks:
          !isMovie && (prefs.getBool(_autoBindSeriesPacksKey) ?? true),
    );
    return migrated == defaults
        ? migrated
        : migrated.copyWith(preset: QuickPlayPreset.custom);
  }

  static Future<void> setQuickPlayRules(
    QuickPlayRules rules, {
    required bool isMovie,
  }) async {
    final prefs = await ProfilePreferences.instance();
    final siblingIsMovie = !isMovie;
    final siblingKey = siblingIsMovie
        ? _quickPlayMovieRulesKey
        : _quickPlaySeriesRulesKey;
    // Snapshot an as-yet-unpersisted sibling BEFORE updating the legacy global
    // mirrors below. Otherwise saving Movies first could make a later Series
    // migration inherit the movie retry count (and vice versa).
    final sibling = prefs.containsKey(siblingKey)
        ? null
        : _quickPlayRulesFromPrefs(prefs, isMovie: siblingIsMovie);
    await prefs.setString(
      isMovie ? _quickPlayMovieRulesKey : _quickPlaySeriesRulesKey,
      jsonEncode(rules.toJson()),
    );
    if (sibling != null) {
      await prefs.setString(siblingKey, jsonEncode(sibling.toJson()));
    }

    // Keep old readers and downgrade builds safe. Media-specific values can't
    // be represented perfectly by the legacy global keys, so the active v2
    // playback path never reads these; they are compatibility mirrors only.
    //
    // That invariant was violated once: series auto-pinning read
    // _autoBindSeriesPacksKey, so writing this mirror turned pinning off
    // whenever the user turned off "Prefer season packs". Auto-pin now owns
    // _seriesAutoPinOnPlayKey. Before adding a reader for any key below, check
    // it is genuinely write-only on this path.
    await prefs.setBool(
      _quickPlayTryMultipleTorrentsKey,
      rules.tryNextOnFailure,
    );
    await prefs.setInt(_quickPlayMaxRetriesKey, rules.maxAttempts);
    if (!isMovie) {
      await prefs.setBool(_autoBindSeriesPacksKey, rules.preferSeriesPacks);
    }
  }

  static Future<void> restoreQuickPlayDefaults() async {
    await setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: true),
      isMovie: true,
    );
    await setQuickPlayRules(
      QuickPlayRules.debrifyDefault(isMovie: false),
      isMovie: false,
    );
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayHonorsFiltersKey, true);
    // The page's reset button reads as "reset this page", and this function
    // already resets a non-per-tab key above, so the Play button mode goes back
    // to the shipped Quick Play too. Leaving it would restore defaults while
    // Play kept behaving differently.
    await prefs.remove(_playButtonModeKey);
  }

  static Future<bool> getQuickPlayTryMultipleTorrents() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_quickPlayTryMultipleTorrentsKey) ?? true;
  }

  static Future<void> setQuickPlayTryMultipleTorrents(bool tryMultiple) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_quickPlayTryMultipleTorrentsKey, tryMultiple);
  }

  static Future<bool> getSeriesAutoPinOnPlay() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getBool(_seriesAutoPinOnPlayKey) ?? true;
  }

  static Future<void> setSeriesAutoPinOnPlay(bool enabled) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_seriesAutoPinOnPlayKey, enabled);
  }

  static Future<int> getQuickPlayMaxRetries() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_quickPlayMaxRetriesKey) ?? 5;
  }

  static Future<void> setQuickPlayMaxRetries(int maxRetries) async {
    final prefs = await ProfilePreferences.instance();
    // Clamp between 2 and 10
    await prefs.setInt(_quickPlayMaxRetriesKey, maxRetries.clamp(2, 10));
  }

  static Future<int> getQuickPlaySearchTimeout() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_quickPlaySearchTimeoutKey) ?? 5;
  }

  static Future<void> setQuickPlaySearchTimeout(int seconds) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_quickPlaySearchTimeoutKey, seconds);
  }

  static Future<int> getStremioSourcesTimeout() async {
    final prefs = await ProfilePreferences.instance();
    return prefs.getInt(_stremioSourcesTimeoutKey) ?? 15;
  }

  static Future<void> setStremioSourcesTimeout(int seconds) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.setInt(_stremioSourcesTimeoutKey, seconds);
  }

  static Future<void> clearQuickPlayCacheFallbackSettings() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.remove(_quickPlayTryMultipleTorrentsKey);
    await prefs.remove(_quickPlayMaxRetriesKey);
    await prefs.remove(_quickPlayMovieRulesKey);
    await prefs.remove(_quickPlaySeriesRulesKey);
  }
}
