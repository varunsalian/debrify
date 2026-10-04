import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:debrify/models/webdav_item.dart';
import 'package:debrify/services/profiles/device_key_provider.dart';
import 'package:debrify/services/profiles/profile_preferences.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_binding_store.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_engine_state.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_models.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_tombstones.dart';

/// Uses the real file-backed sync state; no recorder sink substitutes for writes.
class PlaylistContentProfiles {
  final a = ProfileScope(
    profileId: 'playlist-A',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final b = ProfileScope(
    profileId: 'playlist-B',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  late Directory directory;
  late WebDavSyncBindingStore bindings;
  late WebDavSyncEngineStateStore engine;
  late String namespace;
  Future<void> open() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(a);
    ProfilePreferences.debugResetMutationTracking();
    DeviceKeyProvider.debugInstallCipher(
      MemoryDeviceSecretCipher(List<int>.filled(32, 4)),
    );
    directory = await Directory.systemTemp.createTemp('playlist-content-sync-');
    bindings = WebDavSyncBindingStore(
      randomBytes: (length) =>
          Uint8List.fromList(List<int>.generate(length, (i) => i)),
    );
    engine = WebDavSyncEngineStateStore(
      bindingStore: bindings,
      directoryProvider: () async => directory,
    );
    WebDavSyncTombstoneRecorder.debugInstall(
      bindingStore: bindings,
      stateRepository: engine,
    );
    const config = WebDavConfig(
      id: 'sync-server',
      name: 'Sync',
      baseUrl: 'https://sync.test/dav',
      username: 'fixture',
      password: 'fixture',
    );
    final staged = await bindings.stageBinding(
      location: WebDavSyncFolderLocation.fromConfig(config, 'Family'),
      config: config,
      syncPassphrase: 'fixture-passphrase',
    );
    final verified = await bindings.markRootVerified(
      bindingId: staged.id,
      root: WebDavSyncRootDocument(
        circleId: 'playlist-content-circle',
        createdAt: DateTime.utc(2026, 1, 1),
        schemaFloor: 1,
        kdfSalt: Uint8List(16),
      ),
      markerBytes: [1, 2, 3],
    );
    await bindings.setLifecycle(verified.id, WebDavSyncLifecycle.active);
    await bindings.promoteStaged(verified.id);
    namespace = (await bindings.load()).activeBinding!.namespaceId;
  }

  void switchTo(ProfileScope scope) => ProfileRuntime.publish(scope);
  Future<Set<String>> tombstones(String profile) async {
    // Reopening the store verifies durable state rather than its in-memory view.
    final reopened = WebDavSyncEngineStateStore(
      bindingStore: bindings,
      directoryProvider: () async => directory,
    );
    final state = await reopened.load(namespace);
    return state.pendingLocalProfiles[profile]?.tombstones.keys.toSet() ?? {};
  }

  Future<void> close() async {
    WebDavSyncTombstoneRecorder.debugReset();
    DeviceKeyProvider.debugReset();
    ProfilePreferences.debugResetMutationTracking();
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    await directory.delete(recursive: true);
  }
}

/// Hold the await continuation of the real JSON decode, after the scoped read
/// has produced A's list but before the caller can reacquire preferences to save.
/// This uses Dart's existing Zone boundary and never adds a production hook.
class PlaylistContentReadBarrier {
  final reached = Completer<void>();
  final release = Completer<void>();
  bool captured = false;
  Future<void> run(Future<void> Function() action) => runZoned(
    action,
    zoneSpecification: ZoneSpecification(
      registerUnaryCallback:
          <R, T>(self, parent, zone, R Function(T) callback) {
            return parent.registerUnaryCallback(zone, (T value) {
              if (!captured &&
                  value is List &&
                  value.isNotEmpty &&
                  value.first is Map &&
                  (value.first as Map)['title'] == 'A-read-boundary') {
                captured = true;
                reached.complete();
                release.future.then((_) {
                  callback(value);
                });
                return null as R;
              }
              return callback(value);
            });
          },
    ),
  );
}
