import 'dart:convert';
import 'dart:typed_data';

import '../../models/webdav_item.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_binding_store.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_diagnostics.dart';
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
  });
}

final class WebDavSyncFolderExisting extends WebDavSyncFolderInspection {
  const WebDavSyncFolderExisting({
    required super.location,
    required super.config,
    required this.markerBytes,
    required this.metadata,
    required this.syncPassphrase,
    this.authorityBytes,
  });

  /// The unchanged inner AEAD marker bytes.
  final Uint8List markerBytes;

  /// Exact bytes pinned for the merged layout; null only for a legacy result.
  final Uint8List? authorityBytes;
  final WebDavResponseMetadata metadata;
  final String syncPassphrase;

  List<int> get pinBytes => authorityBytes ?? markerBytes;
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

/// Merged-layout capability. Legacy test/embedding transports that do not yet
/// expose it continue to exercise only the compatibility read path.
abstract interface class WebDavSyncAuthorityProbeTransport {
  Future<WebDavBytesResult> readRootAuthority({
    required String path,
    Future<void> Function()? beforeSend,
  });
}

abstract interface class WebDavSyncAuthorityProvisionTransport {
  Future<WebDavResponseMetadata> writeRootAuthority({
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
    implements
        WebDavSyncProbeTransport,
        WebDavSyncAuthorityProbeTransport,
        WebDavSyncAuthorityProvisionTransport {
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
    maxBytes: path.endsWith('/circle.authority') || path == 'circle.authority'
        ? WebDavSyncAuthorityFile.maxBytes
        : WebDavSyncCodec.rootMarkerMaxBytes,
    beforeSend: beforeSend,
  );

  @override
  Future<WebDavBytesResult> readRootAuthority({
    required String path,
    Future<void> Function()? beforeSend,
  }) => _client.getBytes(
    path: path,
    maxBytes: WebDavSyncAuthorityFile.maxBytes,
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
  Future<WebDavResponseMetadata> writeRootAuthority({
    required String path,
    required Uint8List bytes,
    Future<void> Function()? beforeSend,
  }) => _client.putBytes(
    path: path,
    bytes: bytes,
    maxBytes: WebDavSyncAuthorityFile.maxBytes,
    ifNoneMatch: '*',
    createParents: false,
    beforeSend: beforeSend,
  );

  @override
  void close() => _client.close();
}

/// Setup probes inspect the merged authority first. An authenticated legacy
/// open may provision the one merged authority object and verify its read-back.
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
      final authorityTransport = transport is WebDavSyncAuthorityProbeTransport
          ? transport as WebDavSyncAuthorityProbeTransport
          : null;
      final authorityResult = authorityTransport == null
          ? null
          : await _readIfPresent(
              () => authorityTransport.readRootAuthority(
                path: location.rootAuthorityPath,
                beforeSend: beforeSend,
              ),
            );
      if (authorityResult != null) {
        final opened = await codec.openAuthority(
          authorityResult.bytes,
          runInBackground: runCryptoInBackground,
        );
        if (context == WebDavSyncFolderInspectionContext.repair) {
          final matchesPinnedAuthority = snapshot
              .namespaceFor(priorBinding!)!
              .matchesAuthority(authorityResult.bytes);
          final upgradesPinnedLegacyMarker =
              snapshot
                  .namespaceFor(priorBinding)!
                  .matchesAuthority(priorMarker!) &&
              _bytesEqual(priorMarker, opened.authority.markerBytes);
          final resumesDetectedAuthorityReplacement =
              priorBinding.lifecycle == WebDavSyncLifecycle.error &&
              priorBinding.errorMessage ==
                  const WebDavSyncRootChangedException().message;
          if ((!matchesPinnedAuthority &&
                  !upgradesPinnedLegacyMarker &&
                  !resumesDetectedAuthorityReplacement) ||
              opened.root.document.circleId != priorBinding.circleId &&
                  !resumesDetectedAuthorityReplacement) {
            await store.markError(
              priorBinding.id,
              const WebDavSyncRootChangedException(),
            );
            throw const WebDavSyncRootChangedException();
          }
        }
        return WebDavSyncFolderExisting(
          location: location,
          config: config,
          markerBytes: Uint8List.fromList(opened.authority.markerBytes),
          authorityBytes: Uint8List.fromList(authorityResult.bytes),
          metadata: authorityResult.metadata,
          syncPassphrase: opened.authority.syncPassphrase,
        );
      }

      // Compatibility reads are reached only when the merged authority is
      // definitively absent. Malformed authority never falls through here.
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
        return WebDavSyncFolderMissing(location: location, config: config);
      }
      if (context == WebDavSyncFolderInspectionContext.repair &&
          !snapshot
              .namespaceFor(priorBinding!)!
              .matchesAuthority(marker.bytes)) {
        await store.markError(
          priorBinding.id,
          const WebDavSyncRootChangedException(),
        );
        throw const WebDavSyncRootChangedException();
      }
      if (keyResult == null &&
          context == WebDavSyncFolderInspectionContext.setup) {
        throw const WebDavSyncLegacyRootException();
      }
      final rootKey = keyResult == null
          ? WebDavSyncRootKeyFile(
              syncPassphrase: (await store.readSecrets(
                priorBinding!,
              )).syncPassphrase,
            )
          : WebDavSyncRootKeyFile.parse(keyResult.bytes);
      try {
        final legacyRoot = await codec.openRoot(
          marker.bytes,
          rootKey.syncPassphrase,
          runInBackground: runCryptoInBackground,
        );
        if (context == WebDavSyncFolderInspectionContext.repair &&
            legacyRoot.document.circleId != priorBinding!.circleId) {
          throw const WebDavSyncRootChangedException();
        }
        if (transport is! WebDavSyncAuthorityProvisionTransport) {
          return WebDavSyncFolderExisting(
            location: location,
            config: config,
            markerBytes: Uint8List.fromList(marker.bytes),
            metadata: marker.metadata,
            syncPassphrase: rootKey.syncPassphrase,
          );
        }
        final provisioned = await _provisionLegacyAuthority(
          transport: transport,
          location: location,
          markerBytes: marker.bytes,
          syncPassphrase: rootKey.syncPassphrase,
          beforeSend: beforeSend,
        );
        // A concurrent merged authority may have won the write/read-back
        // race. Return that complete winner so reconnect can use the normal
        // authenticated adoption ladder rather than preserving the legacy
        // marker merely because it was read first.
        return WebDavSyncFolderExisting(
          location: location,
          config: config,
          markerBytes: provisioned.authority.markerBytes,
          authorityBytes: provisioned.bytes,
          metadata: provisioned.metadata,
          syncPassphrase: provisioned.authority.syncPassphrase,
        );
      } catch (error) {
        if (context == WebDavSyncFolderInspectionContext.repair) {
          final failure =
              error is WebDavSyncRootChangedException ||
                  error is WebDavSyncAuthorityFileException ||
                  error is WebDavSyncSetupInconclusiveException
              ? error
              : const WebDavSyncAuthorityClaimException();
          try {
            await store.markError(priorBinding!.id, failure);
          } catch (_) {
            // Preserve the actionable authority failure if status persistence
            // is independently unavailable.
          }
          throw failure;
        }
        rethrow;
      }
    } finally {
      transport.close();
    }
  }

  Future<
    ({
      Uint8List bytes,
      WebDavResponseMetadata metadata,
      WebDavSyncAuthorityFile authority,
      OpenedWebDavSyncRoot root,
    })
  >
  _provisionLegacyAuthority({
    required WebDavSyncProbeTransport transport,
    required WebDavSyncFolderLocation location,
    required List<int> markerBytes,
    required String syncPassphrase,
    Future<void> Function()? beforeSend,
  }) async {
    final provision = transport;
    if (provision is! WebDavSyncAuthorityProvisionTransport ||
        transport is! WebDavSyncAuthorityProbeTransport) {
      _throwProvisionFailure();
    }
    final existing = await _readIfPresent(
      () => (transport as WebDavSyncAuthorityProbeTransport).readRootAuthority(
        path: location.rootAuthorityPath,
        beforeSend: beforeSend,
      ),
    );
    if (existing != null) {
      final opened = await codec.openAuthority(
        existing.bytes,
        runInBackground: runCryptoInBackground,
      );
      return (
        bytes: Uint8List.fromList(existing.bytes),
        metadata: existing.metadata,
        authority: opened.authority,
        root: opened.root,
      );
    }
    final expected = WebDavSyncAuthorityFile(
      markerBytes: Uint8List.fromList(markerBytes),
      syncPassphrase: syncPassphrase,
    ).encode();
    Object? writeError;
    try {
      await (provision as WebDavSyncAuthorityProvisionTransport)
          .writeRootAuthority(
            path: location.rootAuthorityPath,
            bytes: expected,
            beforeSend: beforeSend,
          );
    } on Object catch (error) {
      // A lost/failed response can still leave either our object or a valid
      // concurrent winner. The standing object, never the response, decides.
      writeError = error;
    }

    late final WebDavBytesResult standing;
    try {
      standing = await (transport as WebDavSyncAuthorityProbeTransport)
          .readRootAuthority(
            path: location.rootAuthorityPath,
            beforeSend: beforeSend,
          );
    } on WebDavException catch (error) {
      _throwProvisionFailure(error: writeError ?? error);
    }
    try {
      final opened = await codec.openAuthority(
        standing.bytes,
        runInBackground: runCryptoInBackground,
      );
      return (
        bytes: Uint8List.fromList(standing.bytes),
        metadata: standing.metadata,
        authority: opened.authority,
        root: opened.root,
      );
    } on WebDavSyncAuthorityFileException {
      rethrow;
    } on Object catch (error) {
      _throwProvisionFailure(
        error: error,
        statusCode: standing.metadata.statusCode,
      );
    }
  }

  Never _throwProvisionFailure({Object? error, int? statusCode}) {
    recordWebDavSyncAuthorityFailure(
      _diagnostic,
      step: 'provision',
      error: error,
      statusCode: statusCode,
    );
    throw const WebDavSyncAuthorityClaimException();
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
      inspection.syncPassphrase,
      runInBackground: runCryptoInBackground,
    );
    final snapshot = await store.load();
    if (WebDavSyncBindingStore.logoutPending(snapshot)) {
      return store.repairLogoutCredentials(
        bindingId: inspection.location.fingerprint,
        config: inspection.config,
        syncPassphrase: inspection.syncPassphrase,
        authorityBytes: inspection.pinBytes,
        beforeSave: beforeCommit,
      );
    }
    final resumesCommittedCandidate = _matchesCommittedCandidate(
      snapshot,
      inspection.location.fingerprint,
      inspection.pinBytes,
      inspection.syncPassphrase,
    );
    final prior = snapshot.bindings[inspection.location.fingerprint];
    final sameAsActive =
        snapshot.activeBindingId == inspection.location.fingerprint;
    final priorPin = prior == null
        ? null
        : snapshot.namespaceFor(prior)?.markerBytes;
    final upgradesPinnedLegacyMarker =
        sameAsActive &&
        inspection.authorityBytes != null &&
        priorPin != null &&
        snapshot.namespaceFor(prior!)!.matchesAuthority(priorPin) &&
        _bytesEqual(priorPin, inspection.markerBytes);
    final reconnectPinnedActive =
        sameAsActive &&
        (reconnectActive ||
            upgradesPinnedLegacyMarker ||
            prior?.lifecycle == WebDavSyncLifecycle.rootVerified ||
            prior?.lifecycle == WebDavSyncLifecycle.awaitingAdoption);
    final preserveActive = sameAsActive && !reconnectPinnedActive;
    if (sameAsActive &&
        opened.document.circleId != prior?.circleId &&
        !(reconnectActive && inspection.authorityBytes != null)) {
      throw const WebDavSyncRootChangedException();
    }
    if (upgradesPinnedLegacyMarker) {
      return store.upgradeLegacyActiveAuthority(
        bindingId: prior.id,
        config: inspection.config,
        syncPassphrase: inspection.syncPassphrase,
        root: opened.document,
        legacyMarkerBytes: inspection.markerBytes,
        authorityBytes: inspection.authorityBytes!,
        beforeSave: beforeCommit,
      );
    }
    if (preserveActive) {
      if (priorPin == null ||
          !snapshot
              .namespaceFor(prior!)!
              .matchesAuthority(inspection.pinBytes)) {
        // Never reseal replacement credentials beneath an old marker pin.
        // A legitimate marker change must use reconnect verification, which
        // republishes the pin and secrets together.
        throw const WebDavSyncRootChangedException();
      }
    }
    final binding = await store.stageBinding(
      location: inspection.location,
      config: inspection.config,
      syncPassphrase: inspection.syncPassphrase,
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
      markerBytes: inspection.pinBytes,
      allowPinReplacement: reconnectPinnedActive,
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
        final result = transport is WebDavSyncAuthorityProbeTransport
            ? await (transport as WebDavSyncAuthorityProbeTransport)
                  .readRootAuthority(
                    path: binding.location.rootAuthorityPath,
                    beforeSend: beforeSend,
                  )
            : await transport.readRootMarker(
                path: binding.location.rootMarkerPath,
                beforeSend: beforeSend,
              );
        if (!namespace.matchesAuthority(result.bytes)) {
          throw const WebDavSyncRootChangedException();
        }
        final opened = await codec.openPinnedAuthority(
          markerPin,
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
    String syncPassphrase,
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
      if (candidate.isEmpty ||
          candidate.length > WebDavSyncCodec.rootMarkerMaxBytes) {
        return false;
      }
      final authority = WebDavSyncAuthorityFile(
        markerBytes: Uint8List.fromList(candidate),
        syncPassphrase: syncPassphrase,
      ).encode();
      // The raw comparison is only for an interrupted pre-upgrade legacy
      // candidate. New candidates compare the complete authority in memory.
      return _bytesEqual(authority, remoteMarker) ||
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
