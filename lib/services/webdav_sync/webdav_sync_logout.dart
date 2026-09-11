import 'package:flutter/foundation.dart';

import '../webdav_protocol_client.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_transport.dart';

/// Missing registration metadata is the original, registered-device format.
/// An authenticated logout record retires the registration, not its data.
Future<bool> webDavSyncDeviceIsRegistered({
  required WebDavSyncTransport transport,
  required WebDavSyncCodec codec,
  required OpenedWebDavSyncRoot root,
  required String deviceId,
}) async {
  if (transport is! WebDavSyncRegistrationTransport) return true;
  final registration = transport as WebDavSyncRegistrationTransport;
  final bytes = await registration.readRegistration(deviceId);
  if (bytes == null) return true;
  final value = await codec.openDocument(
    key: root.key,
    encoded: bytes.bytes,
    circleId: root.document.circleId,
    deviceId: deviceId,
    logicalName: 'registration',
    schemaVersion: 1,
    maxBytes: 4096,
  );
  if (value is! Map || value['signedOut'] != true) {
    throw const FormatException('Invalid device registration');
  }
  return false;
}

typedef WebDavSyncLogoutTransportFactory =
    WebDavSyncTransport Function(
      WebDavSyncBinding binding,
      WebDavSyncSecrets secrets,
    );

/// Run under the runtime operation lock, with scheduler/transports stopped.
/// Remote failures retain the logout journal and credentials for an explicit
/// retry; a restart cannot silently register the device again. A missing root
/// needs no remote cleanup. Explicit local-only logout skips remote access.
final class WebDavSyncLogout {
  WebDavSyncLogout({
    required this.store,
    WebDavSyncCodec? codec,
    WebDavSyncLogoutTransportFactory? transportFactory,
  }) : codec = codec ?? WebDavSyncCodec(),
       transportFactory =
           transportFactory ??
           ((binding, secrets) => ProtocolWebDavSyncTransport(
             location: binding.location,
             credentials: WebDavCredentials(
               username: secrets.username,
               password: secrets.password,
             ),
           ));

  final WebDavSyncBindingStore store;
  final WebDavSyncCodec codec;
  final WebDavSyncLogoutTransportFactory transportFactory;

  Future<void> run({
    required Future<void> Function() authorize,
    bool localOnly = false,
    Future<void> Function(WebDavSyncNamespace)? forgetLocalNamespace,
  }) async {
    await authorize();
    final snapshot = await store.beginLogout();
    for (final binding
        in localOnly ? const <WebDavSyncBinding>[] : snapshot.bindings.values) {
      final namespace = snapshot.namespaceFor(binding);
      if (binding.circleId == null || namespace?.markerBytes == null) continue;
      final secrets = await store.readSecrets(binding);
      final transport = transportFactory(binding, secrets);
      try {
        if (transport is! WebDavSyncRegistrationTransport) {
          throw StateError('This connection cannot unregister devices');
        }
        final WebDavBytesResult rootBytes;
        try {
          rootBytes = await transport.readRootMarker();
        } on WebDavException catch (error) {
          // A deleted sync folder has no registration left to retire.
          if (error.kind == WebDavErrorKind.notFound) continue;
          rethrow;
        }
        if (!namespace!.matchesAuthority(rootBytes.bytes)) {
          throw StateError('The sync folder changed. Logout has been paused.');
        }
        final root = await codec.openRoot(
          webDavSyncInnerMarker(rootBytes.bytes),
          secrets.syncPassphrase,
          runInBackground: true,
        );
        // A setup that never published a manifest has no device to unregister.
        try {
          final manifestBytes = await transport.readManifest(
            namespace.deviceId,
          );
          WebDavSyncManifest.fromJson(
            await codec.openDocument(
              key: root.key,
              encoded: manifestBytes.bytes,
              circleId: root.document.circleId,
              deviceId: namespace.deviceId,
              logicalName: 'manifest',
              schemaVersion: WebDavSyncManifest.schemaVersion,
              maxBytes: WebDavSyncLimits.maxManifestBytes,
            ),
          );
        } on WebDavException catch (error) {
          if (error.kind == WebDavErrorKind.notFound) continue;
          rethrow;
        }
        await authorize();
        final registration = transport as WebDavSyncRegistrationTransport;
        final encoded = await codec.sealDocument(
          key: root.key,
          circleId: root.document.circleId,
          deviceId: namespace.deviceId,
          logicalName: 'registration',
          schemaVersion: 1,
          payload: const {'signedOut': true},
          maxBytes: 4096,
        );
        await registration.writeRegistration(namespace.deviceId, encoded);
        final verified = await registration.readRegistration(
          namespace.deviceId,
        );
        if (verified == null || !listEquals(verified.bytes, encoded)) {
          throw StateError('Could not confirm logout with the WebDAV server');
        }
      } catch (_) {
        await store.updateNamespaceValues(
          namespace!.id,
          (values) => {...values, 'logoutNeedsAttentionBindingId': binding.id},
        );
        rethrow;
      } finally {
        transport.close();
      }
    }
    await authorize();
    if (forgetLocalNamespace != null) {
      for (final namespace in snapshot.namespaces.values) {
        await forgetLocalNamespace(namespace);
      }
    }
    await authorize();
    await store.finishLogout();
  }
}
