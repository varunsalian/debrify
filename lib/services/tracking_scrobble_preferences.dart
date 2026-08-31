import '../models/tracking_source.dart';
import 'profiles/profile_preferences.dart';
import 'profiles/profile_scope.dart';

/// Profile-scoped persistence for the master scrobble target set.
///
/// All mutations use [ProfilePreferences.mutateStringListAtomically], so
/// simultaneous tracker connections merge their additions instead of letting
/// the last completed write discard the others.
class TrackingScrobblePreferences {
  TrackingScrobblePreferences._();

  static const String key = 'tracking_scrobble_targets';

  static const Map<TrackingSource, String> _legacyKeys =
      <TrackingSource, String>{
        TrackingSource.trakt: 'trakt_sync_catalog_items',
        TrackingSource.simkl: 'simkl_sync_catalog_items',
        TrackingSource.mdblist: 'mdblist_sync_catalog_items',
      };

  static Future<Set<TrackingSource>> readCurrent() async =>
      _read(await ProfilePreferences.instance());

  static Future<void> writeCurrent(Set<TrackingSource> value) async {
    final prefs = await ProfilePreferences.instance();
    await prefs.mutateStringListAtomically(key, (_) => _encode(value));
  }

  static Future<bool> enableCurrent(TrackingSource source) async =>
      _enable(await ProfilePreferences.instance(), source);

  /// Enables a tracker for the profile that just received a shared singleton
  /// binding. The resource service validates the target before constructing
  /// this captured scope; this access only persists the resulting preference.
  static Future<bool> enableForScope(
    ProfileScope scope,
    TrackingSource source,
  ) async {
    final prefs = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.connectionGrant,
    );
    return _enable(prefs, source);
  }

  static Future<void> reseedCurrentFromLegacy() async {
    final prefs = await ProfilePreferences.instance();
    await prefs.mutateStringListAtomically(
      key,
      (_) => _encode(_seedFromLegacy(prefs)),
    );
  }

  static Future<Set<TrackingSource>> _read(ProfilePreferences prefs) async {
    final stored = prefs.getStringList(key);
    if (stored != null) return _decode(stored);

    late Set<TrackingSource> resolved;
    await prefs.mutateStringListAtomically(key, (latest) {
      if (latest != null) {
        resolved = _decode(latest);
        return null;
      }
      resolved = _seedFromLegacy(prefs);
      return _encode(resolved);
    });
    return resolved;
  }

  static Future<bool> _enable(
    ProfilePreferences prefs,
    TrackingSource source,
  ) async {
    var changed = false;
    await prefs.mutateStringListAtomically(key, (stored) {
      final current = stored == null ? _seedFromLegacy(prefs) : _decode(stored);
      if (current.contains(source)) {
        // An absent key still needs its one-time migration seed persisted.
        return stored == null ? _encode(current) : null;
      }
      current.add(source);
      changed = true;
      return _encode(current);
    });
    return changed;
  }

  static Set<TrackingSource> _seedFromLegacy(ProfilePreferences prefs) {
    final seeded = <TrackingSource>{TrackingSource.local};
    for (final entry in _legacyKeys.entries) {
      if (!prefs.containsKey(entry.value) ||
          (prefs.getBool(entry.value) ?? true)) {
        seeded.add(entry.key);
      }
    }
    return seeded;
  }

  static Set<TrackingSource> _decode(List<String> stored) => <TrackingSource>{
    TrackingSource.local,
    for (final value in stored)
      if (TrackingSourceStorageName.parse(value) case final source?) source,
  };

  static List<String> _encode(Set<TrackingSource> value) => <String>[
    for (final source in TrackingSource.values)
      if (source == TrackingSource.local || value.contains(source))
        source.storageName,
  ];
}
