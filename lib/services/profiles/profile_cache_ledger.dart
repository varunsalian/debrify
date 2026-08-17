import 'package:flutter/foundation.dart';

import 'profile_scope.dart';

/// Records which profile scope each process-global cache was last warmed for.
///
/// Nothing else in the app knows this. Singletons that survive a profile switch
/// expose a `resetProfileScope()`/`clearCache()` and nothing more, so "is this
/// cache serving the profile that is actually active?" was a question only
/// answerable by reading the switch path line by line — which is exactly why
/// `EngineRegistry` served one profile's torrent engines to another for as long
/// as it did.
///
/// **Stamped per group as the warm proceeds, never in one call at the end.**
/// That ordering is the whole diagnostic: if warming throws partway, every
/// group after the throw keeps its previous stamp, and a stale stamp is the
/// signature of the leak. A single stamp at the end would report success for
/// caches that were never touched.
///
/// Deliberately dumb: a `Map<String, String>` and no listeners. It observes the
/// lifecycle, it must never influence it.
abstract final class ProfileCacheLedger {
  static final Map<String, String> _stamps = <String, String>{};

  /// The canonical scope key, delegating to [ProfileScope.cacheKey] so that
  /// every producer of a scope key uses one definition.
  ///
  /// This used to build the string itself and claim it matched the shape
  /// `EngineRegistry` uses. It did not — see [ProfileScope.cacheKey].
  static String keyFor(ProfileScope scope) => scope.cacheKey;

  static void stamp(String name, ProfileScope scope) {
    _stamps[name] = keyFor(scope);
  }

  /// Records a cache that reports its own scope rather than being stamped —
  /// [EngineRegistry] tracks a real `_loadedScopeKey`, so its row is measured
  /// rather than declared.
  static void stampRaw(String name, String? scopeKey) {
    _stamps[name] = scopeKey ?? 'unloaded';
  }

  static Map<String, String> snapshot() => Map<String, String>.unmodifiable(
    Map<String, String>.fromEntries(
      _stamps.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
  );

  @visibleForTesting
  static void debugReset() => _stamps.clear();
}
