import 'package:shared_preferences/shared_preferences.dart';
// Existing resolved transport, no application package changes.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// A stable-session physical preference read failure, not a catalog HTTP error.
class IdentifyInventoryStore extends InMemorySharedPreferencesStore {
  IdentifyInventoryStore(super.values) : super.withData();
  bool fail = true;
  int reads = 0;
  static Future<IdentifyInventoryStore> install() async {
    final store = IdentifyInventoryStore(
      await SharedPreferencesStorePlatform.instance.getAll(),
    );
    SharedPreferences.resetStatic();
    SharedPreferencesStorePlatform.instance = store;
    return store;
  }

  @override
  Future<Map<String, Object>> getAll() async {
    reads++;
    if (fail) {
      throw StateError('Synthetic stable addon inventory storage failure');
    }
    return super.getAll();
  }

  void restore() {
    fail = false;
    SharedPreferences.resetStatic();
  }
}
