import 'dart:convert';
import 'dart:io';

import 'package:debrify/models/profiles/connection_resource.dart';
import 'package:debrify/models/profiles/profile_policy.dart';
import 'package:debrify/screens/settings/indexer_managers_settings_page.dart';
import 'package:debrify/screens/settings/iptv_settings_page.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_catalog_db.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/connection_resource_service.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_authorization.dart';
import 'package:debrify/services/profiles/profile_bootstrap.dart';
import 'package:debrify/services/profiles/profile_registry.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProfileRegistry registry;
  late MemoryDeviceSecretCipher cipher;
  late ConnectionResourceService service;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    DeviceKeyProvider.debugReset();
    directory = await Directory.systemTemp.createTemp(
      'credential-editor-repair-',
    );
    AppStorage.debugOverride(
      documents: directory,
      support: directory,
      cache: directory,
    );
    IptvCatalogDb.debugDirectoryOverride = directory.path;
    registry = await ProfileRegistry.open(
      path: p.join(directory.path, 'profiles.db'),
    );
    final owner = await registry.createProfile(
      name: 'Owner',
      role: UserProfileRole.admin,
    );
    await registry.commitBootstrap(
      activeProfileId: owner.id,
      migratedLegacyInstall: false,
    );
    cipher = MemoryDeviceSecretCipher(List<int>.generate(32, (i) => i + 1));
    service = ConnectionResourceService(registry: registry, cipher: cipher);
    DeviceKeyProvider.debugInstallCipher(cipher);
    ProfileBootstrap.debugInstallRegistry(registry);
    ProfileRuntime.initializeCommitted(
      ProfileScope(profileId: owner.id, dataGeneration: 1, sessionEpoch: 1),
    );
  });

  tearDown(() async {
    await DebrifyTvDatabase.instance.closeScope();
    IptvMediaStore.debugResetMigration();
    IptvCatalogDb.debugClose();
    IptvCatalogDb.debugDirectoryOverride = null;
    ProfileRuntime.debugReset();
    ProfileBootstrap.debugInstallRegistry(null);
    DeviceKeyProvider.debugReset();
    AppStorage.debugReset();
    await registry.close();
    await directory.delete(recursive: true);
  });

  Future<ConnectionResource> seed(
    ConnectionResourceType type,
    String label, {
    required bool pending,
  }) async {
    final resource = await service.create(
      context: await ProfileAuthorizationContext.capture(registry),
      type: type,
      label: label,
      publicConfig: {},
      secretConfig: {'old': 'credential'},
    );
    if (pending) {
      final observed = (await registry.readRegistrySyncProjection()).resources
          .singleWhere((entry) => entry.resource.id == resource.id);
      final result = await registry.applySyncedRegistryDelta(
        SyncedRegistryDelta(
          resources: [
            SyncedRegistryResourceRecord(
              resource: resource,
              updatedAtMs: 1,
              clearSecret: true,
              expectedPriorUpdatedAtMs: observed.updatedAtMs,
            ),
          ],
        ),
      );
      expect(result, SyncedRegistryApplyResult.applied);
      expect((await registry.getResource(resource.id))!.secretPending, isTrue);
      expect(await registry.getSealedResourceSecret(resource.id), isNull);
    } else {
      final wrongKey = MemoryDeviceSecretCipher(List<int>.filled(32, 99));
      final envelope = await wrongKey.seal(
        utf8.encode('{"old":"credential"}'),
        associatedData: ConnectionResourceService.associatedDataForSecret(
          resourceId: resource.id,
          type: type,
          ownerProfileId: resource.ownerProfileId,
          publicSchemaVersion: resource.publicSchemaVersion,
          payloadVersion: 1,
        ),
      );
      await registry.updateResourceSecret(
        resourceId: resource.id,
        sealedSecretPayload: envelope,
        secretPayloadVersion: 1,
      );
    }
    return resource;
  }

  // The screens use real registry IO; pumping only the fake clock cannot
  // complete SQLite operations. Keep frame scheduling outside runAsync.
  Future<void> settleIo(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final type in [
    ConnectionResourceType.jackett,
    ConnectionResourceType.prowlarr,
    ConnectionResourceType.iptvM3u,
  ]) {
    for (final pending in [false, true]) {
      testWidgets(
        '${type.name} editor repairs ${pending ? 'pending' : 'unreadable'} credentials',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          late ConnectionResource target;
          late ConnectionResource sibling;
          late String siblingEnvelope;
          await tester.runAsync(() async {
            target = await seed(type, 'AAA Repair me', pending: pending);
            sibling = await seed(type, 'ZZZ Untouched', pending: false);
            siblingEnvelope = (await registry.getSealedResourceSecret(
              sibling.id,
            ))!.envelope;
            if (type == ConnectionResourceType.iptvM3u) {
              await IptvCatalogDb.open();
              // Open the media database outside the widget fake clock.
              await StorageService.getIptvLists();
              await StorageService.setIptvDefaultPlaylist(target.id);
            }
          });
          final isIptv = type == ConnectionResourceType.iptvM3u;
          await tester.pumpWidget(
            MaterialApp(
              home: isIptv
                  ? const IptvSettingsPage()
                  : const IndexerManagersSettingsPage(),
            ),
          );
          await settleIo(tester);
          expect(tester.takeException(), isNull);
          await tester.tap(
            isIptv ? find.text('Edit source') : find.byTooltip('Edit').first,
          );
          await settleIo(tester);
          final dialog = find.byType(Dialog);
          final urlField = find.descendant(
            of: dialog,
            matching: find.widgetWithText(
              TextField,
              isIptv ? 'Playlist URL' : 'Base URL',
            ),
          );
          await tester.enterText(
            urlField,
            isIptv
                ? 'https://repaired.invalid/channels.m3u'
                : 'https://repaired.invalid',
          );
          if (!isIptv) {
            await tester.enterText(
              find.descendant(
                of: dialog,
                matching: find.widgetWithText(TextField, 'API key'),
              ),
              'replacement-key',
            );
          }
          await tester.pump();
          await tester.tap(
            find.descendant(of: dialog, matching: find.text('Save')),
          );
          await settleIo(tester);
          expect(tester.takeException(), isNull);
          await tester.runAsync(() async {
            final repaired = (await registry.getResource(target.id))!;
            expect(repaired.needsReconnect, isFalse);
            final secret = await service.resolveSecretForUse(
              context: await ProfileAuthorizationContext.capture(registry),
              resourceId: target.id,
              feature: isIptv
                  ? ProfileFeature.iptv
                  : ProfileFeature.torrentSearch,
            );
            if (isIptv) {
              expect(secret['url'], 'https://repaired.invalid/channels.m3u');
            } else {
              expect(secret['base_url'], 'https://repaired.invalid');
              expect(secret['api_key'], 'replacement-key');
            }
            expect(
              secret['_connectionResourceCredentialsRedacted'],
              isNot(true),
            );
            expect(
              (await registry.getSealedResourceSecret(sibling.id))!.envelope,
              siblingEnvelope,
            );
            expect(
              (await registry.getResource(sibling.id))!.needsReconnect,
              isTrue,
            );
          });
          await tester.pumpWidget(const SizedBox.shrink());
          await settleIo(tester);
          await tester.runAsync(() => DebrifyTvDatabase.instance.closeScope());
        },
      );
    }
  }
}
