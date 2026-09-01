import 'package:flutter/foundation.dart' show visibleForTesting;
import 'profiles/profile_preferences.dart';

/// Synchronously cached preferences for the Discover tab.
///
/// Discover is a Source dropdown over a swappable See-All panel, and each panel
/// used to open on its own default order every time — so a user who browses
/// Trakt by "IMDb Rating · High → Low" had to re-pick it on every launch (and on
/// every source swap, since swapping re-mounts the panel).
///
/// The sort is stored per SOURCE, not globally: Continue Watching sorted A–Z
/// says nothing about how the user wants an addon catalog ordered. Every addon
/// catalog shares the one [catalog] slot on purpose — the panel itself already
/// treats Sort as a preference that survives type/catalog/genre edits rather
/// than as a per-catalog filter.
///
/// Reads are synchronous off a cache warmed in `main()` before `runApp`, so a
/// panel can apply the remembered order and card chrome before its first frame
/// (no visible re-order or badge flash). A cold cache — or any storage failure
/// — simply means the panel opens on its default sort with card details shown.
class DiscoverPrefs {
  static const String _prefix = 'discover_sort_';
  static const String _showTypeTagsKey = 'discover_show_type_tags';
  static const String _showRatingsKey = 'discover_show_ratings';
  static const String _showTitlesKey = 'discover_show_titles';

  // Source keys. Persisted, so never rename one without a migration.
  static const String cw = 'cw';
  static const String trakt = 'trakt';
  static const String simkl = 'simkl';
  static const String mdblist = 'mdblist';
  static const String catalog = 'catalog';

  static const List<String> _sources = [cw, trakt, simkl, mdblist, catalog];

  static final Map<String, String> _cache = {};
  static bool _showTypeTags = true;
  static bool _showRatings = true;
  static bool _showTitles = true;
  static bool _warmed = false;

  /// Load every Discover preference into the cache. Called once from `main()`;
  /// repeat calls are no-ops.
  static Future<void> warmUp() async {
    if (_warmed) return;
    _warmed = true;
    try {
      final prefs = await ProfilePreferences.instance();
      for (final source in _sources) {
        final id = prefs.getString('$_prefix$source');
        if (id != null) _cache[source] = id;
      }
      _showTypeTags = prefs.getBool(_showTypeTagsKey) ?? true;
      _showRatings = prefs.getBool(_showRatingsKey) ?? true;
      _showTitles = prefs.getBool(_showTitlesKey) ?? true;
    } catch (_) {
      // Storage unavailable — Discover just opens on its default sorts.
    }
  }

  /// The remembered sort id for [source], or null if the user has never picked
  /// one there.
  static String? sortFor(String source) => _cache[source];

  /// The remembered sort for [source] resolved against an enum's [values], or
  /// null when nothing is stored or the stored id is no longer a valid option
  /// (an enum value dropped in a later release).
  static T? enumSortFor<T extends Enum>(String source, List<T> values) {
    final id = _cache[source];
    if (id == null) return null;
    for (final value in values) {
      if (value.name == id) return value;
    }
    return null;
  }

  /// Remember [id] as [source]'s sort. Cache-first so the next panel mount sees
  /// it even if the disk write is still in flight.
  static Future<void> setSort(String source, String id) async {
    _cache[source] = id;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setString('$_prefix$source', id);
    } catch (_) {
      // Best-effort: the choice still holds for this session.
    }
  }

  /// Remember an enum sort by its [Enum.name] — the id the enum overloads of
  /// [enumSortFor] read back.
  static Future<void> setEnumSort(String source, Enum value) =>
      setSort(source, value.name);

  /// Whether Discover poster cards show their MOVIE/SERIES tag. Unset is on,
  /// so existing profiles keep the information visible.
  static bool get showTypeTags => _showTypeTags;

  /// Whether Discover poster cards show their rating chip. Unset is on.
  static bool get showRatings => _showRatings;

  /// Whether poster walls opened from Discover or a Home row show the title
  /// beneath each poster. Unset is on so existing profiles keep their current
  /// presentation until they explicitly hide it.
  static bool get showTitles => _showTitles;

  static Future<void> setShowTypeTags(bool value) async {
    _showTypeTags = value;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(_showTypeTagsKey, value);
    } catch (_) {
      // Best-effort: the choice still holds for this session.
    }
  }

  static Future<void> setShowRatings(bool value) async {
    _showRatings = value;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(_showRatingsKey, value);
    } catch (_) {
      // Best-effort: the choice still holds for this session.
    }
  }

  static Future<void> setShowTitles(bool value) async {
    _showTitles = value;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(_showTitlesKey, value);
    } catch (_) {
      // Best-effort: the choice still holds for this session.
    }
  }

  static void resetProfileScope() {
    _cache.clear();
    _showTypeTags = true;
    _showRatings = true;
    _showTitles = true;
    _warmed = false;
  }

  /// Drop the cache so the next [warmUp] re-reads storage — tests only (it
  /// stands in for an app restart).
  @visibleForTesting
  static void debugReset() {
    resetProfileScope();
  }
}
