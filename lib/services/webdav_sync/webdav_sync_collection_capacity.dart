import 'package:shared_preferences/shared_preferences.dart';

import '../../models/home_collection_inventory.dart';
import '../profiles/profile_preference_budget.dart';
import '../engine/local_engine_storage.dart';

/// Collection capacity cannot hold resume/watched updates hostage on tvOS.
/// The engine retains the complete target and the unchanged local snapshot.
abstract final class WebDavSyncCollectionCapacity {
  static ({Map<String, Object> values, bool collectionsDeferred}) plan(
    SharedPreferences prefs,
    String prefix,
    Map<String, Object> values,
  ) {
    const key = HomeCollectionInventory.prefsKey;
    const notice = HomeCollectionInventory.syncDeferredKey;
    if (!ProfilePreferenceBudget.enforced || !values.containsKey(key)) {
      return (
        values: {
          ...values,
          if (prefs.getBool('$prefix$notice') == true) notice: false,
        },
        collectionsDeferred: false,
      );
    }
    bool fits(Map<String, Object> candidate) {
      var bytes = ProfilePreferenceBudget.measure(prefs);
      final deltas = <int>[];
      for (final e in candidate.entries) {
        if (e.key.startsWith(LocalEngineStorage.definitionPrefix)) continue;
        final physical = '$prefix${e.key}';
        deltas.add(
          ProfilePreferenceBudget.entryFootprint(physical, e.value) -
              (prefs.containsKey(physical)
                  ? ProfilePreferenceBudget.entryFootprint(
                      physical,
                      prefs.get(physical),
                    )
                  : 0),
        );
      }
      deltas.sort();
      for (final delta in deltas) {
        if (!ProfilePreferenceBudget.admitsProjectedDelta(
          currentBytes: bytes,
          deltaBytes: delta,
        )) {
          return false;
        }
        bytes += delta;
      }
      return true;
    }

    final complete = {
      ...values,
      if (prefs.getBool('$prefix$notice') == true) notice: false,
    };
    if (fits(complete)) return (values: complete, collectionsDeferred: false);
    final deferred = {...values}..remove(key);
    deferred[notice] = true;
    // Other over-capacity hot state still uses the normal failure/retry path.
    // Only a collection-induced failure is isolated here.
    if (!fits(deferred)) return (values: values, collectionsDeferred: false);
    return (values: deferred, collectionsDeferred: true);
  }
}
