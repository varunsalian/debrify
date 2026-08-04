import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

/// Remembered Sort selections for the Discover tab.
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
/// panel can apply the remembered order in `initState` and paint the first
/// frame already sorted (no visible re-order a frame later). A cold cache — or
/// any storage failure — simply means the panel opens on its default sort.
class DiscoverPrefs {
  static const String _prefix = 'discover_sort_';

  // Source keys. Persisted, so never rename one without a migration.
  static const String cw = 'cw';
  static const String trakt = 'trakt';
  static const String simkl = 'simkl';
  static const String mdblist = 'mdblist';
  static const String catalog = 'catalog';

  static const List<String> _sources = [cw, trakt, simkl, mdblist, catalog];

  static final Map<String, String> _cache = {};
  static bool _warmed = false;

  /// Load every remembered sort into the cache. Called once from `main()`;
  /// repeat calls are no-ops.
  static Future<void> warmUp() async {
    if (_warmed) return;
    _warmed = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final source in _sources) {
        final id = prefs.getString('$_prefix$source');
        if (id != null) _cache[source] = id;
      }
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
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$source', id);
    } catch (_) {
      // Best-effort: the choice still holds for this session.
    }
  }

  /// Remember an enum sort by its [Enum.name] — the id the enum overloads of
  /// [enumSortFor] read back.
  static Future<void> setEnumSort(String source, Enum value) =>
      setSort(source, value.name);

  /// Drop the cache so the next [warmUp] re-reads storage — tests only (it
  /// stands in for an app restart).
  @visibleForTesting
  static void debugReset() {
    _cache.clear();
    _warmed = false;
  }
}
