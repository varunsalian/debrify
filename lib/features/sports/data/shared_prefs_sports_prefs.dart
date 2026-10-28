// The production [SportsPrefs] adapter over SharedPreferences.
//
// Data layer: forwarding only — no key naming, no defaults and no caching, so
// [SportsFollowStore] stays the single owner of the persisted shape.
import 'package:shared_preferences/shared_preferences.dart';

import 'sports_follow_store.dart';

/// Forwards the four storage calls the follow store makes.
final class SharedPrefsSportsPrefs implements SportsPrefs {
  SharedPrefsSportsPrefs(this._prefs);

  final SharedPreferences _prefs;

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);
}
