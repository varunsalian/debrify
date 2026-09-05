import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:synchronized/synchronized.dart';

import '../../models/webdav_item.dart';
import '../profiles/device_key_provider.dart';
import '../profiles/profile_preferences.dart';
import 'webdav_sync_models.dart';
import 'webdav_sync_codec.dart';

final class WebDavSyncVaultLockedException implements Exception {
  const WebDavSyncVaultLockedException();

  @override
  String toString() => 'The device vault is locked';
}

final class WebDavSyncSecrets {
  const WebDavSyncSecrets({
    required this.username,
    required this.password,
    required this.syncPassphrase,
  });

  final String username;
  final String password;
  final String syncPassphrase;
}

/// Device-owned persistence for sync binding metadata and sealed credentials.
///
/// The entire state is one atomic SharedPreferences value. Root namespaces
/// remain separate from endpoint bindings, so staging a different folder can
/// neither inherit the old marker pin nor activate against old ID maps.
final class WebDavSyncBindingStore {
  WebDavSyncBindingStore({
    DateTime Function()? clock,
    Uint8List Function(int length)? randomBytes,
    String? debugStorageKey,
  }) : _clock = clock ?? DateTime.now,
       _randomBytes = randomBytes ?? _secureRandomBytes,
       _storageKey = debugStorageKey ?? storageKey;

  static const String storageKey = 'webdav_sync_state_v1';
  static const String seedCandidateMarkerValueKey = 'm5SeedCandidateMarker';
  static const String seedCandidateResetRequiredValueKey =
      'm5SeedCandidateResetRequired';
  static const String engineStateFileValueKey = 'm4Engine';
  static const String registryTombstonesFileValueKey = 'm11RegistryTombstones';
  static const Set<String> deviceIdDerivedNamespaceValueKeys = <String>{
    engineStateFileValueKey,
    registryTombstonesFileValueKey,
  };
  // This value lives in UserDefaults on tvOS. Keep one sync store comfortably
  // below the platform's warning threshold and also run it through the shared
  // database-wide preference budget before every write.
  static const int _stateMaxBytes = 64 * 1024;
  static final Lock _writeLock = Lock();

  final DateTime Function() _clock;
  final Uint8List Function(int length) _randomBytes;
  final String _storageKey;

  Future<WebDavSyncStoreSnapshot> load() async {
    final device = await DevicePreferences.instance();
    final encoded = device.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return const WebDavSyncStoreSnapshot();
    }
    if (utf8.encode(encoded).length > _stateMaxBytes) {
      throw const FormatException('WebDAV sync state exceeds its limit');
    }
    final decoded = jsonDecode(encoded);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('WebDAV sync state must be an object');
    }
    return WebDavSyncStoreSnapshot.fromJson(decoded);
  }

  Future<WebDavSyncBinding> stageBinding({
    required WebDavSyncFolderLocation location,
    required WebDavConfig config,
    required String syncPassphrase,
    bool preserveActive = false,
    bool reconnectActive = false,
    bool completeOnboarding = false,
    Future<void> Function()? beforeSave,
  }) => _writeLock.synchronized(() async {
    _requireVault();
    WebDavSyncCodec.validatePassphrase(syncPassphrase);
    final snapshot = await load();
    final id = location.fingerprint;
    final existing = snapshot.bindings[id];
    final namespaceId = existing?.namespaceId ?? 'candidate:$id';
    final namespaces = Map<String, WebDavSyncNamespace>.from(
      snapshot.namespaces,
    );
    final existingNamespace = namespaces[namespaceId];
    final replacingFailedCandidate =
        existing != null &&
        existing.circleId == null &&
        existingNamespace?.markerBytes == null &&
        (await readSecrets(existing)).syncPassphrase != syncPassphrase;
    if (replacingFailedCandidate) {
      // Candidate marker bytes and the device engine journal are derived from
      // the passphrase. A retry with a different passphrase must begin from a
      // fresh device identity instead of trying to open the abandoned state.
      namespaces[namespaceId] = WebDavSyncNamespace(
        id: namespaceId,
        deviceId: _uuidV4(),
      );
    } else {
      namespaces.putIfAbsent(
        namespaceId,
        () => WebDavSyncNamespace(id: namespaceId, deviceId: _uuidV4()),
      );
    }
    final sameAsActive = snapshot.activeBindingId == id;
    if (preserveActive && reconnectActive) {
      throw ArgumentError('Active binding modes are mutually exclusive');
    }
    if (preserveActive && !sameAsActive) {
      throw StateError('Only the current binding can preserve Active state');
    }
    if (reconnectActive &&
        (!sameAsActive ||
            existing?.circleId == null ||
            namespaces[namespaceId]?.markerBytes == null)) {
      throw StateError('Only a pinned active binding can be reconnected');
    }
    if (sameAsActive && !preserveActive && !reconnectActive) {
      throw StateError('The active binding must be reverified before update');
    }
    final binding = WebDavSyncBinding(
      id: id,
      location: location,
      lifecycle: preserveActive
          ? WebDavSyncLifecycle.active
          : WebDavSyncLifecycle.configured,
      namespaceId: namespaceId,
      sealedSecrets: await _sealSecrets(
        id,
        WebDavSyncSecrets(
          username: config.username,
          password: config.password,
          syncPassphrase: syncPassphrase,
        ),
      ),
      updatedAt: _clock().toUtc(),
      circleId: existing?.circleId,
      completeOnboarding: completeOnboarding,
    );
    final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings)
      ..[id] = binding;
    final previousStagedId = snapshot.stagedBindingId;
    if (!sameAsActive &&
        previousStagedId != null &&
        previousStagedId != id &&
        previousStagedId != snapshot.activeBindingId) {
      final abandoned = bindings.remove(previousStagedId);
      if (abandoned != null &&
          !_namespaceIsReferenced(bindings.values, abandoned.namespaceId)) {
        namespaces.remove(abandoned.namespaceId);
      }
    }
    await beforeSave?.call();
    await _save(
      WebDavSyncStoreSnapshot(
        activeBindingId: snapshot.activeBindingId,
        stagedBindingId: reconnectActive
            ? id
            : (sameAsActive ? snapshot.stagedBindingId : id),
        bindings: bindings,
        namespaces: namespaces,
      ),
    );
    return binding;
  });

  Future<WebDavSyncBinding> markAwaitingSeedCommit(
    String bindingId, {
    Future<void> Function()? beforeSave,
  }) => _updateBinding(bindingId, (snapshot, binding, namespace) {
    if (namespace.markerBytes != null || binding.circleId != null) {
      throw StateError('A pinned sync root can never become a new root');
    }
    return (
      binding: binding.copyWith(
        lifecycle: WebDavSyncLifecycle.awaitingSeedCommit,
        updatedAt: _clock().toUtc(),
        clearError: true,
      ),
      namespace: namespace,
    );
  }, beforeSave: beforeSave);

  Future<WebDavSyncBinding> markRootVerified({
    required String bindingId,
    required WebDavSyncRootDocument root,
    required List<int> markerBytes,
    bool allowPinReplacement = false,
    Future<void> Function()? beforeSave,
  }) => _writeLock.synchronized(() async {
    if (markerBytes.isEmpty ||
        markerBytes.length > WebDavSyncAuthorityFile.maxBytes) {
      throw ArgumentError('Invalid WebDAV sync marker size');
    }
    final snapshot = await load();
    final binding = _requireBinding(snapshot, bindingId);
    final previousNamespace = _requireNamespace(snapshot, binding);
    final namespaceId = 'circle:${root.circleId}';
    final namespaces = Map<String, WebDavSyncNamespace>.from(
      snapshot.namespaces,
    );
    final existing = namespaces[namespaceId];
    final replacesPinnedAuthority =
        allowPinReplacement &&
        existing?.markerBytes != null &&
        !existing!.matchesAuthority(markerBytes);
    if (existing?.markerBytes != null) {
      if (!allowPinReplacement && !existing!.matchesAuthority(markerBytes)) {
        throw StateError('Authenticated sync root conflicts with its pin');
      }
    }
    final replacesVerifiedCircle =
        binding.circleId != null && binding.circleId != root.circleId;
    final namespace =
        (replacesVerifiedCircle || replacesPinnedAuthority
                ? WebDavSyncNamespace(id: namespaceId, deviceId: _uuidV4())
                : existing ?? previousNamespace)
            .copyWith(
              id: namespaceId,
              markerBytes: webDavSyncInnerMarker(markerBytes),
              authorityContentHash: webDavSyncAuthorityHash(markerBytes),
            );
    namespaces[namespaceId] = namespace;
    if (previousNamespace.id != namespaceId &&
        !_namespaceIsReferenced(
          snapshot.bindings.values.where((value) => value.id != bindingId),
          previousNamespace.id,
        )) {
      namespaces.remove(previousNamespace.id);
    }
    final nextLifecycle = binding.lifecycle == WebDavSyncLifecycle.active
        ? WebDavSyncLifecycle.active
        : WebDavSyncLifecycle.rootVerified;
    final updated = binding.copyWith(
      lifecycle: nextLifecycle,
      namespaceId: namespaceId,
      circleId: root.circleId,
      updatedAt: _clock().toUtc(),
      clearError: true,
    );
    final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings)
      ..[bindingId] = updated;
    await beforeSave?.call();
    await _save(
      WebDavSyncStoreSnapshot(
        activeBindingId: snapshot.activeBindingId,
        stagedBindingId: snapshot.stagedBindingId,
        bindings: bindings,
        namespaces: namespaces,
      ),
    );
    return updated;
  });

  /// Atomically upgrades an authenticated legacy marker pin to the merged
  /// authority hash and encrypted inner marker without routing an otherwise
  /// healthy Active circle through first-join adoption.
  Future<WebDavSyncBinding> upgradeLegacyActiveAuthority({
    required String bindingId,
    required WebDavConfig config,
    required String syncPassphrase,
    required WebDavSyncRootDocument root,
    required List<int> legacyMarkerBytes,
    required List<int> authorityBytes,
    Future<void> Function()? beforeSave,
  }) => _writeLock.synchronized(() async {
    _requireVault();
    WebDavSyncCodec.validatePassphrase(syncPassphrase);
    if (authorityBytes.isEmpty ||
        authorityBytes.length > WebDavSyncAuthorityFile.maxBytes) {
      throw ArgumentError('Invalid WebDAV sync authority size');
    }
    final snapshot = await load();
    final binding = _requireBinding(snapshot, bindingId);
    final namespace = _requireNamespace(snapshot, binding);
    if (snapshot.activeBindingId != bindingId ||
        binding.circleId != root.circleId ||
        namespace.markerBytes == null ||
        !namespace.matchesAuthority(legacyMarkerBytes)) {
      throw StateError('Legacy WebDAV sync authority changed during upgrade');
    }
    final updated = binding.copyWith(
      lifecycle: WebDavSyncLifecycle.active,
      sealedSecrets: await _sealSecrets(
        binding.id,
        WebDavSyncSecrets(
          username: config.username,
          password: config.password,
          syncPassphrase: syncPassphrase,
        ),
      ),
      updatedAt: _clock().toUtc(),
      clearError: true,
    );
    final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings)
      ..[bindingId] = updated;
    final namespaces =
        Map<String, WebDavSyncNamespace>.from(snapshot.namespaces)
          ..[namespace.id] = namespace.copyWith(
            markerBytes: Uint8List.fromList(legacyMarkerBytes),
            authorityContentHash: webDavSyncAuthorityHash(authorityBytes),
          );
    await beforeSave?.call();
    await _save(
      WebDavSyncStoreSnapshot(
        activeBindingId: bindingId,
        stagedBindingId: snapshot.stagedBindingId,
        bindings: bindings,
        namespaces: namespaces,
      ),
    );
    return updated;
  });

  Future<WebDavSyncBinding> setLifecycle(
    String bindingId,
    WebDavSyncLifecycle lifecycle, {
    String? errorMessage,
  }) => _updateBinding(bindingId, (snapshot, binding, namespace) {
    final requiresVerifiedRoot =
        lifecycle == WebDavSyncLifecycle.rootVerified ||
        lifecycle == WebDavSyncLifecycle.awaitingAdoption ||
        lifecycle == WebDavSyncLifecycle.active;
    if (requiresVerifiedRoot && binding.circleId == null) {
      throw StateError('An unverified sync root cannot enter this lifecycle');
    }
    if (lifecycle == WebDavSyncLifecycle.awaitingSeedCommit &&
        binding.circleId != null) {
      throw StateError('A verified sync root cannot become a new candidate');
    }
    return (
      binding: binding.copyWith(
        lifecycle: lifecycle,
        updatedAt: _clock().toUtc(),
        errorMessage: errorMessage,
        clearError: errorMessage == null,
      ),
      namespace: namespace,
    );
  });

  Future<WebDavSyncBinding> markError(String bindingId, Object error) =>
      setLifecycle(
        bindingId,
        WebDavSyncLifecycle.error,
        errorMessage: _boundedError(error),
      );

  /// Retains a resumable first-join lifecycle while exposing a terminal
  /// process-local auto-resume failure to settings. A later manual attempt or
  /// process restart may safely enter the existing-root connector again.
  Future<WebDavSyncBinding> markAwaitingAdoptionError(
    String bindingId,
    Object error,
  ) => setLifecycle(
    bindingId,
    WebDavSyncLifecycle.awaitingAdoption,
    errorMessage: _boundedError(error),
  );

  /// Atomically publishes a fully verified staged binding as the active one.
  ///
  /// Keeping the lifecycle transition and pointer promotion in one persisted
  /// snapshot removes the crash state where a binding says `active` while the
  /// device still points at the previous folder (or at no folder at all).
  Future<WebDavSyncBinding> activateAndPromoteStaged(String bindingId) =>
      _writeLock.synchronized(() async {
        final snapshot = await load();
        final binding = _requireBinding(snapshot, bindingId);
        if (snapshot.stagedBindingId != bindingId || binding.circleId == null) {
          throw StateError('Only a verified staged binding can be activated');
        }
        final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings);
        final updated = binding.copyWith(
          lifecycle: WebDavSyncLifecycle.active,
          updatedAt: _clock().toUtc(),
          clearError: true,
        );
        bindings[bindingId] = updated;
        final oldActiveId = snapshot.activeBindingId;
        if (oldActiveId != null && oldActiveId != bindingId) {
          final old = bindings[oldActiveId];
          if (old != null) {
            bindings[oldActiveId] = old.copyWith(
              lifecycle: WebDavSyncLifecycle.rootVerified,
              updatedAt: _clock().toUtc(),
            );
          }
        }
        await _save(
          WebDavSyncStoreSnapshot(
            activeBindingId: bindingId,
            bindings: bindings,
            namespaces: snapshot.namespaces,
          ),
        );
        return updated;
      });

  /// Legacy recovery for snapshots written by builds that split activation
  /// and pointer promotion across two saves.
  Future<void> promoteStaged(String bindingId) =>
      _writeLock.synchronized(() async {
        final snapshot = await load();
        final binding = _requireBinding(snapshot, bindingId);
        if (snapshot.stagedBindingId != bindingId ||
            binding.lifecycle != WebDavSyncLifecycle.active) {
          throw StateError('Only an active staged binding can be promoted');
        }
        final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings);
        bindings[bindingId] = binding;
        final oldActiveId = snapshot.activeBindingId;
        if (oldActiveId != null && oldActiveId != bindingId) {
          final old = bindings[oldActiveId];
          if (old != null) {
            bindings[oldActiveId] = old.copyWith(
              lifecycle: WebDavSyncLifecycle.rootVerified,
              updatedAt: _clock().toUtc(),
            );
          }
        }
        await _save(
          WebDavSyncStoreSnapshot(
            activeBindingId: bindingId,
            bindings: bindings,
            namespaces: snapshot.namespaces,
          ),
        );
      });

  /// Clears first-run intent only after profile-scoped onboarding completion
  /// is durable. A retained intent is deliberately restart-recoverable.
  Future<void> acknowledgeOnboardingIntent(String bindingId) =>
      _writeLock.synchronized(() async {
        final snapshot = await load();
        final binding = _requireBinding(snapshot, bindingId);
        if (snapshot.activeBindingId != bindingId ||
            binding.lifecycle != WebDavSyncLifecycle.active) {
          throw StateError(
            'Only the active WebDAV sync binding can acknowledge onboarding',
          );
        }
        if (!binding.completeOnboarding) return;
        final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings)
          ..[bindingId] = binding.copyWith(completeOnboarding: false);
        await _save(
          WebDavSyncStoreSnapshot(
            activeBindingId: snapshot.activeBindingId,
            stagedBindingId: snapshot.stagedBindingId,
            bindings: bindings,
            namespaces: snapshot.namespaces,
          ),
        );
      });

  Future<void> discardStaged() => _discardStaged();

  Future<void> discardStagedMatching(String bindingId) =>
      _discardStaged(expectedBindingId: bindingId);

  Future<void> _discardStaged({String? expectedBindingId}) =>
      _writeLock.synchronized(() async {
        final snapshot = await load();
        final stagedId = snapshot.stagedBindingId;
        if (stagedId == null ||
            expectedBindingId != null && stagedId != expectedBindingId) {
          return;
        }
        final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings);
        final staged = bindings[stagedId];
        if (stagedId != snapshot.activeBindingId) {
          bindings.remove(stagedId);
        } else if (staged != null && staged.completeOnboarding) {
          bindings[stagedId] = staged.copyWith(completeOnboarding: false);
        }
        final namespaces = Map<String, WebDavSyncNamespace>.from(
          snapshot.namespaces,
        );
        if (staged != null &&
            stagedId != snapshot.activeBindingId &&
            !_namespaceIsReferenced(bindings.values, staged.namespaceId)) {
          namespaces.remove(staged.namespaceId);
        }
        await _save(
          WebDavSyncStoreSnapshot(
            activeBindingId: snapshot.activeBindingId,
            bindings: bindings,
            namespaces: namespaces,
          ),
        );
      });

  Future<WebDavSyncSecrets> readSecrets(WebDavSyncBinding binding) async {
    _requireVault();
    final clear = await DeviceKeyProvider.cipher.open(
      binding.sealedSecrets,
      associatedData: _secretsAad(binding.id),
    );
    if (clear.length > 16 * 1024) {
      throw const FormatException('WebDAV sync credentials exceed their limit');
    }
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic> ||
        decoded['version'] != 1 ||
        decoded['username'] is! String ||
        decoded['password'] is! String ||
        decoded['syncPassphrase'] is! String) {
      throw const FormatException('Invalid sealed WebDAV sync credentials');
    }
    return WebDavSyncSecrets(
      username: decoded['username'] as String,
      password: decoded['password'] as String,
      syncPassphrase: decoded['syncPassphrase'] as String,
    );
  }

  /// Atomically adopts the standing authority object's secret without changing
  /// WebDAV login or the binding lifecycle.
  ///
  /// Candidate marker bytes and the candidate device identity are derived
  /// from the losing secret. They are invalidated in the same snapshot as the
  /// reseal. The reset journal lets activation clear the separate engine-state
  /// store before rebuilding, including after a crash between those writes.
  Future<WebDavSyncBinding> adoptSyncSecret(
    String bindingId,
    String syncPassphrase, {
    bool resetCandidate = false,
  }) => _writeLock.synchronized(() async {
    _requireVault();
    WebDavSyncCodec.validatePassphrase(syncPassphrase);
    final snapshot = await load();
    final binding = _requireBinding(snapshot, bindingId);
    final secrets = await readSecrets(binding);
    if (secrets.syncPassphrase == syncPassphrase && !resetCandidate) {
      return binding;
    }

    final namespace = _requireNamespace(snapshot, binding);
    var updatedNamespace = namespace;
    if (binding.circleId == null &&
        (resetCandidate || secrets.syncPassphrase != syncPassphrase)) {
      final pendingReset = namespace.values[seedCandidateResetRequiredValueKey];
      final previousDeviceId = pendingReset is String && pendingReset.isNotEmpty
          ? pendingReset
          : namespace.deviceId;
      final values = Map<String, Object?>.from(namespace.values)
        ..remove(seedCandidateMarkerValueKey);
      for (final key in deviceIdDerivedNamespaceValueKeys) {
        values.remove(key);
      }
      values[seedCandidateResetRequiredValueKey] = previousDeviceId;
      updatedNamespace = WebDavSyncNamespace(
        id: namespace.id,
        deviceId: _uuidV4(),
        values: Map<String, Object?>.unmodifiable(values),
      );
    }
    final updated = binding.copyWith(
      sealedSecrets: await _sealSecrets(
        binding.id,
        WebDavSyncSecrets(
          username: secrets.username,
          password: secrets.password,
          syncPassphrase: syncPassphrase,
        ),
      ),
      updatedAt: _clock().toUtc(),
    );
    final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings)
      ..[binding.id] = updated;
    final namespaces = Map<String, WebDavSyncNamespace>.from(
      snapshot.namespaces,
    )..[namespace.id] = updatedNamespace;
    await _save(
      WebDavSyncStoreSnapshot(
        activeBindingId: snapshot.activeBindingId,
        stagedBindingId: snapshot.stagedBindingId,
        bindings: bindings,
        namespaces: namespaces,
      ),
    );
    return updated;
  });

  Future<WebDavSyncNamespace> updateNamespaceValues(
    String namespaceId,
    Map<String, Object?> Function(Map<String, Object?> current) update,
  ) => _writeLock.synchronized(() async {
    final snapshot = await load();
    final namespace =
        snapshot.namespaces[namespaceId] ??
        (throw StateError('WebDAV sync namespace is unavailable'));
    final nextValues = Map<String, Object?>.unmodifiable(
      update(Map<String, Object?>.from(namespace.values)),
    );
    final updated = namespace.copyWith(values: nextValues);
    final namespaces = Map<String, WebDavSyncNamespace>.from(
      snapshot.namespaces,
    )..[namespaceId] = updated;
    await _save(
      WebDavSyncStoreSnapshot(
        activeBindingId: snapshot.activeBindingId,
        stagedBindingId: snapshot.stagedBindingId,
        bindings: snapshot.bindings,
        namespaces: namespaces,
      ),
    );
    return updated;
  });

  Future<WebDavSyncBinding> _updateBinding(
    String bindingId,
    ({WebDavSyncBinding binding, WebDavSyncNamespace namespace}) Function(
      WebDavSyncStoreSnapshot snapshot,
      WebDavSyncBinding binding,
      WebDavSyncNamespace namespace,
    )
    update, {
    Future<void> Function()? beforeSave,
  }) => _writeLock.synchronized(() async {
    final snapshot = await load();
    final binding = _requireBinding(snapshot, bindingId);
    final namespace = _requireNamespace(snapshot, binding);
    final result = update(snapshot, binding, namespace);
    final bindings = Map<String, WebDavSyncBinding>.from(snapshot.bindings)
      ..[bindingId] = result.binding;
    final namespaces = Map<String, WebDavSyncNamespace>.from(
      snapshot.namespaces,
    )..[result.namespace.id] = result.namespace;
    await beforeSave?.call();
    await _save(
      WebDavSyncStoreSnapshot(
        activeBindingId: snapshot.activeBindingId,
        stagedBindingId: snapshot.stagedBindingId,
        bindings: bindings,
        namespaces: namespaces,
      ),
    );
    return result.binding;
  });

  Future<String> _sealSecrets(
    String bindingId,
    WebDavSyncSecrets secrets,
  ) async {
    final encoded = utf8.encode(
      jsonEncode(<String, Object?>{
        'version': 1,
        'username': secrets.username,
        'password': secrets.password,
        'syncPassphrase': secrets.syncPassphrase,
      }),
    );
    if (encoded.length > 16 * 1024) {
      throw const FormatException('WebDAV sync credentials exceed their limit');
    }
    return DeviceKeyProvider.cipher.seal(
      encoded,
      associatedData: _secretsAad(bindingId),
    );
  }

  Future<void> _save(WebDavSyncStoreSnapshot snapshot) async {
    final encoded = jsonEncode(snapshot.toJson());
    if (utf8.encode(encoded).length > _stateMaxBytes) {
      throw const FormatException('WebDAV sync state exceeds its limit');
    }
    final device = await DevicePreferences.instance();
    if (!await device.setBudgetedString(_storageKey, encoded)) {
      throw StateError('Could not persist WebDAV sync state');
    }
  }

  static WebDavSyncBinding _requireBinding(
    WebDavSyncStoreSnapshot snapshot,
    String bindingId,
  ) =>
      snapshot.bindings[bindingId] ??
      (throw StateError('WebDAV sync binding is unavailable'));

  static WebDavSyncNamespace _requireNamespace(
    WebDavSyncStoreSnapshot snapshot,
    WebDavSyncBinding binding,
  ) =>
      snapshot.namespaces[binding.namespaceId] ??
      (throw StateError('WebDAV sync namespace is unavailable'));

  static bool _namespaceIsReferenced(
    Iterable<WebDavSyncBinding> bindings,
    String namespaceId,
  ) => bindings.any((binding) => binding.namespaceId == namespaceId);

  static List<int> _secretsAad(String bindingId) =>
      utf8.encode('debrify-webdav-sync-secrets-v1:$bindingId');

  static String _boundedError(Object error) {
    final value = error.toString().replaceAll('\n', ' ').trim();
    return value.length <= 300 ? value : '${value.substring(0, 297)}…';
  }

  void _requireVault() {
    if (!DeviceKeyProvider.isUnlocked) {
      throw const WebDavSyncVaultLockedException();
    }
  }

  String _uuidV4() {
    final bytes = _randomBytes(16);
    if (bytes.length != 16) {
      throw StateError('Secure random source returned the wrong byte count');
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int value) => value.toRadixString(16).padLeft(2, '0');
    final value = bytes.map(hex).join();
    return '${value.substring(0, 8)}-${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  static Uint8List _secureRandomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
