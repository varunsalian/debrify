import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/dev/profile_audit_flag.dart';
import 'package:debrify/services/profiles/dev/profile_audit_report.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_cache_ledger.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The audit report is meant to be pasted to someone else, so the tests that
/// matter most are the ones proving nothing private rides along.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporaryDirectory;
  late Directory documents;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
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
    temporaryDirectory = await Directory.systemTemp.createTemp('audit-report-');
    documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    await documents.create(recursive: true);
    AppStorage.debugOverride(documents: documents, support: documents);
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    adminId = (await registry.createProfile(
      name: 'Household Admin',
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
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 21));
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

  Future<void> writePref(String profileId, String key, Object value) async {
    final prefs = await ProfilePreferences.forCapturedScope(
      ProfileScope(profileId: profileId, dataGeneration: 1, sessionEpoch: 0),
      CapturedProfilePreferenceAccess.migration,
    );
    if (value is String) await prefs.setString(key, value);
    if (value is bool) await prefs.setBool(key, value);
  }

  test('no value, profile id or watched title reaches the report', () async {
    await writePref(adminId, 'app_theme', 'sentinel-theme-value');
    await writePref(adminId, 'series_source_tt0903747', 'sentinel-binding');
    await writePref(memberId, 'iptv_style', 'sentinel-style-value');

    final json = await ProfileAuditReport.collectJson(registry);

    for (final secret in <String>[
      'sentinel-theme-value',
      'sentinel-binding',
      'sentinel-style-value',
    ]) {
      expect(json, isNot(contains(secret)), reason: '$secret must not ship');
    }
    // Real ids identify the install; the IMDb id names something watched.
    expect(json, isNot(contains(adminId)));
    expect(json, isNot(contains(memberId)));
    expect(json, isNot(contains('tt0903747')));
    // Profile names can identify a household.
    expect(json, isNot(contains('Household Admin')));

    expect(json, contains('profile-1'));
    expect(json, contains('series_source_<imdbId>'));
  });

  test(
    'identical values across profiles collide, different ones do not',
    () async {
      await writePref(adminId, 'app_theme', 'signal');
      await writePref(memberId, 'app_theme', 'signal');
      await writePref(adminId, 'iptv_style', 'command');
      await writePref(memberId, 'iptv_style', 'console');

      final report = await ProfileAuditReport.collect(registry);
      final prefs = report['preferences']! as Map<String, Object?>;

      String hashOf(String alias, String key) =>
          ((prefs[alias]! as List).cast<Map<String, Object?>>().firstWhere(
                (row) => row['key'] == key,
              ))['hash']!
              as String;

      expect(
        hashOf('profile-1', 'app_theme'),
        hashOf('profile-2', 'app_theme'),
        reason: 'the same value in two profiles is the isolation smell',
      );
      expect(
        hashOf('profile-1', 'iptv_style'),
        isNot(hashOf('profile-2', 'iptv_style')),
      );
    },
  );

  test('the salt is per export, so hashes never survive the file', () async {
    await writePref(adminId, 'app_theme', 'signal');
    String themeHash(Map<String, Object?> report) =>
        (((report['preferences']! as Map<String, Object?>)['profile-1']!
                    as List)
                .cast<Map<String, Object?>>()
                .firstWhere((row) => row['key'] == 'app_theme'))['hash']!
            as String;

    expect(
      themeHash(await ProfileAuditReport.collect(registry)),
      isNot(themeHash(await ProfileAuditReport.collect(registry))),
      reason: 'a stable salt would be a rainbow-table target',
    );
  });

  test('a resource missing a required key is reported', () async {
    // Exactly the IPTV bug: the migration stripped `url` because it was empty.
    await ConnectionResourceService(registry: registry, cipher: cipher).create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: ConnectionResourceType.iptvXtream,
      label: 'Panel',
      publicConfig: const <String, dynamic>{'playlistName': 'Panel'},
      secretConfig: const <String, dynamic>{
        'name': 'Panel',
        'serverUrl': 'https://panel.invalid:8080',
        'addedAt': '2026-08-14T00:00:00.000Z',
      },
    );

    final report = await ProfileAuditReport.collect(registry);
    final findings = (report['findings']! as List).cast<Map<String, Object?>>();
    final missing = findings.singleWhere(
      (row) => row['id'] == 'resource-missing-required-key',
    );
    expect(missing['detail'], contains('url'));

    // And the resource row itself names its keys, without any value.
    final resource = (report['resources']! as List)
        .cast<Map<String, Object?>>()
        .single;
    expect(resource['secretKeysReadable'], isTrue);
    expect(resource['secretKeys'], isNot(contains('url')));
    expect(resource['secretKeys'], contains('serverUrl'));
    expect(jsonEncode(report), isNot(contains('panel.invalid')));
  });

  test('a stale cache stamp is reported against the active scope', () async {
    ProfileCacheLedger.stamp(
      'Engines',
      ProfileScope(profileId: memberId, dataGeneration: 1, sessionEpoch: 9),
    );
    ProfileCacheLedger.stamp(
      'Trakt',
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 1),
    );

    final report = await ProfileAuditReport.collect(registry);
    final caches = (report['caches']! as List).cast<Map<String, Object?>>();
    expect(
      caches.firstWhere((row) => row['name'] == 'Trakt')['matchesActive'],
      isTrue,
    );
    expect(
      caches.firstWhere((row) => row['name'] == 'Engines')['matchesActive'],
      isFalse,
    );

    final stale = (report['findings']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((row) => row['id'] == 'cache-scope-stale');
    expect(stale['cache'], 'Engines');
    // Even inside a finding message, ids stay pseudonymous.
    expect(stale['detail'], contains('profile-2'));
    expect(stale['detail'], isNot(contains(memberId)));
  });

  test('a credential left in a profile namespace is reported', () async {
    // Migration converts every credential key to a resource, so anything
    // credential-shaped still sitting in a profile namespace is a finding.
    await writePref(adminId, 'real_debrid_api_key', 'sentinel-key');

    final report = await ProfileAuditReport.collect(registry);
    final residue = (report['findings']! as List)
        .cast<Map<String, Object?>>()
        .singleWhere((row) => row['id'] == 'credential-residue');
    expect(residue['detail'], contains('real_debrid_api_key'));
    expect(jsonEncode(report), isNot(contains('sentinel-key')));
  });

  test('device preferences of every type are read, not thrown on', () async {
    // DevicePreferences exposes typed getters only, and getString on a bool
    // THROWS rather than returning null. Chaining the accessors crashed on the
    // first non-String key — which on a real device is remote_control_enabled.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'remote_control_enabled': true,
      'remote_tv_device_name': 'sentinel-device-name',
      'recording_max_concurrent': 3,
      'subtitle_custom_fonts': <String>['sentinel-font'],
    });

    final report = await ProfileAuditReport.collect(registry);
    final device = (report['devicePreferences']! as List)
        .cast<Map<String, Object?>>();
    Map<String, Object?> row(String key) =>
        device.singleWhere((entry) => entry['key'] == key);

    expect(row('remote_control_enabled')['type'], 'bool');
    expect(row('remote_tv_device_name')['type'], 'str');
    expect(row('recording_max_concurrent')['type'], 'int');
    expect(row('subtitle_custom_fonts')['type'], 'list');
    final json = jsonEncode(report);
    expect(json, isNot(contains('sentinel-device-name')));
    expect(json, isNot(contains('sentinel-font')));
  });

  test('the entry point stays behind the compile-time flag', () {
    // The gate is what makes this tooling removable in one edit, whichever way
    // the default points. Pinned separately from the default so flipping the
    // default can never quietly un-gate the button.
    final screen = File(
      'lib/screens/profiles/manage_profiles_screen.dart',
    ).readAsStringSync();
    expect(screen, contains('if (kProfileAudit)'));
  });

  test('the default is ON, deliberately and temporarily', () {
    // User decision 2026-08-15: default true so local --release tvOS builds
    // carry the tool without a --dart-define. The consequence is real — CI
    // passes no defines, so a release artifact cut today includes this — and
    // is accepted only while this branch has one user.
    //
    // This assertion exists so that flipping the default back is a deliberate
    // act with a failing test to explain itself, rather than a silent change.
    expect(
      kProfileAudit,
      isTrue,
      reason:
          'flip this test with the default; see profile_audit_flag.dart for '
          'why it is on and when it must go off',
    );
  });

  test('the diagnostics handle cannot write', () async {
    final prefs = await ProfilePreferences.forCapturedScope(
      ProfileScope(profileId: adminId, dataGeneration: 1, sessionEpoch: 0),
      CapturedProfilePreferenceAccess.diagnosticsReadOnly,
    );
    expect(prefs.getKeys(), isA<Set<String>>());
    await expectLater(
      prefs.setString('app_theme', 'mutated'),
      throwsA(isA<StateError>()),
    );
  });
}
