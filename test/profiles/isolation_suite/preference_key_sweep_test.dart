import 'dart:io';

import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Enumerate-then-assert over the whole preference store.
///
/// Every other isolation test in this repo checks a key someone thought of.
/// This one inverts that: it drives real writes, then walks **every key that
/// exists afterwards** and demands each one account for itself — either it
/// carries a profile scope prefix, or it is a registered device key. There is
/// no third category, so a feature that quietly writes an unscoped key fails
/// here without anyone having predicted that feature.
///
/// That inversion is the point. The IPTV migration bug was not a broken
/// assertion, it was an absent one; this shape is the only kind that catches
/// the absent case.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const profileId = 'sweep-profile';
  final scope = ProfileScope(
    profileId: profileId,
    dataGeneration: 1,
    sessionEpoch: 1,
  );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(scope);
  });

  tearDown(ProfileRuntime.debugReset);

  /// Splits the live store into (scoped, deviceRegistered, unaccounted).
  Future<({List<String> scoped, List<String> device, List<String> orphan})>
  classify() async {
    final raw = await SharedPreferences.getInstance();
    await raw.reload();
    final scoped = <String>[];
    final device = <String>[];
    final orphan = <String>[];
    for (final key in raw.getKeys()) {
      if (key.startsWith('p.')) {
        scoped.add(key);
      } else if (DevicePreferences.allowedKeys.contains(key)) {
        device.add(key);
      } else {
        orphan.add(key);
      }
    }
    return (scoped: scoped..sort(), device: device..sort(), orphan: orphan..sort());
  }

  test('a real settings write lands inside the active profile scope', () async {
    await StorageService.setTvHomeStyle('atrium');
    await StorageService.setDetailTheme('dossier');

    final result = await classify();

    expect(
      result.orphan,
      isEmpty,
      reason:
          'These keys belong to no profile and are not registered device '
          'keys, so they are shared silently between every profile. Either '
          'write them through ProfilePreferences, or register them in '
          'DevicePreferences.allowedKeys with a reason.',
    );
    expect(result.scoped, isNotEmpty, reason: 'the writes must be observable');
    for (final key in result.scoped) {
      expect(
        key,
        startsWith(scope.preferencePrefix),
        reason: 'a scoped key belonging to a DIFFERENT profile appeared',
      );
    }
  });

  test('the second profile reads none of the first profile\'s values',
      () async {
    await StorageService.setTvHomeStyle('atrium');
    expect(await StorageService.getTvHomeStyle(), 'atrium');

    // What a switch does to storage-facing state: publish the new scope and
    // drop the synchronous mirrors. No relaunch.
    ProfileRuntime.publish(
      ProfileScope(profileId: 'other', dataGeneration: 1, sessionEpoch: 2),
    );
    StorageService.resetProfileCaches();

    expect(
      await StorageService.getTvHomeStyle(),
      isNot('atrium'),
      reason: 'profile B read profile A\'s setting',
    );
    expect(
      StorageService.tvHomeStyleCached,
      isNot('atrium'),
      reason:
          'the synchronous mirror is what the UI paints from — a stale value '
          'here is profile A\'s screen shown to profile B',
    );
  });

  test('the device allowlist stays small and deliberate', () {
    // Every entry here is a key deliberately shared by all profiles. The list
    // is the sanctioned exception to isolation, so it should be reviewed when
    // it grows — an unnoticed addition is an unnoticed shared setting.
    expect(
      DevicePreferences.allowedKeys.length,
      lessThanOrEqualTo(40),
      reason:
          'the shared-key allowlist grew; confirm each new entry genuinely '
          'describes the device rather than the person using it',
    );
    // Nothing credential-shaped may ever be device-global.
    final credentialShaped = DevicePreferences.allowedKeys
        .where(
          (key) =>
              key.contains('api_key') ||
              key.contains('token') ||
              key.contains('password') ||
              key.contains('secret'),
        )
        .toList();
    expect(
      credentialShaped,
      isEmpty,
      reason: 'a credential shared across profiles defeats the whole feature',
    );
  });

  test('no profile writes escape into the repository working tree', () {
    // A guard against the test rig itself leaking: if a service ever resolves
    // its storage root before AppStorage is overridden, it writes into the
    // checkout instead of a temp dir, and the leak is invisible until it
    // shows up in someone's `git status`.
    final strays = Directory('.')
        .listSync()
        .whereType<Directory>()
        .map((d) => d.path.split(Platform.pathSeparator).last)
        .where((name) => name.startsWith('p.') || name == 'profiles')
        .toList();
    expect(strays, isEmpty, reason: 'profile storage escaped into the repo');
  });
}
