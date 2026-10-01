import 'package:debrify/services/profiles/profile_preferences.dart';

final class UiFeedbackStorage {
  const UiFeedbackStorage._();
  static const String _uiSoundsKey = 'ui_sounds';
  static const String _uiHapticsKey = 'ui_haptics';

  /// Whether interface sound and haptics are allowed at all.
  ///
  /// A VETO, not a switch: the theme decides whether there is anything to play
  /// and these decide whether the user wants to hear or feel it. Both default
  /// ON, because a theme that asks for silence — which is every look except
  /// Console and Warm Room — already produces none, so the default cannot
  /// surprise anybody who has not chosen a look that ticks.
  ///
  /// Synchronous mirrors because `UiFeedback` is consulted from a focus
  /// listener and a key handler, neither of which can await. Warmed in main()
  /// before runApp.
  static bool uiSoundsCached = true;
  static bool uiHapticsCached = true;

  static Future<bool> getUiSounds() async {
    final prefs = await ProfilePreferences.instance();
    uiSoundsCached = prefs.getBool(_uiSoundsKey) ?? true;
    return uiSoundsCached;
  }

  static Future<void> setUiSounds(bool enabled) async {
    // The mirror moves FIRST. `UiFeedback` reads it from a focus listener that
    // cannot await, so publishing after the platform write leaves a window in
    // which a user who has just switched sound off still hears the next tick.
    uiSoundsCached = enabled;
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_uiSoundsKey, enabled);
  }

  static Future<bool> getUiHaptics() async {
    final prefs = await ProfilePreferences.instance();
    uiHapticsCached = prefs.getBool(_uiHapticsKey) ?? true;
    return uiHapticsCached;
  }

  static Future<void> setUiHaptics(bool enabled) async {
    uiHapticsCached = enabled;
    final prefs = await ProfilePreferences.instance();
    await prefs.setBool(_uiHapticsKey, enabled);
  }

  /// Clears this owner before the existing profile handoff ledger stamp.
  static void resetProfileCaches() {
    uiSoundsCached = true;
    uiHapticsCached = true;
  }
}
