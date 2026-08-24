import 'package:debrify/services/profiles/profile_preference_budget.dart';
import 'package:debrify/services/profiles/profile_creation_service.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/sanitized_profile_preferences.dart';
import 'package:debrify/services/storage_service.dart';
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

  test('Home card orientation is isolated per profile', () async {
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1),
    );

    // Landscape is the unset default; an explicit portrait choice is the
    // per-profile state that must not leak.
    expect(
      await StorageService.getHomeCardOrientation(),
      HomeCardOrientation.landscape,
    );
    await StorageService.setHomeCardOrientation(
      HomeCardOrientation.portrait,
    );

    ProfileRuntime.publish(
      ProfileScope(profileId: 'two', dataGeneration: 1, sessionEpoch: 2),
    );
    expect(
      await StorageService.getHomeCardOrientation(),
      HomeCardOrientation.landscape,
    );

    ProfileRuntime.publish(
      ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 3),
    );
    expect(
      await StorageService.getHomeCardOrientation(),
      HomeCardOrientation.portrait,
    );
  });

  test('Home card orientation transfers as a reviewed preference', () {
    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('home_card_orientation'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_card_orientation',
        'landscape',
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_card_orientation',
        'square',
      ),
      isFalse,
    );
  });

  test('Home card hold action transfers as a reviewed preference', () {
    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('home_cw_hold_to_quick_play'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_cw_hold_to_quick_play',
        true,
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_cw_hold_to_quick_play',
        'yes',
      ),
      isFalse,
    );
  });

  test('Home card text visibility transfers as a reviewed preference', () {
    expect(
      ProfileCreationService.copyablePreferenceKeys,
      contains('home_hide_card_titles_and_ratings'),
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_hide_card_titles_and_ratings',
        true,
      ),
      isTrue,
    );
    expect(
      SanitizedProfilePreferences.allowsEntry(
        'home_hide_card_titles_and_ratings',
        'yes',
      ),
      isFalse,
    );
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

  group('tvOS preference budget', () {
    String filler(int bytes) => 'x' * bytes;

    setUp(() => ProfilePreferenceBudget.debugEnforcedOverride = true);
    tearDown(ProfilePreferenceBudget.debugReset);

    ProfileScope scopeOne() =>
        ProfileScope(profileId: 'one', dataGeneration: 1, sessionEpoch: 1);

    test('refuses an oversized ordinary write without throwing', () async {
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      // Must return false rather than throw: no ordinary caller inspects the
      // result, so a throw would surface in code that has never handled one.
      expect(
        await prefs.setString(
          'bulk',
          filler(ProfilePreferenceBudget.limitBytes),
        ),
        isFalse,
      );
      expect(prefs.getString('bulk'), isNull);
    });

    test('still admits ordinary writes that fit', () async {
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(await prefs.setString('language', 'en'), isTrue);
      expect(prefs.getString('language'), 'en');
    });

    test('refuses an oversized string list write', () async {
      // Scoring a list flat instead of summing its elements would let an
      // arbitrarily large list straight through the guard.
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(
        await prefs.setStringList('bulk', <String>[
          filler(ProfilePreferenceBudget.limitBytes ~/ 2),
          filler(ProfilePreferenceBudget.limitBytes ~/ 2),
        ]),
        isFalse,
      );
      expect(prefs.getStringList('bulk'), isNull);
    });

    test('measures the whole database, not just the captured scope', () async {
      // The platform limit is database-wide, so another profile's keys count.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'p.two.g.1.bulk': filler(ProfilePreferenceBudget.limitBytes - 4096),
      });
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(await prefs.setString('bulk', filler(8192)), isFalse);
    });

    test('removal is never gated', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'p.one.g.1.bulk': filler(ProfilePreferenceBudget.limitBytes * 2),
      });
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(await prefs.remove('bulk'), isTrue);
      expect(prefs.getString('bulk'), isNull);
    });

    test('captured-scope writes are exempt', () async {
      // Migration, restore and profile creation all treat a false result as
      // fatal and throw; during bootstrap that would stop the app from
      // starting. They are bounded by their own preflight/envelope caps.
      ProfileRuntime.initializeCommitted(scopeOne());
      final captured = await ProfilePreferences.forCapturedScope(
        scopeOne(),
        CapturedProfilePreferenceAccess.migration,
      );

      expect(
        await captured.setString(
          'bulk',
          filler(ProfilePreferenceBudget.limitBytes),
        ),
        isTrue,
      );
    });

    test('off tvOS every write behaves exactly as before', () async {
      ProfilePreferenceBudget.debugEnforcedOverride = false;
      ProfileRuntime.initializeCommitted(scopeOne());
      final prefs = await ProfilePreferences.instance();

      expect(
        await prefs.setString(
          'bulk',
          filler(ProfilePreferenceBudget.limitBytes * 2),
        ),
        isTrue,
      );
    });
  });

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
