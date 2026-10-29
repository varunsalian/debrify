// Persisted league on/off choices.
//
// Data layer: the store owns the serialized shape (two sorted string lists)
// and nothing else. Persistence is reached through the narrow SportsPrefs
// contract from sports_follow_store.dart, resolved per operation so the
// composition boundary can hand over the storage of the currently active
// profile instead of letting a stale reference write into the wrong one.
import 'package:debrify/features/sports/data/sports_follow_store.dart';
import 'package:debrify/features/sports/models/sports_league_filter.dart';

/// Reads and writes the board's league filter.
///
/// [read] never fails on missing keys: an untouched device reads back as the
/// empty filter (every league uses its default). [write] stores sorted lists
/// so the same choices always serialize to the same bytes.
final class SportsLeagueFilterStore {
  SportsLeagueFilterStore(this._prefs);

  /// Key of the leagues enabled although off by default.
  static const onKey = 'sports_leagues_on_v1';

  /// Key of the leagues disabled although on by default.
  static const offKey = 'sports_leagues_off_v1';

  final Future<SportsPrefs> Function() _prefs;

  /// The stored filter; missing keys read as the empty filter.
  Future<SportsLeagueFilter> read() async {
    final prefs = await _prefs();
    return SportsLeagueFilter(
      on: _stored(prefs, onKey),
      off: _stored(prefs, offKey),
    );
  }

  /// Stores [filter] as two sorted lists under [onKey] and [offKey].
  Future<void> write(SportsLeagueFilter filter) async {
    final prefs = await _prefs();
    await prefs.setStringList(onKey, _sorted(filter.on));
    await prefs.setStringList(offKey, _sorted(filter.off));
  }

  static Set<String> _stored(SportsPrefs prefs, String key) {
    final stored = prefs.getStringList(key);
    return stored == null ? const <String>{} : Set<String>.of(stored);
  }

  static List<String> _sorted(Iterable<String> ids) => [...ids]..sort();
}
