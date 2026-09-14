import 'webdav_sync_binding_store.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_engine_state.dart';
import 'webdav_sync_transport.dart';

class WebDavSyncDeviceRemovedException implements Exception {
  const WebDavSyncDeviceRemovedException();
  static const message = 'This device was removed. Sign in again to reconnect.';
  @override
  String toString() => message;
}

/// Permanent, authenticated retirement of a device identity. Records live
/// outside devices/ so deleting all of a device's files cannot undo removal.
abstract final class WebDavSyncDeviceRemoval {
  static Future<bool> isRemoved({
    required WebDavSyncTransport transport,
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
  }) async {
    if (transport is! WebDavSyncDeviceRemovalTransport) return false;
    final bytes = await (transport as WebDavSyncDeviceRemovalTransport)
        .readDeviceRemoval(deviceId);
    if (bytes == null) return false;
    final value = await codec.openDocument(
      key: root.key,
      encoded: bytes.bytes,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'device-removal',
      schemaVersion: 1,
      maxBytes: 4096,
    );
    if (value is! Map || value['removed'] != true) {
      throw const FormatException('Invalid device removal record');
    }
    return true;
  }

  static Future<void> guard({
    required WebDavSyncTransport transport,
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
    Future<void> Function()? onRemoved,
  }) async {
    Future<void> check() async {
      if (await isRemoved(
        transport: transport,
        codec: codec,
        root: root,
        deviceId: deviceId,
      )) {
        await onRemoved?.call();
        throw const WebDavSyncDeviceRemovedException();
      }
    }

    // Install before the first read so later PUT retries/MKCOLs also check.
    if (transport is WebDavSyncDeviceRemovalTransport) {
      (transport as WebDavSyncDeviceRemovalTransport).setDeviceWriteGuard(
        deviceId,
        check,
      );
    }
    await check();
  }

  static Future<void> publish({
    required WebDavSyncTransport transport,
    required WebDavSyncCodec codec,
    required OpenedWebDavSyncRoot root,
    required String deviceId,
  }) async {
    if (transport is! WebDavSyncDeviceRemovalTransport) {
      throw StateError('This connection does not support device removal');
    }
    if (await isRemoved(
      transport: transport,
      codec: codec,
      root: root,
      deviceId: deviceId,
    )) {
      return;
    }
    final bytes = await codec.sealDocument(
      key: root.key,
      circleId: root.document.circleId,
      deviceId: deviceId,
      logicalName: 'device-removal',
      schemaVersion: 1,
      payload: const {'removed': true},
      maxBytes: 4096,
    );
    await (transport as WebDavSyncDeviceRemovalTransport).writeDeviceRemoval(
      deviceId,
      bytes,
    );
    if (!await isRemoved(
      transport: transport,
      codec: codec,
      root: root,
      deviceId: deviceId,
    )) {
      throw StateError('Could not verify device removal. Please try again.');
    }
  }

  static Future<void> retireLocal({
    required WebDavSyncBindingStore store,
    required WebDavSyncEngineStateRepository states,
    required String bindingId,
    required String deviceId,
  }) async {
    await store.removeDeviceSession(
      bindingId,
      deviceId,
      forgetState: (namespace) async {
        if (states is WebDavSyncEngineStateStore) {
          await states.forgetLoggedOutNamespace(namespace);
        } else {
          await states.update(
            namespace.id,
            (_) => const WebDavSyncEngineState(),
          );
        }
      },
    );
  }
}
