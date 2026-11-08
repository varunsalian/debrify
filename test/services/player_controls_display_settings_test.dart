// The duration readout's mode and the icon-only controls are remembered for
// the profile, and the controls read them through notifiers.

import 'package:debrify/services/player_controls_display_settings.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    PlayerControlsDisplaySettings.showRemaining.value = false;
    PlayerControlsDisplaySettings.iconOnly.value = false;
  });
  tearDown(ProfileRuntime.debugReset);

  test('both default off', () async {
    await PlayerControlsDisplaySettings.load();
    expect(PlayerControlsDisplaySettings.showRemaining.value, isFalse);
    expect(PlayerControlsDisplaySettings.iconOnly.value, isFalse);
  });

  test('choices persist and come back on the next load', () async {
    await PlayerControlsDisplaySettings.toggleRemaining();
    await PlayerControlsDisplaySettings.setIconOnly(true);

    final prefs = await ProfilePreferences.instance();
    expect(prefs.getBool(PlayerControlsDisplaySettings.remainingKey), isTrue);
    expect(prefs.getBool(PlayerControlsDisplaySettings.iconOnlyKey), isTrue);

    PlayerControlsDisplaySettings.showRemaining.value = false;
    PlayerControlsDisplaySettings.iconOnly.value = false;
    await PlayerControlsDisplaySettings.load();
    expect(PlayerControlsDisplaySettings.showRemaining.value, isTrue);
    expect(PlayerControlsDisplaySettings.iconOnly.value, isTrue);
  });

  test('toggling twice returns to the total', () async {
    await PlayerControlsDisplaySettings.toggleRemaining();
    await PlayerControlsDisplaySettings.toggleRemaining();
    expect(PlayerControlsDisplaySettings.showRemaining.value, isFalse);
  });
}
