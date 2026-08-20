import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/profiles_settings_page.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The hub's contract: the active identity is distinct from the other-profile
/// roster, with device behavior and household actions grouped separately.
void main() {
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String adminId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    temporaryDirectory = await Directory.systemTemp.createTemp('hub-test-');
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Boss',
      role: UserProfileRole.admin,
    )).id;
    await registry.createProfile(name: 'Maya', role: UserProfileRole.child);
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  // Real registry IO completes only inside runAsync windows, and avatar art
  // animates continuously (pumpAndSettle would never settle) — so interleave
  // bounded real-async waits with pumps, the house pattern for these
  // screens.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> pumpHub(
    WidgetTester tester, {
    Size size = const Size(900, 1400),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(home: ProfilesSettingsPage()));
    await settle(tester);
  }

  testWidgets('level one separates the active identity and other profiles', (
    tester,
  ) async {
    await pumpHub(tester);

    expect(find.text('CURRENT PROFILE'), findsOneWidget);
    expect(find.text('Admin · Signed in'), findsOneWidget);
    expect(find.text('OTHER PROFILES'), findsOneWidget);
    expect(find.text('Kid'), findsOneWidget);

    // Only profile-specific actions remain in this hub. Backup/restore belongs
    // to Data & Backup and picker presentation belongs to Appearance.
    expect(find.text('Switch profile'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.text('Create a profile'), findsOneWidget);
    expect(find.text('Send profiles to TV'), findsOneWidget);
    expect(find.text('Back up'), findsNothing);
    expect(find.text('Restore'), findsNothing);
    expect(find.text("Who's-watching style"), findsNothing);
  });

  testWidgets('a profile row opens one action panel that can disable', (
    tester,
  ) async {
    await pumpHub(tester);

    await tester.tap(find.text('Maya'));
    await settle(tester);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Switch to this profile'), findsOneWidget);
    expect(find.text('Disable profile'), findsOneWidget);
    expect(find.text('Delete profile'), findsOneWidget);

    await tester.tap(find.text('Disable profile'));
    await settle(tester);

    // The hub keeps showing the disabled profile (managers must see it to
    // re-enable or delete), badged accordingly.
    expect(find.text('Kid · disabled'), findsOneWidget);
  });

  testWidgets('the active profile is not duplicated in the roster', (
    tester,
  ) async {
    await pumpHub(tester);
    expect(find.text('Boss'), findsOneWidget);
    expect(find.byKey(const ValueKey('profiles-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('profiles-edit-current')), findsOneWidget);
  });

  testWidgets('compact layout stacks without clipping profile actions', (
    tester,
  ) async {
    await pumpHub(tester, size: const Size(390, 844));

    expect(find.byKey(const ValueKey('profiles-switch')), findsOneWidget);
    expect(find.byKey(const ValueKey('profiles-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('profiles-always-ask')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
