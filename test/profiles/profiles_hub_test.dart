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

/// The hub's contract: everything visible at level one (roster with state
/// badges + household actions), per-profile actions one panel deep.
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

  Future<void> pumpHub(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: ProfilesSettingsPage()),
    );
    await settle(tester);
  }

  testWidgets('level one shows the whole household with state badges', (
    tester,
  ) async {
    await pumpHub(tester);

    // Roster with badges: the signed-in admin and the kid.
    expect(find.text('Admin · you'), findsOneWidget);
    expect(find.text('Kid'), findsOneWidget);

    // Household actions all present at level one.
    expect(find.text('Create a profile'), findsOneWidget);
    expect(find.text('Send everything to TV'), findsOneWidget);
    expect(find.text('Back up'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('More management'), findsOneWidget);
  });

  testWidgets('a profile row opens one action panel that can disable', (
    tester,
  ) async {
    await pumpHub(tester);

    await tester.tap(find.text('Maya'));
    await settle(tester);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Disable'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    // Only the active profile's panel offers Switch.
    expect(find.text('Switch profile'), findsNothing);

    await tester.tap(find.text('Disable'));
    await settle(tester);

    // The hub keeps showing the disabled profile (managers must see it to
    // re-enable or delete), badged accordingly.
    expect(find.text('Kid · disabled'), findsOneWidget);
  });

  testWidgets('the active profile panel offers Switch', (tester) async {
    await pumpHub(tester);
    // 'Boss' also sits on the active card — target the roster row via its
    // unique badge line.
    await tester.tap(find.text('Admin · you'));
    await settle(tester);
    expect(find.text('Switch profile'), findsOneWidget);
    // The registry blocks disabling/deleting the signed-in profile, so the
    // panel must not dangle actions that can only fail.
    expect(find.text('Disable'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });
}
