import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Hold the real preferences load used by _loadPlayerDefaults. Other startup
/// readers share that pending load, rather than receiving invented defaults.
class DisplayDefaultsReads extends InMemorySharedPreferencesStore {
  DisplayDefaultsReads(super.values) : super.withData();

  final release = Completer<void>();
  final writes = <(String, Object)>[];
  bool entered = false;

  static Future<DisplayDefaultsReads> install() async {
    final store = DisplayDefaultsReads(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    entered = true;
    await release.future;
    return super.getAll();
  }

  @override
  Future<bool> setValue(String type, String key, Object value) async {
    writes.add((key, value));
    return super.setValue(type, key, value);
  }

  void unblock() {
    if (!release.isCompleted) release.complete();
  }
}
