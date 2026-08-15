import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/profiles/dev/profile_data_screen.dart';
import 'package:debrify/services/profiles/dev/profile_audit_report.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_cache_ledger.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String adminId;
  late String memberId;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    ProfileCacheLedger.debugReset();
    temporaryDirectory = await Directory.systemTemp.createTemp('audit-screen-');
    final documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    await documents.create(recursive: true);
    AppStorage.debugOverride(documents: documents, support: documents);
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Admin',
      role: UserProfileRole.admin,
    )).id;
    memberId = (await registry.createProfile(
      name: 'Member',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: adminId,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(
      List<int>.generate(32, (i) => i + 5),
    );
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    ProfileCacheLedger.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  Future<void> writePref(String profileId, String key, String value) async {
    final prefs = await ProfilePreferences.forCapturedScope(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 0),
      CapturedProfilePreferenceAccess.migration,
    );
    await prefs.setString(key, value);
  }

  /// Collects OUTSIDE the fake clock, then renders the fixture.
  ///
  /// `ProfileAuditReport.collect` walks directories and opens databases, and
  /// real file IO never completes under the widget tester's clock — pumping
  /// against it just times out. `tester.runAsync` is the window where that IO
  /// actually runs; `pumpWidget`/`pump` must stay outside it.
  Future<void> pumpScreen(WidgetTester tester) async {
    late final Map<String, Object?> report;
    await tester.runAsync(() async {
      report = await ProfileAuditReport.collect(registry);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileDataScreen(
          registry: registry,
          debugCollect: () async => report,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists a profile\'s keys without showing any value', (
    tester,
  ) async {
    await writePref(adminId, 'app_theme', 'sentinel-value');
    await pumpScreen(tester);

    expect(find.text('app_theme'), findsOneWidget);
    expect(find.textContaining('sentinel-value'), findsNothing);
    // Pseudonyms on screen too — in the picker AND the scope banner — so a
    // screenshot of this screen is as safe to share as the report itself.
    expect(find.text('profile-1'), findsWidgets);
    expect(find.textContaining(adminId), findsNothing);
  });

  testWidgets('the filter narrows to matching keys', (tester) async {
    await writePref(adminId, 'app_theme', 'signal');
    await writePref(adminId, 'iptv_style', 'command');
    await pumpScreen(tester);

    expect(find.text('app_theme'), findsOneWidget);
    expect(find.text('iptv_style'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'iptv');
    await tester.pumpAndSettle();

    expect(find.text('app_theme'), findsNothing);
    expect(find.text('iptv_style'), findsOneWidget);
  });

  testWidgets('compare buckets a shared value away from a differing one', (
    tester,
  ) async {
    await writePref(adminId, 'app_theme', 'signal');
    await writePref(memberId, 'app_theme', 'signal');
    await writePref(adminId, 'iptv_style', 'command');
    await writePref(memberId, 'iptv_style', 'console');
    await pumpScreen(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    // The shared-value bucket is the isolation smell and leads the list.
    expect(find.textContaining('Same value in both · 1'), findsOneWidget);
    expect(find.textContaining('Differs · 1'), findsOneWidget);
  });

  testWidgets('Reveal shows values, and only for the active profile', (
    tester,
  ) async {
    await writePref(adminId, 'app_theme', 'sentinel-value');
    await writePref(memberId, 'app_theme', 'other-profile-value');
    await pumpScreen(tester);

    // Nothing is shown until asked for — the report never carries values.
    expect(find.textContaining('sentinel-value'), findsNothing);

    await tester.runAsync(() async {
      await tester.tap(find.text('Reveal values'));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('sentinel-value'), findsOneWidget);

    // The OTHER profile is inventoried, never opened: switching to it offers
    // no Reveal and shows no value, so this never becomes a cross-profile
    // secret viewer.
    await tester.tap(find.text('profile-2').last);
    await tester.pumpAndSettle();
    expect(find.text('Reveal values'), findsNothing);
    expect(find.text('Hide values'), findsNothing);
    expect(find.textContaining('other-profile-value'), findsNothing);
  });

  testWidgets('a stale cache surfaces as a finding on the screen', (
    tester,
  ) async {
    ProfileCacheLedger.stamp(
      'Engines',
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 9),
    );
    await pumpScreen(tester);

    expect(find.text('cache-scope-stale'), findsOneWidget);
    expect(find.textContaining('profile-2'), findsWidgets);
  });
}
