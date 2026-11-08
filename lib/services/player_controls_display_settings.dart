import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:flutter/foundation.dart';

/// Profile-owned choices for how the in-app player's controls read.
///
/// The controls listen to the notifiers, so a change shows at once; each new
/// player kicks off [load] to refresh them from the active profile.
final class PlayerControlsDisplaySettings {
  const PlayerControlsDisplaySettings._();

  /// The duration readout shows the time left (`-42:55`) instead of the
  /// total (`46:20`). Tapping the readout flips it.
  static const remainingKey = 'player_time_remaining_v1';

  /// The control buttons show their icons only, without labels.
  static const iconOnlyKey = 'player_controls_icon_only_v1';

  static final ValueNotifier<bool> showRemaining = ValueNotifier(false);
  static final ValueNotifier<bool> iconOnly = ValueNotifier(false);

  /// Never throws: with no profile yet, or a failed read, the current values
  /// stay.
  static Future<void> load() async {
    try {
      final prefs = await ProfilePreferences.instance();
      showRemaining.value = prefs.getBool(remainingKey) ?? false;
      iconOnly.value = prefs.getBool(iconOnlyKey) ?? false;
    } catch (_) {
      // No profile scope yet, or the read failed: keep the current values.
    }
  }

  static Future<void> toggleRemaining() =>
      _write(showRemaining, remainingKey, !showRemaining.value);

  static Future<void> setIconOnly(bool enabled) =>
      _write(iconOnly, iconOnlyKey, enabled);

  /// A failed write still updates the notifier, so the session reflects the
  /// choice.
  static Future<void> _write(
    ValueNotifier<bool> notifier,
    String key,
    bool value,
  ) async {
    notifier.value = value;
    try {
      final prefs = await ProfilePreferences.instance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Nothing to persist into; the notifier still holds.
    }
  }
}
