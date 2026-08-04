import 'package:debrify/services/engine/settings_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final settings = SettingsManager();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('background torrent prefetch defaults to enabled', () async {
    expect(await settings.getGlobalBackgroundPrefetchEnabled(), isTrue);
  });

  test('background torrent prefetch can be disabled and re-enabled', () async {
    await settings.setGlobalBackgroundPrefetchEnabled(false);
    expect(await settings.getGlobalBackgroundPrefetchEnabled(), isFalse);

    await settings.setGlobalBackgroundPrefetchEnabled(true);
    expect(await settings.getGlobalBackgroundPrefetchEnabled(), isTrue);
  });
}
