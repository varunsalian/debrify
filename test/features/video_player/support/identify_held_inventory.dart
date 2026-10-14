import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved test transport, app dependencies unchanged.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'vp_fixture_actions.dart';

/// Only the first physical preferences read is held and fails. A fresh public
/// preferences load can succeed while the original getter remains pending.
class IdentifyHeldInventory extends InMemorySharedPreferencesStore {
  IdentifyHeldInventory(super.values) : super.withData();
  final gate = Completer<void>();
  bool entered = false;
  int reads = 0;
  static Future<IdentifyHeldInventory> install() async {
    final store = IdentifyHeldInventory(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    if (++reads == 1) {
      entered = true;
      final activity = VpFixtureActions.current?.begin(
        'held-addon-inventory-failure',
        held: true,
      );
      try {
        await gate.future;
        throw StateError('Synthetic held stable inventory failure');
      } finally {
        activity?.complete();
      }
    }
    return super.getAll();
  }

  void freshLoad() => SharedPreferences.resetStatic();
  void release() {
    if (!gate.isCompleted) gate.complete();
  }
}
