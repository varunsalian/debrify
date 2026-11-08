// Persisted kick-off reminders for the active profile.
//
// Data layer: owns the stored shape (one string list of encoded reminders)
// and nothing else. Storage is reached through [SportsPrefs], resolved per
// operation so the active profile's storage is always the one written.
import 'package:debrify/features/sports/models/sports_reminder.dart';

import 'sports_follow_store.dart';

final class SportsReminderStore {
  SportsReminderStore(this._prefs);

  final Future<SportsPrefs> Function() _prefs;

  static const remindersKey = 'sports_reminders';

  /// Unreadable entries are skipped rather than failing the whole list.
  Future<List<SportsReminder>> read() async {
    final prefs = await _prefs();
    return [
      for (final raw in prefs.getStringList(remindersKey) ?? const <String>[])
        ?SportsReminder.decode(raw),
    ];
  }

  Future<void> write(List<SportsReminder> reminders) async {
    final prefs = await _prefs();
    final sorted = [...reminders]
      ..sort((a, b) => a.eventKey.compareTo(b.eventKey));
    await prefs.setStringList(remindersKey, [
      for (final reminder in sorted) reminder.encode(),
    ]);
  }
}
