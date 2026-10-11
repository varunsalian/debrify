import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved interface; application dependencies stay frozen.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Hold the existing preferences transport before the original async loads.
class SkipSettingsReads extends InMemorySharedPreferencesStore {
  SkipSettingsReads(super.values) : super.withData();
  final release = Completer<void>();
  bool entered = false;

  static Future<SkipSettingsReads> install() async {
    final store = SkipSettingsReads(
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
}
