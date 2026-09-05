import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_clock.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_circle_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_merge.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_hot_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late WebDavSyncBindingStore bindingStore;
  late WebDavSyncEngineStateStore engineStore;
  late Directory stateDirectory;

  setUp(() async {
    ProfileRuntime.debugReset();
    ProfilePreferences.debugResetMutationTracking();
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 4)),
    );
    bindingStore = WebDavSyncBindingStore(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (index) => index)),
    );
    stateDirectory = await Directory.systemTemp.createTemp(
      'debrify-webdav-sync-state-',
    );
    engineStore = WebDavSyncEngineStateStore(
      bindingStore: bindingStore,
      directoryProvider: () async => stateDirectory,
    );
    WebDavSyncTombstoneRecorder.debugInstall(
      bindingStore: bindingStore,
      stateRepository: engineStore,
    );
  });

  tearDown(() async {
    ProfileRuntime.debugReset();
    ProfilePreferences.webDavSyncLocalChangeSink = null;
    WebDavSyncTombstoneRecorder.debugReset();
    DeviceKeyProvider.debugReset();
    if (await stateDirectory.exists()) {
      await stateDirectory.delete(recursive: true);
    }
  });

  test(
    'an unbound oversized delete set is ignored without inspection',
    () async {
      var enumerated = false;

      await WebDavSyncTombstoneRecorder.recordForProfile(
        'local-profile',
        () sync* {
          enumerated = true;
          for (
            var index = 0;
            index <= WebDavSyncLimits.maxTombstonesPerProfile;
            index++
          ) {
            yield 'key-$index';
          }
        }(),
      );

      expect(enumerated, isFalse);
    },
  );

  test(
    'registry tombstones are durable and keep local record identity',
    () async {
      final binding = await _activateBinding(
        bindingStore,
        circleId: 'circle-registry-tombstones',
      );
      final registryStore = WebDavSyncRegistryTombstoneStore(
        bindingStore: bindingStore,
        directoryProvider: () async => stateDirectory,
      );
      WebDavSyncTombstoneRecorder.debugInstall(
        bindingStore: bindingStore,
        stateRepository: engineStore,
        registryRepository: registryStore,
      );
      final records = <WebDavSyncRegistryRecordId>{
        WebDavSyncRegistryRecordId.profile('local-profile'),
        WebDavSyncRegistryRecordId.resource(
          'local-resource',
          ownerProfileId: 'local-profile',
        ),
        WebDavSyncRegistryRecordId.grant('local-profile', 'local-resource'),
      };

      await WebDavSyncTombstoneRecorder.recordRegistryRecords(records);

      var persisted =
          await WebDavSyncTombstoneRecorder.loadRegistryRecordTombstones();
      expect(persisted.values.map((item) => item.record).toSet(), records);
      expect(persisted.values.every((item) => item.timeMs > 0), isTrue);
      final snapshot = await bindingStore.load();
      expect(
        snapshot
            .namespaces[binding.namespaceId]!
            .values[WebDavSyncRegistryTombstoneStore.valueKey],
        const <String, Object>{'version': 1, 'storage': 'file'},
      );

      WebDavSyncTombstoneRecorder.debugReset();
      WebDavSyncTombstoneRecorder.debugInstall(
        bindingStore: bindingStore,
        stateRepository: engineStore,
        registryRepository: WebDavSyncRegistryTombstoneStore(
          bindingStore: bindingStore,
          directoryProvider: () async => stateDirectory,
        ),
      );
      persisted =
          await WebDavSyncTombstoneRecorder.loadRegistryRecordTombstones();
      expect(persisted.values.map((item) => item.record).toSet(), records);
    },
  );

  test('registry tombstone store keeps the newest concurrent stamp', () async {
    final binding = await _activateBinding(
      bindingStore,
      circleId: 'circle-monotonic-registry-tombstones',
    );
    final store = WebDavSyncRegistryTombstoneStore(
      bindingStore: bindingStore,
      directoryProvider: () async => stateDirectory,
    );
    final record = WebDavSyncRegistryRecordId.profile('same-profile');

    await Future.wait<void>(<Future<void>>[
      store.record(
        binding.namespaceId,
        deviceId: 'device-z',
        records: <WebDavSyncRegistryRecordId>{record},
        nowMs: 100,
      ),
      store.record(
        binding.namespaceId,
        deviceId: 'device-a',
        records: <WebDavSyncRegistryRecordId>{record},
        nowMs: 200,
      ),
      store.record(
        binding.namespaceId,
        deviceId: 'device-z',
        records: <WebDavSyncRegistryRecordId>{record},
        nowMs: 200,
      ),
    ]);

    final persisted = (await store.load(
      binding.namespaceId,
    ))[record.storageKey]!;
    expect(persisted.timeMs, 200);
    expect(persisted.originDeviceId, 'device-z');
  });

  test(
    'registry tombstone normalization is frozen in the file store',
    () async {
      final binding = await _activateBinding(
        bindingStore,
        circleId: 'circle-frozen-registry-tombstones',
      );
      final store = WebDavSyncRegistryTombstoneStore(
        bindingStore: bindingStore,
        directoryProvider: () async => stateDirectory,
      );
      final record = WebDavSyncRegistryRecordId.grant(
        'local-profile',
        'local-resource',
      );
      await store.record(
        binding.namespaceId,
        deviceId: 'device-a',
        records: <WebDavSyncRegistryRecordId>{record},
        nowMs: 100,
      );

      final first = (await store.freeze(
        binding.namespaceId,
        clockOffsetMs: 50,
        serverNowMs: 1000,
      ))[record.storageKey]!;
      // A crash between the durable file write and SQL outbox deletion can
      // replay the exact raw batch. It must not unfreeze the stored stamp.
      await store.record(
        binding.namespaceId,
        deviceId: 'device-a',
        records: <WebDavSyncRegistryRecordId>{record},
        nowMs: 100,
      );
      final second = (await store.freeze(
        binding.namespaceId,
        clockOffsetMs: 500,
        serverNowMs: 1000,
      ))[record.storageKey]!;
      final reloaded = (await store.load(
        binding.namespaceId,
      ))[record.storageKey]!;

      expect(first.normalizedTimeFrozen, isTrue);
      expect(first.timeMs, 150);
      expect(second.timeMs, 150);
      expect(reloaded.normalizedTimeFrozen, isTrue);
      expect(reloaded.timeMs, 150);
    },
  );

  test('recorded deletes notify only while a sync binding exists', () async {
    final notifications = <(String, String)>[];
    ProfilePreferences.webDavSyncLocalChangeSink = (profileId, key) {
      notifications.add((profileId, key));
    };
    const key = 'movie:tt-local-change';

    await WebDavSyncTombstoneRecorder.recordForProfile(
      'local-profile',
      const <String>{key},
    );
    expect(notifications, isEmpty);

    await _activateBinding(bindingStore, circleId: 'circle-local-change');
    await WebDavSyncTombstoneRecorder.recordForProfile(
      'local-profile',
      const <String>{key},
    );

    expect(notifications, <(String, String)>[('local-profile', key)]);
  });

  test('recorder is inert before Active and mapped afterwards', () async {
    const config = WebDavConfig(
      id: 'server',
      name: 'Server',
      baseUrl: 'https://example.test/dav',
      username: 'alice',
      password: 'secret',
    );
    final binding = await bindingStore.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(config, 'Family'),
      config: config,
      syncPassphrase: 'circle-secret',
    );
    final key = WebDavSyncRecordKey.finishedMovie('tt1');

    await WebDavSyncTombstoneRecorder.recordForProfile(
      'local-profile',
      <String>{key},
    );
    expect((await engineStore.load(binding.namespaceId)).profiles, isEmpty);

    final verified = await bindingStore.markRootVerified(
      bindingId: binding.id,
      root: WebDavSyncRootDocument(
        circleId: 'circle-1',
        createdAt: DateTime.utc(2026, 9, 1),
        schemaFloor: 1,
        kdfSalt: Uint8List(16),
      ),
      markerBytes: const <int>[1, 2, 3],
    );
    await bindingStore.setLifecycle(verified.id, WebDavSyncLifecycle.active);
    await bindingStore.promoteStaged(verified.id);
    final namespaceId = 'circle:circle-1';

    final unmappedKey = WebDavSyncRecordKey.finishedMovie('tt-unmapped');
    await WebDavSyncTombstoneRecorder.recordForProfile(
      'local-profile',
      <String>{unmappedKey},
    );
    var state = await engineStore.load(namespaceId);
    expect(
      state.pendingLocalProfiles['local-profile']!.tombstones,
      contains(unmappedKey),
    );

    await engineStore.update(
      namespaceId,
      (state) => state.copyWith(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'local-profile',
        },
        circleToLocalResources: const <String, String>{},
      ),
    );

    await WebDavSyncTombstoneRecorder.recordForProfile(
      'local-profile',
      <String>{key},
    );
    state = await engineStore.load(namespaceId);
    final tombstone = state.profiles['profile-circle']!.tombstones[key]!;

    expect(tombstone.rawLocalTime, isTrue);
    expect(tombstone.pendingPublication, isTrue);

    await bindingStore.markError(verified.id, 'temporary authentication error');
    final errorKey = WebDavSyncRecordKey.finishedMovie('tt-error');
    await WebDavSyncTombstoneRecorder.recordForProfile(
      'local-profile',
      <String>{errorKey},
    );
    expect(
      (await engineStore.load(
        namespaceId,
      )).profiles['profile-circle']!.tombstones,
      contains(errorKey),
    );
  });

  test(
    'isolated journal writes serialize concurrent updates and reject corrupt candidates',
    () async {
      final binding = await _activateBinding(
        bindingStore,
        circleId: 'circle-journal',
      );
      final other = WebDavSyncEngineStateStore(
        bindingStore: bindingStore,
        directoryProvider: () async => stateDirectory,
      );
      await engineStore.update(
        binding.namespaceId,
        (state) => state.copyWith(lastSuccessfulSyncMs: 0),
      );
      await Future.wait([
        for (var i = 0; i < 12; i++)
          (i.isEven ? engineStore : other).update(
            binding.namespaceId,
            (state) => state.copyWith(
              lastSuccessfulSyncMs: state.lastSuccessfulSyncMs! + 1,
            ),
          ),
      ]);
      expect((await other.load(binding.namespaceId)).lastSuccessfulSyncMs, 12);
      await expectLater(
        engineStore.update(
          binding.namespaceId,
          (state) => state.copyWith(lastSuccessfulSyncMs: -1),
        ),
        throwsFormatException,
      );
      expect(
        (await other.load(binding.namespaceId)).lastSuccessfulSyncMs,
        12,
        reason:
            'failed worker validation must not replace the last good journal',
      );
    },
  );

  test('engine state is file-backed and missing state fails closed', () async {
    const config = WebDavConfig(
      id: 'server',
      name: 'Server',
      baseUrl: 'https://example.test/dav',
      username: 'alice',
      password: 'secret',
    );
    final binding = await bindingStore.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(config, 'Family'),
      config: config,
      syncPassphrase: 'circle-secret',
    );
    await engineStore.update(
      binding.namespaceId,
      (state) => state.copyWith(
        circleToLocalProfiles: const <String, String>{
          'profile-circle': 'local-profile',
        },
        circleToLocalResources: const <String, String>{},
      ),
    );

    final snapshot = await bindingStore.load();
    final marker = snapshot
        .namespaces[binding.namespaceId]!
        .values[WebDavSyncEngineStateStore.valueKey];
    expect(marker, <String, Object>{'version': 1, 'storage': 'file'});
    expect(marker.toString(), isNot(contains('local-profile')));
    final files = await stateDirectory
        .list(recursive: true)
        .where((entity) => entity is File && entity.path.endsWith('.json'))
        .cast<File>()
        .toList();
    expect(files, hasLength(1));
    expect(await files.single.readAsString(), contains('local-profile'));
    expect(
      (await engineStore.load(binding.namespaceId)).circleToLocalProfiles,
      const <String, String>{'profile-circle': 'local-profile'},
    );

    final verified = await bindingStore.markRootVerified(
      bindingId: binding.id,
      root: WebDavSyncRootDocument(
        circleId: 'circle-file-state',
        createdAt: DateTime.utc(2026, 9, 1),
        schemaFloor: 1,
        kdfSalt: Uint8List(16),
      ),
      markerBytes: const <int>[4, 5, 6],
    );
    expect(
      (await engineStore.load(verified.namespaceId)).circleToLocalProfiles,
      const <String, String>{'profile-circle': 'local-profile'},
    );

    await files.single.delete();
    await expectLater(
      engineStore.load(verified.namespaceId),
      throwsA(isA<WebDavSyncEngineStateMissingException>()),
    );

    await engineStore.initializeMissingForReconnect(verified.namespaceId);
    final reconnected = await engineStore.load(verified.namespaceId);
    expect(reconnected.hasAuthenticatedMaps, isFalse);
    await expectLater(
      engineStore.initializeMissingForReconnect(verified.namespaceId),
      throwsStateError,
    );
  });

  test(
    'a full tombstone journal degrades sync without blocking local deletion',
    () async {
      final binding = await _activateBinding(
        bindingStore,
        circleId: 'circle-limit',
      );
      final tombstones = <String, WebDavSyncTombstone>{
        for (
          var index = 0;
          index < WebDavSyncLimits.maxTombstonesPerProfile;
          index++
        )
          'key-$index': WebDavSyncTombstone(
            key: 'key-$index',
            stamp: const WebDavSyncStamp(
              normalizedTimeMs: 1,
              originDeviceId: 'device-a',
            ),
            rawLocalTime: true,
          ),
      };
      await engineStore.update(
        binding.namespaceId,
        (state) => state.copyWith(
          circleToLocalProfiles: const <String, String>{
            'profile-circle': 'local-profile',
          },
          circleToLocalResources: const <String, String>{},
          profiles: <String, WebDavSyncProfileEngineState>{
            'profile-circle': WebDavSyncProfileEngineState(
              tombstones: tombstones,
            ),
          },
        ),
      );

      await WebDavSyncTombstoneRecorder.recordForProfile(
        'local-profile',
        const <String>{'one-too-many'},
      );

      final state = await engineStore.load(binding.namespaceId);
      expect(
        state.profiles['profile-circle']!.tombstones,
        hasLength(WebDavSyncLimits.maxTombstonesPerProfile),
      );
      expect(
        state.profiles['profile-circle']!.tombstones,
        isNot(contains('one-too-many')),
      );
      final degraded = (await bindingStore.load()).activeBinding!;
      expect(degraded.lifecycle, WebDavSyncLifecycle.error);
      expect(degraded.errorMessage, contains('safe limit'));
    },
  );

  test('playback deletion keys match the merge parser guards', () async {
    ProfileRuntime.initializeCommitted(
      ProfileScope(
        profileId: 'local-profile',
        dataGeneration: 1,
        sessionEpoch: 1,
      ),
    );
    final prefs = await ProfilePreferences.instance();
    await prefs.setString(
      WebDavSyncHotMerge.playbackPreference,
      jsonEncode(<String, Object?>{
        'series-alias': <String, Object?>{
          'type': 'series',
          'imdbId': 'tt-guard',
          'seasons': <String, Object?>{
            '-1': <String, Object?>{
              '1': <String, Object?>{'positionMs': 1},
            },
            '1': <String, Object?>{
              '-1': <String, Object?>{'positionMs': 1},
              '2': 'not-an-episode-map',
              '3': <String, Object?>{'positionMs': 1},
            },
          },
        },
      }),
    );
    final recorded = <String>{};
    WebDavSyncTombstoneRecorder.debugInstall(
      sink: (_, keys) => recorded.addAll(keys),
    );

    await StorageService.clearPlaybackStateByImdbId('tt-guard');

    expect(
      recorded,
      contains(WebDavSyncRecordKey.playbackMeta('series-alias')),
    );
    expect(
      recorded,
      contains(WebDavSyncRecordKey.playbackEpisode('series-alias', 1, 3)),
    );
    expect(
      recorded,
      isNot(
        contains(WebDavSyncRecordKey.playbackEpisode('series-alias', -1, 1)),
      ),
    );
    expect(
      recorded,
      isNot(
        contains(WebDavSyncRecordKey.playbackEpisode('series-alias', 1, -1)),
      ),
    );
    expect(
      recorded,
      isNot(
        contains(WebDavSyncRecordKey.playbackEpisode('series-alias', 1, 2)),
      ),
    );
  });

  test('bootstrap and circle state round-trips with strict digests', () {
    const stamp = WebDavSyncStamp(
      normalizedTimeMs: 42,
      originDeviceId: 'device-a',
    );
    const circleProfiles = WebDavSyncProfilesDocument(
      profiles: <String, WebDavSyncCircleLeaf<WebDavSyncProfileValue>>{
        'circle-profile': WebDavSyncCircleLeaf<WebDavSyncProfileValue>(
          stamp: stamp,
          value: null,
        ),
      },
    );
    const circleResources = WebDavSyncResourcesDocument(
      resources: <String, WebDavSyncResourceEntry>{
        'circle-resource': WebDavSyncResourceEntry(
          metadata: WebDavSyncCircleLeaf<WebDavSyncResourceMetadata>(
            stamp: stamp,
            value: null,
          ),
        ),
      },
      grants:
          <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncGrantValue>>>{},
      settings:
          <
            String,
            Map<String, WebDavSyncCircleLeaf<WebDavSyncSettingsValue>>
          >{},
      bindings:
          <String, Map<String, WebDavSyncCircleLeaf<WebDavSyncBindingValue>>>{},
    );
    final source = WebDavSyncEngineState(
      lastPushMs: 50,
      lastRemoteChangeMs: 75,
      lastBootstrapCheckMs: 200,
      publishedBootstrapDatabaseDigest: 'c' * 64,
      currentDeviceIds: const <String>{'device-a', 'device-b'},
      peerManifestValidators: const <String, WebDavSyncManifestValidator>{
        'device-b': WebDavSyncManifestValidator.etag('"revision-1"'),
      },
      deviceClockWarning: true,
      lastClockPauseReason: WebDavSyncClockPauseReason.offsetOutlier,
      circleProfilesBaseline: circleProfiles,
      circleResourcesBaseline: circleResources,
      pendingCircleApply: const WebDavSyncPendingCircleApply(
        profiles: circleProfiles,
        resources: circleResources,
      ),
      lastPushedProfilesDigest: 'e' * 64,
      lastPushedResourcesDigest: 'f' * 64,
      pendingActiveProfile: WebDavSyncPendingActiveProfile(
        localProfileId: 'local-retired-profile',
        circleProfileId: 'circle-profile',
        reason: WebDavSyncPendingActiveProfileReason.deleted,
        profileLeaf: circleProfiles.profiles['circle-profile'],
        expectedPriorUpdatedAtMs: 41,
      ),
      pendingAdminSafetyProfile: 'local-admin',
      statusHint: 'sync kept Local Admin as Admin on this device',
    );

    final legacyJson = <String, Object?>{
      ...source.toJson(),
      'lastGraphCheckMs': 100,
      'appliedGraphDigest': 'a' * 64,
      'pendingGraphDigest': 'b' * 64,
      'declinedGraphDigests': <String>['d' * 64],
    };
    final restored = WebDavSyncEngineState.fromJson(legacyJson);

    expect(restored.lastPushMs, 50);
    expect(restored.lastRemoteChangeMs, 75);
    expect(restored.lastBootstrapCheckMs, 200);
    expect(restored.publishedBootstrapDatabaseDigest, 'c' * 64);
    expect(restored.deviceClockWarning, isTrue);
    expect(restored.currentDeviceIds, const <String>{'device-a', 'device-b'});
    expect(
      restored.peerManifestValidators['device-b'],
      const WebDavSyncManifestValidator.etag('"revision-1"'),
    );
    expect(
      restored.lastClockPauseReason,
      WebDavSyncClockPauseReason.offsetOutlier,
    );
    expect(restored.circleProfilesBaseline?.toJson(), circleProfiles.toJson());
    expect(
      restored.circleResourcesBaseline?.toJson(),
      circleResources.toJson(),
    );
    expect(restored.pendingCircleApply?.toJson(), {
      'profiles': circleProfiles.toJson(),
      'resources': circleResources.toJson(),
      'registryVersions': {
        'updatedAtMsByRecord': <String, Object?>{},
        'enforce': true,
      },
    });
    expect(restored.lastPushedProfilesDigest, 'e' * 64);
    expect(restored.lastPushedResourcesDigest, 'f' * 64);
    expect(restored.pendingActiveProfileDeletion, 'local-retired-profile');
    expect(
      restored.pendingActiveProfile?.reason,
      WebDavSyncPendingActiveProfileReason.deleted,
    );
    expect(restored.pendingActiveProfile?.expectedPriorUpdatedAtMs, 41);
    expect(restored.pendingAdminSafetyProfile, 'local-admin');
    expect(
      restored.statusHint,
      'sync kept Local Admin as Admin on this device',
    );
    expect(restored.toJson(), isNot(contains('lastGraphCheckMs')));
    expect(restored.toJson(), isNot(contains('appliedGraphDigest')));
    expect(restored.toJson(), isNot(contains('pendingGraphDigest')));
    expect(restored.toJson(), isNot(contains('declinedGraphDigests')));
    expect(
      () => WebDavSyncEngineState.fromJson(<String, Object?>{
        ...source.toJson(),
        'publishedBootstrapDatabaseDigest': 'not-a-digest',
      }),
      throwsFormatException,
    );
  });

  test(
    'engine state rejects oversized profile and peer maps before parsing',
    () {
      final oversized = <String, Object?>{
        for (var index = 0; index <= WebDavSyncLimits.maxMapEntries; index++)
          'id-$index': <String, Object?>{},
      };

      expect(
        () => WebDavSyncEngineState.fromJson(<String, Object?>{
          'version': 1,
          'profiles': oversized,
          'peerManifestHighWater': const <String, int>{},
        }),
        throwsFormatException,
      );
      expect(
        () => WebDavSyncEngineState.fromJson(<String, Object?>{
          'version': 1,
          'profiles': const <String, Object?>{},
          'peerManifestHighWater': <String, int>{
            for (
              var index = 0;
              index <= WebDavSyncLimits.maxMapEntries;
              index++
            )
              'peer-$index': index,
          },
        }),
        throwsFormatException,
      );
    },
  );

  test('peer history stays bounded while retaining currently listed peers', () {
    final source = <String, int>{
      for (var index = 0; index <= WebDavSyncLimits.maxMapEntries; index++)
        'peer-${index.toString().padLeft(4, '0')}': index,
    };

    final bounded = boundedPeerManifestHighWater(
      source,
      currentDeviceIds: const <String>['peer-0000'],
    );

    expect(bounded, hasLength(WebDavSyncLimits.maxMapEntries));
    expect(bounded, contains('peer-0000'));
    expect(bounded, isNot(contains('peer-0001')));
  });
}

Future<WebDavSyncBinding> _activateBinding(
  WebDavSyncBindingStore store, {
  required String circleId,
}) async {
  const config = WebDavConfig(
    id: 'server',
    name: 'Server',
    baseUrl: 'https://example.test/dav',
    username: 'alice',
    password: 'secret',
  );
  final staged = await store.stageBinding(
    location: WebDavSyncFolderLocation.fromConfig(config, 'Family'),
    config: config,
    syncPassphrase: 'circle-secret',
  );
  final verified = await store.markRootVerified(
    bindingId: staged.id,
    root: WebDavSyncRootDocument(
      circleId: circleId,
      createdAt: DateTime.utc(2026, 9, 1),
      schemaFloor: 1,
      kdfSalt: Uint8List(16),
    ),
    markerBytes: const <int>[1, 2, 3],
  );
  await store.setLifecycle(verified.id, WebDavSyncLifecycle.active);
  await store.promoteStaged(verified.id);
  return (await store.load()).activeBinding!;
}
