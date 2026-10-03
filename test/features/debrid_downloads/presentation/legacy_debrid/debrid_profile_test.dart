import 'dart:io';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/debrid_downloads_screen.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_cache_ledger.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/real_debrid_storage.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../../support/debrid_downloads_fixture.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets(
    'committed ProfileGate epoch remount replaces all original owners and credentials',
    (t) => debridCase(t, (f) async {
      late Directory root;
      late ProfileRegistry registry;
      late String a;
      late String b;
      await t.runAsync(() async {
        root = await Directory.systemTemp.createTemp('debrid-profile-');
        AppStorage.debugOverride(documents: root, support: root, cache: root);
        registry = await ProfileRegistry.open(path: '${root.path}/profiles.db');
        a = (await registry.createProfile(
          name: 'A',
          role: UserProfileRole.admin,
        )).id;
        await registry.commitBootstrap(
          activeProfileId: a,
          migratedLegacyInstall: false,
        );
        final cipher = MemoryDeviceSecretCipher(
          List<int>.generate(32, (i) => i + 5),
        );
        await cipher.initialize();
        DeviceKeyProvider.debugInstallCipher(cipher);
        ProfileBootstrap.debugInstallRegistry(registry);
        ProfileRuntime.initializeCommitted(
          ProfileScope(profileId: a, dataGeneration: 1, sessionEpoch: 1),
        );
        await RealDebridStorage.saveApiKey('profile-A-key');
        await ProfileGateAlwaysAsk.set(false);
        await ProfileGateStyle.set(ProfileGateStyle.classic);
      });
      try {
        t.view.physicalSize = const Size(1000, 800);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(home: const ProfileGate(child: DebridDownloadsScreen())),
        );
        State<DebridDownloadsScreen> state() =>
            t.state<State<DebridDownloadsScreen>>(
              find.byType(DebridDownloadsScreen),
            );
        dynamic member(String name) => debridDownloadsTestAccess(state())[name];
        await f.until(
          t,
          () =>
              find.byType(DebridDownloadsScreen).evaluate().isNotEmpty &&
              member('apiKey') == 'profile-A-key' &&
              member('isLoadingDownloads') == false,
        );
        await t.pump();
        final oldState = state();
        final old = debridDownloadsTestAccess(state());
        await t.runAsync(() async {
          final admin = (await registry.getProfile(a))!;
          b = (await registry.createProfile(
            name: 'B',
            role: UserProfileRole.admin,
            actingProfileId: a,
            actingAuthorizationRevision: admin.authorizationRevision,
            actingSessionEpoch: ProfileRuntime.capture().sessionEpoch,
          )).id;
          await registry.setActiveProfile(b);
          ProfileRuntime.publish(
            ProfileScope(profileId: b, dataGeneration: 1, sessionEpoch: 2),
          );
          await ProfileRuntime.withCapturedScope(
            ProfileScope(profileId: b, dataGeneration: 1, sessionEpoch: 2),
            () => RealDebridStorage.saveApiKey('profile-B-key'),
          );
        });
        f.torrents = [debridTorrent('incoming')];
        f.requests.clear();
        ProfileRuntime.publish(
          ProfileScope(profileId: b, dataGeneration: 1, sessionEpoch: 2),
        );
        await t.pump();
        await f.until(
          t,
          () =>
              state() != oldState &&
              member('apiKey') == 'profile-B-key' &&
              member('isLoadingDownloads') == false,
        );
        expect(identical(state(), oldState), isFalse);
        expect(member('apiKey'), 'profile-B-key');
        for (final name in [
          'torrents',
          'downloads',
          'torrentViewModes',
          'folderPath',
          'selectedTorrentIds',
          'selectedDownloadIds',
          'torrentScrollController',
          'downloadScrollController',
          'firstItemFocusNode',
          'torrentSearchFocusNode',
          'magnetController',
          'linkController',
          'torrentSearchController',
          'searchController',
        ]) {
          expect(identical(old[name], member(name)), isFalse, reason: name);
        }
        expect((member('torrents') as List).map((dynamic row) => row.id), [
          'incoming',
        ]);
        expect(
          f.requests.every(
            (r) => r.headers['Authorization'] == 'Bearer profile-B-key',
          ),
          isTrue,
        );
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 11));
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        ProfileRuntime.debugReset();
        ProfileBootstrap.debugInstallRegistry(null);
        DeviceKeyProvider.debugReset();
        ProfileCacheLedger.debugReset();
        AppStorage.debugReset();
        await t.runAsync(() async {
          await registry.close();
          await root.delete(recursive: true);
        });
      }
    }),
  );
}
