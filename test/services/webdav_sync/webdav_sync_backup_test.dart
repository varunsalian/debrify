import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_backup.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_codec.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const config = WebDavConfig(
  id: 'server',
  name: 'Server',
  baseUrl: 'https://example.test/dav',
  username: 'user',
  password: 'password',
);

void main() {
  late Directory directory;
  late WebDavSyncBindingStore store;
  late WebDavSyncEngineStateStore states;
  late WebDavSyncBinding active;
  late Uint8List marker;
  final codec = WebDavSyncCodec();

  Future<WebDavSyncBinding> candidate(
    String folder, {
    bool verified = true,
  }) async {
    final binding = await store.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(config, folder),
      config: config,
      syncPassphrase: 'circle-secret',
    );
    if (!verified) return binding;
    final encoded = await codec.sealRoot(
      passphrase: 'circle-secret',
      circleId: folder,
      createdAt: DateTime.utc(2026),
      memoryKiB: 8,
      iterations: 1,
    );
    final root = await codec.openRoot(encoded, 'circle-secret');
    if (folder == 'working') marker = encoded;
    return store.markRootVerified(
      bindingId: binding.id,
      root: root.document,
      markerBytes: encoded,
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List.filled(32, 7)),
    );
    directory = await Directory.systemTemp.createTemp('sync-backup-review');
    store = WebDavSyncBindingStore();
    states = WebDavSyncEngineStateStore(
      bindingStore: store,
      directoryProvider: () async => directory,
    );
    active = await candidate('working');
    await states.update(
      active.namespaceId,
      (state) => state.copyWith(
        circleToLocalProfiles: {'circle-profile': 'local-profile'},
        circleToLocalResources: {},
      ),
    );
    active = await store.activateAndPromoteStaged(active.id);
  });
  tearDown(() async {
    DeviceKeyProvider.debugReset();
    await directory.delete(recursive: true);
  });

  for (final stage in ['configured', 'verified', 'awaiting']) {
    test('backup keeps working account while candidate is $stage', () async {
      final next = await candidate(
        'candidate',
        verified: stage != 'configured',
      );
      if (stage == 'awaiting') {
        await store.setLifecycle(next.id, WebDavSyncLifecycle.awaitingAdoption);
      }
      final backup = await WebDavSyncBackup.capture(
        store: store,
        states: states,
        profilesByLocalId: {'local-profile': 'profile-0'},
        resourcesByLocalId: {},
      );
      expect(backup.connection!['folder'], active.location.folderPath);
      expect(backup.connection!['enabled'], isTrue);
      expect(backup.profileIds, {'circle-profile': 'profile-0'});
    });
  }

  test('candidate preparation maps do not prove profile handoff', () async {
    final next = await candidate('candidate');
    await states.update(
      next.namespaceId,
      (state) => state.copyWith(
        circleToLocalProfiles: {'candidate-circle': 'local-profile'},
        circleToLocalResources: {},
      ),
    );
    await store.setLifecycle(next.id, WebDavSyncLifecycle.awaitingAdoption);
    final backup = await WebDavSyncBackup.capture(
      store: store,
      states: states,
      profilesByLocalId: {'local-profile': 'profile-0'},
      resourcesByLocalId: {},
    );
    expect(backup.connection!['folder'], active.location.folderPath);
    expect(backup.profileIds, {'circle-profile': 'profile-0'});
  });

  test(
    'staged handoff owns newly backed-up profiles before promotion',
    () async {
      final next = await candidate('candidate');
      await states.update(
        next.namespaceId,
        (state) => state.copyWith(
          circleToLocalProfiles: {'new-circle': 'new-local'},
          circleToLocalResources: {},
        ),
      );
      await store.setLifecycle(next.id, WebDavSyncLifecycle.awaitingAdoption);
      final backup = await WebDavSyncBackup.capture(
        store: store,
        states: states,
        profilesByLocalId: {'new-local': 'profile-0'},
        resourcesByLocalId: {},
      );
      expect(backup.connection!['folder'], next.location.folderPath);
      expect(backup.connection!['enabled'], isTrue);
      expect(backup.profileIds, {'new-circle': 'profile-0'});
    },
  );

  test(
    '1024 long resource identities survive restore and a new state-store instance',
    () async {
      final resources = {
        for (var i = 0; i < 1024; i++)
          'r${i.toString().padLeft(95, '0')}':
              'l${i.toString().padLeft(95, '0')}',
      };
      expect(utf8.encode(jsonEncode(resources)).length, greaterThan(64 * 1024));
      await store.restoreBackupConnection(
        config: config,
        folderPath: 'working',
        syncPassphrase: 'circle-secret',
        authorityBytes: marker,
        enabled: true,
        prepareState: (namespace) => states.prepareBackupState(
          namespace,
          profileIds: {'circle-profile': 'restored-local'},
          resourceIds: resources,
        ),
      );
      final snapshot = await store.load();
      final namespace = snapshot.namespaceFor(snapshot.stagedBinding!)!;
      expect(namespace.values['backupRestore'], isTrue);
      expect(namespace.values, isNot(contains('backupRestoreResourceIds')));
      expect(
        utf8
            .encode(
              (await SharedPreferences.getInstance()).getString(
                'webdav_sync_state_v1',
              )!,
            )
            .length,
        lessThan(64 * 1024),
      );
      final reopened = WebDavSyncEngineStateStore(
        bindingStore: WebDavSyncBindingStore(),
        directoryProvider: () async => directory,
      );
      final restored = await reopened.load(namespace.id);
      expect(restored.circleToLocalResources, resources);
      expect(restored.circleToLocalProfiles, {
        'circle-profile': 'restored-local',
      });
      expect(restored.ownManifest, isNull);
    },
  );

  test(
    'state file failure leaves the original binding and its data intact',
    () async {
      await expectLater(
        store.restoreBackupConnection(
          config: config,
          folderPath: 'working',
          syncPassphrase: 'circle-secret',
          authorityBytes: marker,
          enabled: true,
          prepareState: (_) async =>
              throw const FileSystemException('write failed'),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect((await store.load()).activeBindingId, active.id);
      expect((await states.load(active.namespaceId)).circleToLocalProfiles, {
        'circle-profile': 'local-profile',
      });
    },
  );
}
