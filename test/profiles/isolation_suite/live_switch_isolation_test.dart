import 'dart:io';

import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/services/profiles/profile_app_lifecycle_participant.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_cache_ledger.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_lifecycle.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Drives a **real** profile switch through the real
/// [ProfileAppLifecycleParticipant] and asserts what the incoming profile can
/// see afterwards — with no relaunch, which is the case that matters.
///
/// The other suites in this directory reason about the source. This one runs
/// the actual reset/warm path, so it catches ordering faults that no amount of
/// source parsing can: a warm that throws partway, a cache warmed against the
/// outgoing scope, a mirror repopulated from the wrong profile.
///
/// **What this cannot cover.** Everything here runs on the Dart VM, so native
/// state is invisible: the nine Kotlin files that read `FlutterSharedPreferences`
/// directly, `debrify_pending_recordings`, `debrify_permissions`, and tvOS
/// `UserDefaults`. Those need a device. See the suite README.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporaryDirectory;
  late ProfileRegistry registry;
  late String profileA;
  late String profileB;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    ProfileRuntime.debugReset();
    ProfileCacheLedger.debugReset();
    DeviceKeyProvider.debugReset();
    temporaryDirectory = await Directory.systemTemp.createTemp('live-switch-');
    final documents = Directory(p.join(temporaryDirectory.path, 'documents'));
    await documents.create(recursive: true);
    AppStorage.debugOverride(documents: documents, support: documents);
    registry = await ProfileRegistry.open(
      path: p.join(temporaryDirectory.path, 'profiles.db'),
    );
    profileA = (await registry.createProfile(
      name: 'A',
      role: UserProfileRole.admin,
    )).id;
    profileB = (await registry.createProfile(
      name: 'B',
      role: UserProfileRole.member,
    )).id;
    await registry.commitBootstrap(
      activeProfileId: profileA,
      migratedLegacyInstall: false,
    );
    final cipher = MemoryDeviceSecretCipher(
      List<int>.generate(32, (index) => index + 1),
    );
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: profileA, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    ProfileCacheLedger.debugReset();
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('a live switch leaves no cache stamped to the outgoing profile',
      () async {
    await StorageService.setTvHomeStyle('atrium');
    expect(StorageService.tvHomeStyleCached, 'atrium');

    final lifecycle = ProfileLifecycleCoordinator(
      registry: registry,
      participants: <ProfileLifecycleParticipant>[
        ProfileAppLifecycleParticipant(),
      ],
    );
    addTearDown(lifecycle.dispose);

    expect(await lifecycle.switchTo(profileB), isTrue);
    expect(ProfileRuntime.capture().profileId, profileB);

    // The ledger is the instrument built for exactly this question. Each row
    // is stamped as its group warms, so a warm that threw partway leaves the
    // rows after the throw showing profile A — a stale stamp IS the leak.
    final active = ProfileCacheLedger.keyFor(ProfileRuntime.capture());
    final stale = ProfileCacheLedger.snapshot().entries
        .where((entry) => entry.value != active && entry.value != 'unloaded')
        .map((entry) => '${entry.key}=${entry.value}')
        .toList()
      ..sort();

    expect(
      stale,
      isEmpty,
      reason:
          'These caches are still serving the previous profile after the '
          'switch completed. With no relaunch, that is profile A\'s data on '
          'profile B\'s screen.',
    );

    expect(
      StorageService.tvHomeStyleCached,
      isNot('atrium'),
      reason: 'the synchronous mirror still holds profile A\'s choice',
    );
  });

  test('switching back does not resurrect the other profile\'s values',
      () async {
    await StorageService.setTvHomeStyle('atrium');

    final lifecycle = ProfileLifecycleCoordinator(
      registry: registry,
      participants: <ProfileLifecycleParticipant>[
        ProfileAppLifecycleParticipant(),
      ],
    );
    addTearDown(lifecycle.dispose);

    await lifecycle.switchTo(profileB);
    await StorageService.setTvHomeStyle('mosaic');
    await lifecycle.switchTo(profileA);

    expect(
      await StorageService.getTvHomeStyle(),
      'atrium',
      reason: 'profile A must get its own choice back',
    );
    expect(
      StorageService.tvHomeStyleCached,
      'atrium',
      reason: 'the mirror must be re-warmed from A, not left holding B',
    );
  });

  test('the ledger accounts for every cache the participant warms', () async {
    final lifecycle = ProfileLifecycleCoordinator(
      registry: registry,
      participants: <ProfileLifecycleParticipant>[
        ProfileAppLifecycleParticipant(),
      ],
    );
    addTearDown(lifecycle.dispose);
    await lifecycle.switchTo(profileB);

    // Pinned rather than counted: the ledger exists so that a warm which
    // silently stops early is visible. If a row disappears from this list, a
    // cache stopped being warmed and nothing else would have said so.
    const expectedRows = <String>[
      'DiscoverPrefs',
      'Engines',
      'IPTV',
      'MDBList',
      'PikPak',
      'Simkl',
      'StorageService',
      'Stremio',
      'SubtitleFont',
      'SubtitleSettings',
      'Trakt',
      'Xtream',
    ];
    final recorded = ProfileCacheLedger.snapshot().keys.toList()..sort();
    for (final row in expectedRows) {
      expect(
        recorded,
        contains(row),
        reason: '$row was never warmed for the incoming profile',
      );
    }
  });
}
