import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/premiumize/premiumize_files_screen.dart';
import 'package:debrify/screens/profiles/profile_gate.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage/playlist_storage.dart';
import 'package:debrify/services/storage/premiumize_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../../../support/premiumize_files_fixture.dart';
import '../../../../support/profile_fixture.dart';

const owners = [
  'items',
  'transfers',
  'navigationStack',
  'folderViewModes',
  'selectedIds',
  'searchResults',
  'scrollController',
  'linkController',
  'searchController',
  'firstItemFocusNode',
];
Future<void> bind(ProfileFixture p, String id, String apiKey) async {
  final resources = ConnectionResourceService(
    registry: p.registry,
    cipher: p.cipher,
  );
  final r = await resources.create(
    context: await ProfileAuthorizationContext.capture(p.registry),
    type: ConnectionResourceType.premiumize,
    label: 'Premiumize fixture',
    publicConfig: const {},
    secretConfig: {'apiKey': apiKey},
  );
  await p.registry.bindResource(
    profileId: id,
    slot: 'provider.premiumize',
    resourceId: r.id,
  );
  await PremiumizeStorage.setPremiumizeIntegrationEnabled(true);
}

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  testWidgets(
    'independent pushed routes have distinct workflow and resource owners',
    (t) => premiumizeCase(t, (f) async {
      await f.mount(t);
      final old = f.access;
      final second = GlobalKey<State<PremiumizeFilesScreen>>();
      f.navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PremiumizeFilesScreen(key: second, isPushedRoute: true),
        ),
      );
      await t.pump();
      await f.until(
        t,
        () =>
            second.currentState != null &&
            premiumizeFilesTestAccess(second.currentState!)['initialLoad'] ==
                false,
      );
      final next = premiumizeFilesTestAccess(second.currentState!);
      for (final name in owners) {
        expect(identical(old[name], next[name]), isFalse, reason: name);
      }
      (next['toggleSelectionMode'] as VoidCallback)();
      await t.pump();
      expect(
        premiumizeFilesTestAccess(second.currentState!)['isSelectionMode'],
        isTrue,
      );
      expect(f.member('isSelectionMode'), isFalse);
      expect(f.log, [f.getRequest('folder/list'), f.getRequest('folder/list')]);
    }),
  );
  testWidgets(
    'profile gate remount uses captured A B credentials and fresh owners',
    (t) => premiumizeCase(t, (f) async {
      final p = ProfileFixture();
      await t.runAsync(p.open);
      try {
        await t.runAsync(() => bind(p, p.a, 'profile-A-key'));
        await t.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            home: ProfileGate(child: const PremiumizeFilesScreen()),
          ),
        );
        State<PremiumizeFilesScreen> state() =>
            t.state<State<PremiumizeFilesScreen>>(
              find.byType(PremiumizeFilesScreen),
            );
        dynamic member(String name) => premiumizeFilesTestAccess(state())[name];
        await f.until(
          t,
          () =>
              find.byType(PremiumizeFilesScreen).evaluate().isNotEmpty &&
              member('initialLoad') == false,
        );
        final oldState = state(), old = premiumizeFilesTestAccess(state());
        expect(f.requests.single.url.queryParameters, {
          'apikey': 'profile-A-key',
        });
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
          await bind(p, b, 'profile-B-key');
        });
        await t.pump();
        await f.until(
          t,
          () =>
              find.byType(PremiumizeFilesScreen).evaluate().isNotEmpty &&
              !identical(state(), oldState) &&
              member('initialLoad') == false,
        );
        expect(oldState.mounted, isFalse);
        for (final name in owners) {
          expect(identical(old[name], member(name)), isFalse, reason: name);
        }
        expect(f.requests.map((r) => r.url.queryParameters), [
          {'apikey': 'profile-A-key'},
          {'apikey': 'profile-B-key'},
        ]);
        expect(f.requests.map((r) => (r.method, r.url.path, r.body)), [
          ('GET', '/api/folder/list', ''),
          ('GET', '/api/folder/list', ''),
        ]);
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(p.close);
        ProfileRuntime.initializeLegacy();
      }
    }),
  );
  testWidgets(
    'stable committed profile playlist persists only to originating profile',
    (t) => premiumizeCase(t, (f) async {
      final p = ProfileFixture();
      await t.runAsync(p.open);
      try {
        await t.runAsync(() => bind(p, p.a, 'profile-A-key'));
        await f.mount(t);
        await t.runAsync(
          () =>
              f.member('addFileToPlaylist')(premiumizeItem('a2'))
                  as Future<void>,
        );
        final saved = await t.runAsync(PlaylistStorage.getPlaylistItemsRaw);
        expect(saved!.single['premiumizeItemId'], 'a2');
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
        });
        expect(await t.runAsync(PlaylistStorage.getPlaylistItemsRaw), isEmpty);
        expect(f.requests.single.url.queryParameters, {
          'apikey': 'profile-A-key',
        });
      } finally {
        await t.pumpWidget(const SizedBox.shrink());
        await t.runAsync(p.close);
        ProfileRuntime.initializeLegacy();
      }
    }),
  );
}
