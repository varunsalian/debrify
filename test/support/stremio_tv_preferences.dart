import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Holds the production preference read that discovery waits for. The seeded
/// plugin values and normal writes are preserved; the screen stays untouched.
class StremioTvHeldPreferences extends InMemorySharedPreferencesStore {
  StremioTvHeldPreferences(super.values) : super.withData();
  final ready = Completer<void>();
  final release = Completer<void>();
  int reads = 0;

  static Future<StremioTvHeldPreferences> install() async {
    final held = StremioTvHeldPreferences(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = held;
    return held;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    if (!ready.isCompleted) {
      ready.complete();
    }
    await release.future;
    return super.getAll();
  }
}
