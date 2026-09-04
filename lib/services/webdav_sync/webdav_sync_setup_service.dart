import 'dart:convert';
import 'dart:typed_data';

import '../../models/webdav_item.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_diagnostics.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_transport.dart';

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

enum WebDavSyncFolderInspectionContext { setup, repair }

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

abstract interface class WebDavSyncRootKeyProvisionTransport
    implements WebDavSyncConditionalCreateProbeTransport {
  Future<WebDavResponseMetadata> createRootKey({
    required String path,
    required Uint8List bytes,
    Future<void> Function()? beforeSend,
  });
}

typedef WebDavSyncProbeTransportFactory =
    WebDavSyncProbeTransport Function({
      required Uri endpoint,
      required WebDavCredentials credentials,
    });

final class ProtocolWebDavSyncProbeTransport
    implements WebDavSyncProbeTransport, WebDavSyncRootKeyProvisionTransport {
  ProtocolWebDavSyncProbeTransport({
    required Uri endpoint,
    required WebDavCredentials credentials,
    WebDavSyncAuthorityDiagnostic? diagnostic,
  }) : _client = WebDavProtocolClient(
         endpoint: endpoint,
         credentials: credentials,
       ),
       _diagnostic = diagnostic ?? recordWebDavSyncDiagnostic;

  final WebDavProtocolClient _client;
  final WebDavSyncAuthorityDiagnostic _diagnostic;

  @override
  Future<void> verifyConditionalCreate({
    required String syncRootPath,
    Future<void> Function()? beforeSend,
  }) => WebDavSyncConditionalCreateProbe(
    _client,
    diagnostic: _diagnostic,
  ).verify(syncRootPath: syncRootPath, beforeSend: beforeSend);

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
  Future<WebDavResponseMetadata> createRootKey({
    required String path,
    required Uint8List bytes,
    Future<void> Function()? beforeSend,
  }) async {
    return _client.putBytes(
      path: path,
      bytes: bytes,
      maxBytes: WebDavSyncRootKeyFile.maxBytes,
      ifNoneMatch: '*',
      createParents: false,
      beforeSend: beforeSend,
    );
  }

  @override
  void close() => _client.close();
}

/// Setup probes are read-only. Repair probes may make the one authenticated,
/// create-only keyfile write needed to upgrade a pinned legacy circle.
final class WebDavSyncSetupService {
  WebDavSyncSetupService({
    WebDavSyncBindingStore? store,
    WebDavSyncCodec? codec,
    WebDavSyncProbeTransportFactory? transportFactory,
    WebDavSyncAuthorityDiagnostic? diagnostic,
    this.runCryptoInBackground = true,
  }) : store = store ?? WebDavSyncBindingStore(),
       codec = codec ?? WebDavSyncCodec(),
       _diagnostic = diagnostic ?? recordWebDavSyncDiagnostic,
       _transportFactory =
           transportFactory ??
           (({required endpoint, required credentials}) =>
               ProtocolWebDavSyncProbeTransport(
                 endpoint: endpoint,
                 credentials: credentials,
                 diagnostic: diagnostic ?? recordWebDavSyncDiagnostic,
               ));

  final WebDavSyncBindingStore store;
  final WebDavSyncCodec codec;
  final bool runCryptoInBackground;
  final WebDavSyncProbeTransportFactory _transportFactory;
  final WebDavSyncAuthorityDiagnostic _diagnostic;

  Future<WebDavSyncFolderInspection> inspectFolder({
    required WebDavConfig config,
    required String folderPath,
    required WebDavSyncFolderInspectionContext context,
    String? repairBindingId,
    Future<void> Function()? beforeSend,
  }) async {
    _validateConfig(config);
    var location = WebDavSyncFolderLocation.fromConfig(config, folderPath);
    final snapshot = await store.load();
    WebDavSyncBinding? priorBinding;
    Uint8List? priorMarker;
    if (context == WebDavSyncFolderInspectionContext.repair) {
      if (repairBindingId == null) {
        throw ArgumentError('A WebDAV sync repair binding is required');
      }
      priorBinding = snapshot.bindings[repairBindingId];
      if (priorBinding == null || location.fingerprint != priorBinding.id) {
        throw StateError('WebDAV sync repair location does not match');
      }
      location = priorBinding.location;
      priorMarker = snapshot.namespaceFor(priorBinding)?.markerBytes;
      if (priorMarker == null || priorBinding.circleId == null) {
        throw StateError('WebDAV sync repair root is not pinned');
      }
    }
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
        if (context == WebDavSyncFolderInspectionContext.repair) {
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
      if (context == WebDavSyncFolderInspectionContext.repair &&
          !_bytesEqual(priorMarker!, marker.bytes)) {
        await store.markError(
          priorBinding!.id,
          const WebDavSyncRootChangedException(),
        );
        throw const WebDavSyncRootChangedException();
      }
      late final WebDavSyncRootKeyFile rootKey;
      if (keyResult == null) {
        if (context == WebDavSyncFolderInspectionContext.setup) {
          throw const WebDavSyncLegacyRootException();
        }
        final secrets = await store.readSecrets(priorBinding!);
        rootKey = WebDavSyncRootKeyFile(syncPassphrase: secrets.syncPassphrase);
        try {
          final opened = await codec.openRoot(
            marker.bytes,
            rootKey.syncPassphrase,
            runInBackground: runCryptoInBackground,
          );
          if (opened.document.circleId != priorBinding.circleId) {
            throw const WebDavSyncRootChangedException();
          }
          await _provisionLegacyRootKey(
            transport: transport,
            syncRootPath: location.folderPath.isEmpty
                ? 'debrify-sync'
                : '${location.folderPath}/debrify-sync',
            path: location.rootKeyPath,
            rootKey: rootKey,
            beforeSend: beforeSend,
          );
        } catch (error) {
          final failure =
              error is WebDavSyncRootChangedException ||
                  error is WebDavSyncProviderUnsupportedException
              ? error
              : const WebDavSyncRootKeyClaimException();
          try {
            await store.markError(priorBinding.id, failure);
          } catch (_) {
            // Keep the non-secret-bearing repair failure actionable even when
            // local status persistence is independently unavailable.
          }
          throw failure;
        }
      } else {
        rootKey = WebDavSyncRootKeyFile.parse(keyResult.bytes);
      }
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

  Future<void> _provisionLegacyRootKey({
    required WebDavSyncProbeTransport transport,
    required String syncRootPath,
    required String path,
    required WebDavSyncRootKeyFile rootKey,
    Future<void> Function()? beforeSend,
  }) async {
    final provision = transport;
    if (provision is! WebDavSyncRootKeyProvisionTransport) {
      _throwProvisionFailure();
    }
    try {
      await (provision as WebDavSyncRootKeyProvisionTransport)
          .verifyConditionalCreate(
            syncRootPath: syncRootPath,
            beforeSend: beforeSend,
          );
    } on WebDavSyncProviderUnsupportedException {
      // The probe records its own more precise step/status diagnostic.
      rethrow;
    } on Object catch (error) {
      _throwProvisionFailure(error: error);
    }
    final expected = rootKey.encode();
    try {
      await (provision as WebDavSyncRootKeyProvisionTransport).createRootKey(
        path: path,
        bytes: expected,
        beforeSend: beforeSend,
      );
    } on WebDavException catch (error) {
      // HTTP 412 is conventional, but honest servers also report 403, 405,
      // or 409 for a refused conditional create. A valid matching winner is
      // the authority regardless of that dialect.
      try {
        final winnerResult = await transport.readRootKey(
          path: path,
          beforeSend: beforeSend,
        );
        final winner = WebDavSyncRootKeyFile.parse(winnerResult.bytes);
        if (winner.syncPassphrase != rootKey.syncPassphrase) {
          _throwProvisionFailure(error: error);
        }
        return;
      } on WebDavSyncRootKeyClaimException {
        rethrow;
      } on WebDavException catch (readError) {
        _throwProvisionFailure(
          error: readError.kind == WebDavErrorKind.notFound ? error : readError,
        );
      } on Object {
        _throwProvisionFailure(error: error);
      }
    } on Object catch (error) {
      _throwProvisionFailure(error: error);
    }

    late final WebDavBytesResult verified;
    try {
      verified = await transport.readRootKey(
        path: path,
        beforeSend: beforeSend,
      );
      if (!_bytesEqual(verified.bytes, expected)) {
        _throwProvisionFailure(statusCode: verified.metadata.statusCode);
      }
      WebDavSyncRootKeyFile.parse(verified.bytes);
    } on WebDavSyncRootKeyClaimException {
      rethrow;
    } on WebDavException catch (error) {
      _throwProvisionFailure(error: error);
    } on Object {
      _throwProvisionFailure(statusCode: verified.metadata.statusCode);
    }
  }

  Never _throwProvisionFailure({Object? error, int? statusCode}) {
    recordWebDavSyncAuthorityFailure(
      _diagnostic,
      step: 'provision',
      error: error,
      statusCode: statusCode,
    );
    throw const WebDavSyncRootKeyClaimException();
  }

  Future<WebDavSyncBinding> configureNewRoot({
    required WebDavSyncFolderMissing inspection,
    required String syncPassphrase,
    bool completeOnboarding = false,
    Future<void> Function()? beforeCommit,
    void Function(WebDavSyncBinding binding)? afterStaged,
  }) async {
    WebDavSyncCodec.validatePassphrase(syncPassphrase);
    final binding = await store.stageBinding(
      location: inspection.location,
      config: inspection.config,
      syncPassphrase: syncPassphrase,
      completeOnboarding: completeOnboarding,
      beforeSave: beforeCommit,
    );
    afterStaged?.call(binding);
    return store.markAwaitingSeedCommit(binding.id, beforeSave: beforeCommit);
  }

  Future<WebDavSyncBinding> configureExistingRoot({
    required WebDavSyncFolderExisting inspection,
    bool reconnectActive = false,
    bool completeOnboarding = false,
    Future<void> Function()? beforeCommit,
    void Function(WebDavSyncBinding binding)? afterStaged,
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
    if (preserveActive) {
      final markerPin = prior == null
          ? null
          : snapshot.namespaceFor(prior)?.markerBytes;
      if (markerPin == null ||
          !_bytesEqual(markerPin, inspection.markerBytes)) {
        // Never reseal replacement credentials beneath an old marker pin.
        // A legitimate marker change must use reconnect verification, which
        // republishes the pin and secrets together.
        throw const WebDavSyncRootChangedException();
      }
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
    afterStaged?.call(binding);
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
