import 'dart:io';
import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/pikpak/pikpak_files_screen.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/screens/profiles/profile_wall_screen.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_cache_ledger.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/pikpak_storage.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../../support/pikpak_files_fixture.dart';

class ProfileFixture {
  late Directory root;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late String a;
  Future<void> open() async {
    root = await Directory.systemTemp.createTemp('pikpak-profile-');
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
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 5));
    await cipher.initialize();
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: a, dataGeneration: 1, sessionEpoch: 1),
    );
    await PikpakStorage.setPikPakEmail('profile-A@example.test');
    await PikpakStorage.setPikPakAccessToken('profile-A-access');
    await PikpakStorage.setPikPakRefreshToken('profile-A-refresh');
    await PikpakStorage.setPikPakEnabled(true);
    await ProfileGateAlwaysAsk.set(false);
    await ProfileGateStyle.set(ProfileGateStyle.classic);
  }

  Future<void> close() async {
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    ProfileCacheLedger.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await root.delete(recursive: true);
  }
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  for (final loadError in [false, true]) {
    testWidgets(
      'shared restricted logout survives credentials grants restriction loadError=$loadError',
      (t) => pikpakCase(t, (f) async {
        final p = ProfileFixture();
        await t.runAsync(p.open);
        late String borrower;
        late ConnectionResource resource;
        await t.runAsync(() async {
          final admin = (await p.registry.getProfile(p.a))!;
          borrower = (await p.registry.createProfile(
            name: 'Borrower',
            role: UserProfileRole.member,
            actingProfileId: p.a,
            actingAuthorizationRevision: admin.authorizationRevision,
            actingSessionEpoch: ProfileRuntime.capture().sessionEpoch,
          )).id;
          final resources = ConnectionResourceService(
            registry: p.registry,
            cipher: p.cipher,
          );
          resource = await resources.create(
            context: await ProfileAuthorizationContext.capture(p.registry),
            type: ConnectionResourceType.pikpak,
            label: 'PikPak',
            publicConfig: const {},
            secretConfig: const {
              'email': 'profile-A@example.test',
              'accessToken': 'profile-A-access',
              'refreshToken': 'profile-A-refresh',
            },
          );
          await p.registry.bindResource(
            profileId: p.a,
            slot: 'provider.pikpak',
            resourceId: resource.id,
          );
          await resources.grant(
            actor: await ProfileAuthorizationContext.capture(p.registry),
            targetProfileId: borrower,
            resourceId: resource.id,
            permissions: const {ResourcePermission.use},
          );
          await PikpakStorage.setPikPakRestrictedFolder(
            'restricted',
            'Restricted',
          );
        });
        try {
          if (loadError) {
            f.failLists = true;
          } else {
            f.details['restricted'] = pikpakFile('restricted');
          }
          await f.mount(t, wait: false);
          await f.until(
            t,
            () => find
                .text(
                  'This connection is shared. Manage profile access before disconnecting.',
                )
                .evaluate()
                .isNotEmpty,
          );
          expect(f.member('pikpakEnabled'), loadError);
          expect(f.member('isLoading'), loadError);
          expect(f.member('initialLoad'), isTrue);
          expect(
            f.member('restrictedFolderId'),
            loadError ? 'restricted' : null,
          );
          expect(f.member('currentFolderId'), loadError ? 'restricted' : null);
          expect(
            await t.runAsync(PikpakStorage.getPikPakEmail),
            'profile-A@example.test',
          );
          expect(
            await t.runAsync(PikpakStorage.getPikPakAccessToken),
            'profile-A-access',
          );
          expect(
            await t.runAsync(PikpakStorage.getPikPakRefreshToken),
            'profile-A-refresh',
          );
          expect(
            await t.runAsync(PikpakStorage.getPikPakRestrictedFolderId),
            'restricted',
          );
          expect(
            await t.runAsync(() => p.registry.getGrant(borrower, resource.id)),
            isNotNull,
          );
          expect(
            await t.runAsync(() => p.registry.getResource(resource.id)),
            isNotNull,
          );
          expect(f.requests.map((r) => (r.method, r.url.path)), [
            ('GET', '/drive/v1/files/restricted'),
            if (loadError) ('GET', '/drive/v1/files'),
          ]);
        } finally {
          await t.pumpWidget(const SizedBox.shrink());
          await t.runAsync(p.close);
          ProfileRuntime.initializeLegacy();
        }
      }),
    );
  }
  testWidgets(
    'ProfileGate remount replaces state resources settings and active tokens',
    (t) => pikpakCase(t, (f) async {
      final p = ProfileFixture();
      await t.runAsync(p.open);
      try {
        t.view.physicalSize = const Size(1000, 800);
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          MaterialApp(home: const ProfileGate(child: PikPakFilesScreen())),
        );
        State<PikPakFilesScreen> state() =>
            t.state<State<PikPakFilesScreen>>(find.byType(PikPakFilesScreen));
        dynamic member(String name) => pikpakFilesTestAccess(state())[name];
        await f.until(
          t,
          () =>
              find.byType(PikPakFilesScreen).evaluate().isNotEmpty &&
              member('initialLoad') == false,
        );
        final oldState = state();
        final old = pikpakFilesTestAccess(oldState);
        await t.runAsync(() async {
          final admin = (await p.registry.getProfile(p.a))!;
          final b = (await p.registry.createProfile(
            name: 'B',
            role: UserProfileRole.admin,
            actingProfileId: p.a,
            actingAuthorizationRevision: admin.authorizationRevision,
            actingSessionEpoch: ProfileRuntime.capture().sessionEpoch,
          )).id;
          await p.registry.setActiveProfile(b);
          ProfileRuntime.publish(
            ProfileScope(profileId: b, dataGeneration: 1, sessionEpoch: 2),
          );
          await PikpakStorage.setPikPakEmail('profile-B@example.test');
          await PikpakStorage.setPikPakAccessToken('profile-B-access');
          await PikpakStorage.setPikPakRefreshToken('profile-B-refresh');
          await PikpakStorage.setPikPakEnabled(true);
          await PikpakStorage.setPikPakShowVideosOnly(false);
        });
        f.rows = [pikpakFile('incoming', video: false)];
        await t.pump();
        await f.until(
          t,
          () =>
              find.byType(PikPakFilesScreen).evaluate().isNotEmpty &&
              !identical(state(), oldState) &&
              member('initialLoad') == false,
        );
        expect(oldState.mounted, isFalse);
        expect(member('showVideosOnly'), isFalse);
        expect((member('files') as List).map((dynamic r) => r['id']), [
          'incoming',
        ]);
        expect(
          f.requests.last.headers['authorization'],
          'Bearer profile-B-access',
        );
        for (final name in [
          'files',
          'navigationStack',
          'folderViewModes',
          'selectedFileIds',
          'recursiveFileCache',
          'scrollController',
          'linkController',
          'searchController',
          'firstItemFocusNode',
        ]) {
          expect(identical(old[name], member(name)), isFalse, reason: name);
        }
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(p.close);
        ProfileRuntime.initializeLegacy();
      }
    }),
  );
  testWidgets(
    'two independent routes never share workflow collection or resource owners',
    (t) => pikpakCase(t, (f) async {
      await f.mount(t);
      final old = f.access;
      final second = GlobalKey<State<PikPakFilesScreen>>();
      f.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PikPakFilesScreen(key: second, isPushedRoute: true),
        ),
      );
      await t.pump();
      await f.until(
        t,
        () =>
            second.currentState != null &&
            pikpakFilesTestAccess(second.currentState!)['initialLoad'] == false,
      );
      final next = pikpakFilesTestAccess(second.currentState!);
      for (final name in [
        'files',
        'navigationStack',
        'folderViewModes',
        'selectedFileIds',
        'recursiveFileCache',
        'scrollController',
        'linkController',
        'searchController',
        'firstItemFocusNode',
      ]) {
        expect(identical(old[name], next[name]), isFalse, reason: name);
      }
      (next['toggleSelectionMode'] as VoidCallback)();
      await t.pump();
      expect(
        pikpakFilesTestAccess(second.currentState!)['isSelectionMode'],
        isTrue,
      );
      expect(f.member('isSelectionMode'), isFalse);
      expect(f.requests.length, 2);
      f.navigatorKey.currentState!.pop();
      await t.pump(const Duration(milliseconds: 600));
    }),
  );
}
