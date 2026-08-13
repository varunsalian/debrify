import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'legacy': 'kept',
      'p.one.g.1.theme': 'blue',
      'p.two.g.1.theme': 'red',
    });
    ProfileRuntime.debugReset();
  });

  tearDown(ProfileRuntime.debugReset);

  test(
    'committed reads and clear are restricted to captured generation',
    () async {
      final scope = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(scope);
      final prefs = await ProfilePreferences.instance();

      expect(prefs.getString('theme'), 'blue');
      expect(prefs.getKeys(), <String>{'theme'});
      await prefs.setString('language', 'en');
      await prefs.clear();

      final raw = await SharedPreferences.getInstance();
      expect(raw.getString('legacy'), 'kept');
      expect(raw.getString('p.two.g.1.theme'), 'red');
      expect(raw.containsKey('p.one.g.1.theme'), isFalse);
      expect(raw.containsKey('p.one.g.1.language'), isFalse);
    },
  );

  test('legacy mode is byte-compatible with existing keys', () async {
    ProfileRuntime.initializeLegacy();
    final prefs = await ProfilePreferences.instance();

    expect(prefs.getString('legacy'), 'kept');
    await prefs.setBool('enabled', true);
    expect((await SharedPreferences.getInstance()).getBool('enabled'), isTrue);
  });

  test('device preference allowlist rejects arbitrary state', () async {
    final prefs = await DevicePreferences.instance();
    expect(() => prefs.setString('profile_theme', 'dark'), throwsArgumentError);
  });

  test(
    'current-session wrapper fails when another profile is published',
    () async {
      final first = ProfileScope(
        profileId: 'one',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      ProfileRuntime.initializeCommitted(first);
      final current = await ProfilePreferences.instance();
      ProfileRuntime.publish(
        ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
      );

      expect(() => current.getString('theme'), throwsA(isA<StateError>()));

      final captured = await ProfilePreferences.forCapturedScope(
        first,
        CapturedProfilePreferenceAccess.profileCreation,
      );
      expect(captured.getString('theme'), 'blue');
      expect(await captured.setString('background_result', 'done'), isTrue);
    },
  );

  test('native projection captured access cannot write', () async {
    final scope = ProfileScope(
      profileId: 'one',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    ProfileRuntime.initializeCommitted(scope);
    final projection = await ProfilePreferences.forCapturedScope(
      scope,
      CapturedProfilePreferenceAccess.nativeProjectionReadOnly,
    );

    expect(projection.getString('theme'), 'blue');
    await expectLater(
      projection.setString('theme', 'red'),
      throwsA(isA<StateError>()),
    );
  });
}
