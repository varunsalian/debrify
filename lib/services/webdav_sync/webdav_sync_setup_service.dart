import 'dart:convert';
import 'dart:typed_data';

import '../../models/webdav_item.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_models.dart';

sealed class WebDavSyncSetupException implements Exception {
  const WebDavSyncSetupException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class WebDavSyncRootMissingException extends WebDavSyncSetupException {
  const WebDavSyncRootMissingException()
    : super(
        'Previously verified sync data is missing from this WebDAV account',
      );
}

final class WebDavSyncRootChangedException extends WebDavSyncSetupException {
  const WebDavSyncRootChangedException()
    : super('The WebDAV sync data no longer matches this device');
}

final class WebDavSyncCredentialsUnavailableException
    extends WebDavSyncSetupException {
  const WebDavSyncCredentialsUnavailableException()
    : super('The selected WebDAV credentials are unavailable');
}

final class WebDavSyncLegacyRootException extends WebDavSyncSetupException {
  const WebDavSyncLegacyRootException()
    : super(
        'This folder was set up by an older version of Debrify. Set up sync '
        'again from your main device.',
      );
}

sealed class WebDavSyncFolderInspection {
  const WebDavSyncFolderInspection({
    required this.location,
    required this.config,
  });

  final WebDavSyncFolderLocation location;
  final WebDavConfig config;
}

final class WebDavSyncFolderMissing extends WebDavSyncFolderInspection {
  const WebDavSyncFolderMissing({
    required super.location,
    required super.config,
    this.rootKey,
  });

  /// An orphan create-only claim. Activation adopts it before minting a root.
  final WebDavSyncRootKeyFile? rootKey;
}

final class WebDavSyncFolderExisting extends WebDavSyncFolderInspection {
  const WebDavSyncFolderExisting({
    required super.location,
    required super.config,
    required this.markerBytes,
    required this.metadata,
    required this.rootKey,
  });

  final Uint8List markerBytes;
  final WebDavResponseMetadata metadata;
  final WebDavSyncRootKeyFile rootKey;
}

abstract interface class WebDavSyncProbeTransport {
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  });

  Future<WebDavBytesResult> readRootKey({
    required String path,
    Future<void> Function()? beforeSend,
  });

  void close();
}

typedef WebDavSyncProbeTransportFactory =
    WebDavSyncProbeTransport Function({
      required Uri endpoint,
      required WebDavCredentials credentials,
    });

final class ProtocolWebDavSyncProbeTransport
    implements WebDavSyncProbeTransport {
  ProtocolWebDavSyncProbeTransport({
    required Uri endpoint,
    required WebDavCredentials credentials,
  }) : _client = WebDavProtocolClient(
         endpoint: endpoint,
         credentials: credentials,
       );

  final WebDavProtocolClient _client;

  @override
  Future<WebDavBytesResult> readRootMarker({
    required String path,
    Future<void> Function()? beforeSend,
  }) => _client.getBytes(
    path: path,
    maxBytes: WebDavSyncCodec.rootMarkerMaxBytes,
    beforeSend: beforeSend,
  );

  @override
  Future<WebDavBytesResult> readRootKey({
    required String path,
    Future<void> Function()? beforeSend,
  }) => _client.getBytes(
    path: path,
    maxBytes: WebDavSyncRootKeyFile.maxBytes,
    beforeSend: beforeSend,
  );

  @override
  void close() => _client.close();
}

/// Read-only M3 setup boundary.
///
/// This service can GET the immutable marker and persist local binding state;
/// it deliberately exposes no MKCOL, PUT, MOVE, or DELETE operation. M5 owns
/// all server mutation after complete seed material exists.
final class WebDavSyncSetupService {
  WebDavSyncSetupService({
    WebDavSyncBindingStore? store,
    WebDavSyncCodec? codec,
    WebDavSyncProbeTransportFactory? transportFactory,
    this.runCryptoInBackground = true,
  }) : store = store ?? WebDavSyncBindingStore(),
       codec = codec ?? WebDavSyncCodec(),
       _transportFactory =
           transportFactory ??
           (({required endpoint, required credentials}) =>
               ProtocolWebDavSyncProbeTransport(
                 endpoint: endpoint,
                 credentials: credentials,
               ));

  final WebDavSyncBindingStore store;
  final WebDavSyncCodec codec;
  final bool runCryptoInBackground;
  final WebDavSyncProbeTransportFactory _transportFactory;

  Future<WebDavSyncFolderInspection> inspectFolder({
    required WebDavConfig config,
    required String folderPath,
    Future<void> Function()? beforeSend,
  }) async {
    _validateConfig(config);
    final location = WebDavSyncFolderLocation.fromConfig(config, folderPath);
    final snapshot = await store.load();
    final priorBinding = snapshot.bindings[location.fingerprint];
    final priorMarker = priorBinding == null
        ? null
        : snapshot.namespaceFor(priorBinding)?.markerBytes;
    final transport = _transportFactory(
      endpoint: location.endpoint,
      credentials: WebDavCredentials(
        username: config.username,
        password: config.password,
      ),
    );
    try {
      final marker = await _readIfPresent(
        () => transport.readRootMarker(
          path: location.rootMarkerPath,
          beforeSend: beforeSend,
        ),
      );
      final keyResult = await _readIfPresent(
        () => transport.readRootKey(
          path: location.rootKeyPath,
          beforeSend: beforeSend,
        ),
      );
      if (marker == null) {
        if (priorMarker != null) {
          await store.markError(
            priorBinding!.id,
            const WebDavSyncRootMissingException(),
          );
          throw const WebDavSyncRootMissingException();
        }
        final rootKey = keyResult == null
            ? null
            : WebDavSyncRootKeyFile.parse(keyResult.bytes);
        return WebDavSyncFolderMissing(
          location: location,
          config: config,
          rootKey: rootKey,
        );
      }
      if (priorMarker != null && !_bytesEqual(priorMarker, marker.bytes)) {
        await store.markError(
          priorBinding!.id,
          const WebDavSyncRootChangedException(),
        );
        throw const WebDavSyncRootChangedException();
      }
      if (keyResult == null) throw const WebDavSyncLegacyRootException();
      final rootKey = WebDavSyncRootKeyFile.parse(keyResult.bytes);
      return WebDavSyncFolderExisting(
        location: location,
        config: config,
        markerBytes: Uint8List.fromList(marker.bytes),
        metadata: marker.metadata,
        rootKey: rootKey,
      );
    } finally {
      transport.close();
    }
  }

  Future<WebDavSyncBinding> configureNewRoot({
    required WebDavSyncFolderMissing inspection,
    required String syncPassphrase,
    bool completeOnboarding = false,
    Future<void> Function()? beforeCommit,
  }) async {
    WebDavSyncCodec.validatePassphrase(syncPassphrase);
    final binding = await store.stageBinding(
      location: inspection.location,
      config: inspection.config,
      syncPassphrase: syncPassphrase,
      completeOnboarding: completeOnboarding,
      beforeSave: beforeCommit,
    );
    return store.markAwaitingSeedCommit(binding.id, beforeSave: beforeCommit);
  }

  Future<WebDavSyncBinding> configureExistingRoot({
    required WebDavSyncFolderExisting inspection,
    bool reconnectActive = false,
    bool completeOnboarding = false,
    Future<void> Function()? beforeCommit,
  }) async {
    // Authenticate the remote bytes before persisting a passphrase or marker
    // pin. A typo leaves the prior binding untouched and retryable.
    final opened = await codec.openRoot(
      inspection.markerBytes,
      inspection.rootKey.syncPassphrase,
      runInBackground: runCryptoInBackground,
    );
    final snapshot = await store.load();
    final resumesCommittedCandidate = _matchesCommittedCandidate(
      snapshot,
      inspection.location.fingerprint,
      inspection.markerBytes,
    );
    final prior = snapshot.bindings[inspection.location.fingerprint];
    final sameAsActive =
        snapshot.activeBindingId == inspection.location.fingerprint;
    final reconnectPinnedActive =
        sameAsActive &&
        (reconnectActive ||
            prior?.lifecycle == WebDavSyncLifecycle.rootVerified ||
            prior?.lifecycle == WebDavSyncLifecycle.awaitingAdoption);
    final preserveActive = sameAsActive && !reconnectPinnedActive;
    if (sameAsActive && opened.document.circleId != prior?.circleId) {
      throw const WebDavSyncRootChangedException();
    }
    final binding = await store.stageBinding(
      location: inspection.location,
      config: inspection.config,
      syncPassphrase: inspection.rootKey.syncPassphrase,
      preserveActive: preserveActive,
      reconnectActive: reconnectPinnedActive,
      completeOnboarding: completeOnboarding,
      beforeSave: beforeCommit,
    );
    if (preserveActive) return binding;
    if (resumesCommittedCandidate) {
      // Root-last initialization may have committed the marker immediately
      // before the process stopped. Keep the persisted candidate lifecycle so
      // M5 can verify its already-uploaded seed and finish without treating
      // this device's own graph as a destructive first connection.
      return store.markAwaitingSeedCommit(binding.id, beforeSave: beforeCommit);
    }
    return store.markRootVerified(
      bindingId: binding.id,
      root: opened.document,
      markerBytes: inspection.markerBytes,
      beforeSave: beforeCommit,
    );
  }

  Future<WebDavSyncBinding> revalidate(
    String bindingId, {
    Future<void> Function()? beforeSend,
  }) async {
    final snapshot = await store.load();
    final binding =
        snapshot.bindings[bindingId] ??
        (throw StateError('WebDAV sync binding is unavailable'));
    final namespace =
        snapshot.namespaceFor(binding) ??
        (throw StateError('WebDAV sync namespace is unavailable'));
    final markerPin = namespace.markerBytes;
    if (markerPin == null || binding.circleId == null) {
      throw StateError('WebDAV sync root has not been verified');
    }
    try {
      final secrets = await store.readSecrets(binding);
      final transport = _transportFactory(
        endpoint: binding.location.endpoint,
        credentials: WebDavCredentials(
          username: secrets.username,
          password: secrets.password,
        ),
      );
      try {
        final result = await transport.readRootMarker(
          path: binding.location.rootMarkerPath,
          beforeSend: beforeSend,
        );
        if (!_bytesEqual(markerPin, result.bytes)) {
          throw const WebDavSyncRootChangedException();
        }
        final opened = await codec.openRoot(
          result.bytes,
          secrets.syncPassphrase,
          runInBackground: runCryptoInBackground,
        );
        if (opened.document.circleId != binding.circleId) {
          throw const WebDavSyncRootChangedException();
        }
        return store.markRootVerified(
          bindingId: binding.id,
          root: opened.document,
          markerBytes: result.bytes,
        );
      } finally {
        transport.close();
      }
    } on WebDavException catch (error) {
      final mapped = error.kind == WebDavErrorKind.notFound
          ? const WebDavSyncRootMissingException()
          : error;
      await store.markError(binding.id, mapped);
      throw mapped;
    } catch (error) {
      await store.markError(binding.id, error);
      rethrow;
    }
  }

  static void _validateConfig(WebDavConfig config) {
    if (!config.isComplete || config.credentialsRedacted) {
      throw const WebDavSyncCredentialsUnavailableException();
    }
  }

  static bool _matchesCommittedCandidate(
    WebDavSyncStoreSnapshot snapshot,
    String bindingId,
    List<int> remoteMarker,
  ) {
    final binding = snapshot.bindings[bindingId];
    if (binding == null ||
        binding.lifecycle != WebDavSyncLifecycle.awaitingSeedCommit ||
        binding.circleId != null) {
      return false;
    }
    final namespace = snapshot.namespaceFor(binding);
    final encoded =
        namespace?.values[WebDavSyncBindingStore.seedCandidateMarkerValueKey];
    if (namespace == null ||
        namespace.markerBytes != null ||
        encoded is! String) {
      return false;
    }
    try {
      final candidate = base64Decode(encoded);
      return candidate.isNotEmpty &&
          candidate.length <= WebDavSyncCodec.rootMarkerMaxBytes &&
          _bytesEqual(candidate, remoteMarker);
    } on FormatException {
      throw const FormatException('Invalid WebDAV sync seed candidate');
    }
  }

  static bool _bytesEqual(List<int> left, List<int> right) {
    var difference = left.length ^ right.length;
    final length = left.length > right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      difference |=
          (index < left.length ? left[index] : 0) ^
          (index < right.length ? right[index] : 0);
    }
    return difference == 0;
  }

  static Future<WebDavBytesResult?> _readIfPresent(
    Future<WebDavBytesResult> Function() read,
  ) async {
    try {
      return await read();
    } on WebDavException catch (error) {
      if (error.kind == WebDavErrorKind.notFound) return null;
      rethrow;
    }
  }
}
