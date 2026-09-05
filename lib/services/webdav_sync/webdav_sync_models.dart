import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../../models/webdav_item.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_codec.dart';

enum WebDavSyncLifecycle {
  unconfigured,
  configured,
  awaitingSeedCommit,
  rootVerified,
  awaitingAdoption,
  active,
  error,
}

const String webDavSyncMissingStateMessage =
    'WebDAV sync local state is missing and must be safely reconnected';

final class WebDavSyncFolderLocation {
  WebDavSyncFolderLocation._({
    required this.endpoint,
    required this.folderPath,
    required this.serverName,
  });

  factory WebDavSyncFolderLocation({
    required String endpoint,
    required String folderPath,
    required String serverName,
  }) {
    final parsed = WebDavProtocolClient.parseEndpoint(endpoint);
    final normalizedEndpoint = _normalizeEndpoint(parsed);
    final normalizedFolder = normalizeFolderPath(folderPath);
    final normalizedName = serverName.trim();
    return WebDavSyncFolderLocation._(
      endpoint: normalizedEndpoint,
      folderPath: normalizedFolder,
      serverName: normalizedName.isEmpty
          ? normalizedEndpoint.host
          : normalizedName,
    );
  }

  factory WebDavSyncFolderLocation.fromConfig(
    WebDavConfig config,
    String folderPath,
  ) => WebDavSyncFolderLocation(
    endpoint: config.baseUrl,
    folderPath: folderPath,
    serverName: config.name,
  );

  final Uri endpoint;
  final String folderPath;
  final String serverName;

  String get rootAuthorityPath => folderPath.isEmpty
      ? 'debrify-sync/circle.authority'
      : '$folderPath/debrify-sync/circle.authority';

  /// Legacy layout, retained only for authenticated repair/upgrade reads.
  String get rootMarkerPath => folderPath.isEmpty
      ? 'debrify-sync/circle.json.enc'
      : '$folderPath/debrify-sync/circle.json.enc';

  String get rootKeyPath => folderPath.isEmpty
      ? 'debrify-sync/circle.key'
      : '$folderPath/debrify-sync/circle.key';

  Uri get resolvedFolderUri => WebDavProtocolClient.resolvePath(
    endpoint: endpoint,
    path: folderPath,
    collection: true,
  );

  String get fingerprint {
    final digest = crypto.sha256.convert(
      utf8.encode('${endpoint.toString()}\n$folderPath'),
    );
    return digest.toString();
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'endpoint': endpoint.toString(),
    'folderPath': folderPath,
    'serverName': serverName,
  };

  factory WebDavSyncFolderLocation.fromJson(Map<String, dynamic> json) {
    final endpoint = json['endpoint'];
    final folderPath = json['folderPath'];
    final serverName = json['serverName'];
    if (endpoint is! String || folderPath is! String || serverName is! String) {
      throw const FormatException('Invalid WebDAV sync folder binding');
    }
    return WebDavSyncFolderLocation(
      endpoint: endpoint,
      folderPath: folderPath,
      serverName: serverName,
    );
  }

  static String normalizeFolderPath(String source) {
    final segments = source
        .trim()
        .replaceAll('\\', '/')
        .split('/')
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    if (segments.length > WebDavProtocolClient.maxPathSegments ||
        segments.any((segment) => segment == '.' || segment == '..')) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV sync folder path is invalid',
      );
    }
    return segments.join('/');
  }

  static Uri _normalizeEndpoint(Uri source) {
    final pathSegments = source.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList(growable: false);
    return source
        .replace(
          scheme: source.scheme.toLowerCase(),
          host: source.host.toLowerCase(),
          pathSegments: <String>[
            ...pathSegments,
            if (pathSegments.isNotEmpty) '',
          ],
          query: source.hasQuery ? source.query : null,
        )
        .removeFragment();
  }
}

sealed class WebDavSyncRootKeyFileException extends FormatException {
  const WebDavSyncRootKeyFileException(super.message);
}

final class WebDavSyncRootKeyFileSizeException
    extends WebDavSyncRootKeyFileException {
  const WebDavSyncRootKeyFileSizeException()
    : super('Invalid WebDAV sync keyfile size');
}

final class WebDavSyncRootKeyFileFormatException
    extends WebDavSyncRootKeyFileException {
  const WebDavSyncRootKeyFileFormatException()
    : super('Invalid WebDAV sync keyfile');
}

final class WebDavSyncRootKeyFileVersionException
    extends WebDavSyncRootKeyFileException {
  const WebDavSyncRootKeyFileVersionException()
    : super('Unsupported WebDAV sync keyfile version');
}

/// Legacy split-layout keyfile, retained only for authenticated read/upgrade.
///
/// Parsing remains strict and no parse error includes the supplied bytes or
/// the secret they may contain. New circles never write this representation.
final class WebDavSyncRootKeyFile {
  const WebDavSyncRootKeyFile({required this.syncPassphrase});

  static const int version = 1;
  static const int maxBytes = 4096;

  final String syncPassphrase;

  Uint8List encode() {
    WebDavSyncCodec.validatePassphrase(syncPassphrase);
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'version': version,
          'syncPassphrase': syncPassphrase,
        }),
      ),
    );
  }

  factory WebDavSyncRootKeyFile.parse(List<int> rawBytes) {
    if (rawBytes.isEmpty || rawBytes.length > maxBytes) {
      throw const WebDavSyncRootKeyFileSizeException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(rawBytes));
    } catch (_) {
      throw const WebDavSyncRootKeyFileFormatException();
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 2 ||
        decoded.keys.any(
          (key) => key != 'version' && key != 'syncPassphrase',
        )) {
      throw const WebDavSyncRootKeyFileFormatException();
    }
    final encodedVersion = decoded['version'];
    if (encodedVersion is! int || encodedVersion != version) {
      throw const WebDavSyncRootKeyFileVersionException();
    }
    final syncPassphrase = decoded['syncPassphrase'];
    if (syncPassphrase is! String) {
      throw const WebDavSyncRootKeyFileFormatException();
    }
    try {
      WebDavSyncCodec.validatePassphrase(syncPassphrase);
    } on ArgumentError {
      throw const WebDavSyncRootKeyFileFormatException();
    }
    return WebDavSyncRootKeyFile(syncPassphrase: syncPassphrase);
  }
}

sealed class WebDavSyncAuthorityFileException extends FormatException {
  const WebDavSyncAuthorityFileException(super.message);
}

final class WebDavSyncAuthorityFileSizeException
    extends WebDavSyncAuthorityFileException {
  const WebDavSyncAuthorityFileSizeException()
    : super('Invalid WebDAV sync authority size');
}

final class WebDavSyncAuthorityFileFormatException
    extends WebDavSyncAuthorityFileException {
  const WebDavSyncAuthorityFileFormatException()
    : super('Invalid WebDAV sync authority');
}

final class WebDavSyncAuthorityFileVersionException
    extends WebDavSyncAuthorityFileException {
  const WebDavSyncAuthorityFileVersionException()
    : super('Unsupported WebDAV sync authority version');
}

/// The circle's sole remote authority object.
///
/// Keeping the sealed marker and its opening secret in one strictly parsed
/// representation means an LWW WebDAV store can replace only a complete,
/// internally consistent authority. A hash pins the exact encoded bytes;
/// only the encrypted inner marker is retained alongside that hash locally.
final class WebDavSyncAuthorityFile {
  const WebDavSyncAuthorityFile({
    required this.markerBytes,
    required this.syncPassphrase,
  });

  static const int version = 1;
  static const int maxBytes = 96 * 1024;

  final Uint8List markerBytes;
  final String syncPassphrase;

  Uint8List encode() {
    _validate();
    final encoded = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'version': version,
          'marker': base64Encode(markerBytes),
          'syncPassphrase': syncPassphrase,
        }),
      ),
    );
    if (encoded.length > maxBytes) {
      throw const WebDavSyncAuthorityFileSizeException();
    }
    return encoded;
  }

  factory WebDavSyncAuthorityFile.parse(List<int> rawBytes) {
    if (rawBytes.isEmpty || rawBytes.length > maxBytes) {
      throw const WebDavSyncAuthorityFileSizeException();
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(rawBytes));
    } catch (_) {
      throw const WebDavSyncAuthorityFileFormatException();
    }
    if (decoded is! Map<String, dynamic> ||
        decoded.length != 3 ||
        decoded.keys.any(
          (key) =>
              key != 'version' && key != 'marker' && key != 'syncPassphrase',
        )) {
      throw const WebDavSyncAuthorityFileFormatException();
    }
    final encodedVersion = decoded['version'];
    if (encodedVersion is! int || encodedVersion != version) {
      throw const WebDavSyncAuthorityFileVersionException();
    }
    final encodedMarker = decoded['marker'];
    final syncPassphrase = decoded['syncPassphrase'];
    if (encodedMarker is! String || syncPassphrase is! String) {
      throw const WebDavSyncAuthorityFileFormatException();
    }
    late final Uint8List markerBytes;
    try {
      markerBytes = Uint8List.fromList(base64Decode(encodedMarker));
    } catch (_) {
      throw const WebDavSyncAuthorityFileFormatException();
    }
    if (base64Encode(markerBytes) != encodedMarker) {
      throw const WebDavSyncAuthorityFileFormatException();
    }
    final result = WebDavSyncAuthorityFile(
      markerBytes: markerBytes,
      syncPassphrase: syncPassphrase,
    );
    try {
      result._validate();
    } on ArgumentError {
      throw const WebDavSyncAuthorityFileFormatException();
    } on WebDavSyncAuthorityFileSizeException {
      rethrow;
    }
    return result;
  }

  void _validate() {
    if (markerBytes.isEmpty ||
        markerBytes.length > WebDavSyncCodec.rootMarkerMaxBytes) {
      throw const WebDavSyncAuthorityFileSizeException();
    }
    WebDavSyncCodec.validatePassphrase(syncPassphrase);
  }
}

/// Activation could not establish a readable standing authority object.
///
/// The failure never includes remote bytes or secrets.
final class WebDavSyncAuthorityClaimException implements Exception {
  const WebDavSyncAuthorityClaimException();

  @override
  String toString() =>
      'This WebDAV provider is unsupported, or the sync folder is damaged.';
}

/// A successful sentinel write was not returned by the immediately following
/// read. Such a store cannot provide the linearizable authority register sync
/// requires. Conditional-create support is deliberately irrelevant.
final class WebDavSyncStoreNotLinearizableException implements Exception {
  const WebDavSyncStoreNotLinearizableException({
    this.probeStep,
    this.statusCode,
    this.exceptionKind,
  });

  final int? probeStep;
  final int? statusCode;
  final WebDavErrorKind? exceptionKind;

  static const String userMessage =
      'This WebDAV server does not reliably return newly written sync data.';

  @override
  String toString() => userMessage;
}

/// The linearizability smoke check could not reach a definitive
/// response-backed outcome. Setup may be retried without changing authority.
final class WebDavSyncSetupInconclusiveException implements Exception {
  const WebDavSyncSetupInconclusiveException({
    this.probeStep,
    this.statusCode,
    this.exceptionKind,
  });

  /// One-based probe operation shown without the private sentinel path.
  final int? probeStep;
  final int? statusCode;
  final WebDavErrorKind? exceptionKind;

  static const String userMessage =
      "Couldn't verify the sync server right now. "
      'Check your connection and try again.';

  String get message => userMessage;

  @override
  String toString() => message;
}

/// The imported profile has already become local authority. The original
/// failure remains available for diagnostics, but setup must roll forward.
final class WebDavSyncPostHandoffException implements Exception {
  const WebDavSyncPostHandoffException(this.error);

  final Object error;

  @override
  String toString() => error.toString();
}

final class WebDavSyncRootDocument {
  const WebDavSyncRootDocument({
    required this.circleId,
    required this.createdAt,
    required this.schemaFloor,
    required this.kdfSalt,
  });

  final String circleId;
  final DateTime createdAt;
  final int schemaFloor;
  final Uint8List kdfSalt;
}

final class WebDavSyncBinding {
  const WebDavSyncBinding({
    required this.id,
    required this.location,
    required this.lifecycle,
    required this.namespaceId,
    required this.sealedSecrets,
    required this.updatedAt,
    this.circleId,
    this.errorMessage,
    this.completeOnboarding = false,
  });

  final String id;
  final WebDavSyncFolderLocation location;
  final WebDavSyncLifecycle lifecycle;
  final String namespaceId;
  final String sealedSecrets;
  final DateTime updatedAt;
  final String? circleId;
  final String? errorMessage;

  /// Local-only first-run intent. This is never included in circle data.
  final bool completeOnboarding;

  bool get isExistingRoot => circleId != null;

  bool get requiresStateReconnect =>
      lifecycle == WebDavSyncLifecycle.error &&
      errorMessage == webDavSyncMissingStateMessage;

  WebDavSyncBinding copyWith({
    WebDavSyncLifecycle? lifecycle,
    String? namespaceId,
    String? sealedSecrets,
    DateTime? updatedAt,
    String? circleId,
    bool clearCircleId = false,
    String? errorMessage,
    bool clearError = false,
    bool? completeOnboarding,
  }) => WebDavSyncBinding(
    id: id,
    location: location,
    lifecycle: lifecycle ?? this.lifecycle,
    namespaceId: namespaceId ?? this.namespaceId,
    sealedSecrets: sealedSecrets ?? this.sealedSecrets,
    updatedAt: updatedAt ?? this.updatedAt,
    circleId: clearCircleId ? null : (circleId ?? this.circleId),
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    completeOnboarding: completeOnboarding ?? this.completeOnboarding,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'location': location.toJson(),
    'lifecycle': lifecycle.name,
    'namespaceId': namespaceId,
    'sealedSecrets': sealedSecrets,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    if (circleId != null) 'circleId': circleId,
    if (errorMessage != null) 'errorMessage': errorMessage,
    if (completeOnboarding) 'completeOnboarding': true,
  };

  factory WebDavSyncBinding.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final location = json['location'];
    final lifecycleName = json['lifecycle'];
    final namespaceId = json['namespaceId'];
    final sealedSecrets = json['sealedSecrets'];
    final updatedAt = json['updatedAt'];
    if (id is! String ||
        id.isEmpty ||
        location is! Map ||
        lifecycleName is! String ||
        namespaceId is! String ||
        namespaceId.isEmpty ||
        sealedSecrets is! String ||
        sealedSecrets.isEmpty ||
        updatedAt is! String) {
      throw const FormatException('Invalid WebDAV sync binding');
    }
    final lifecycle = WebDavSyncLifecycle.values
        .where((value) => value.name == lifecycleName)
        .firstOrNull;
    final parsedTime = DateTime.tryParse(updatedAt);
    if (lifecycle == null || parsedTime == null) {
      throw const FormatException('Invalid WebDAV sync binding state');
    }
    final circleId = json['circleId'];
    final error = json['errorMessage'];
    final completeOnboarding = json['completeOnboarding'] ?? false;
    if (circleId != null && circleId is! String ||
        error != null && error is! String ||
        completeOnboarding is! bool) {
      throw const FormatException('Invalid WebDAV sync binding metadata');
    }
    final typedCircleId = circleId as String?;
    if (typedCircleId != null && !_safeSyncId.hasMatch(typedCircleId)) {
      throw const FormatException('Invalid WebDAV sync circle ID');
    }
    final expectedNamespace = typedCircleId == null
        ? 'candidate:$id'
        : 'circle:$typedCircleId';
    if (namespaceId != expectedNamespace) {
      throw const FormatException('WebDAV sync binding namespace mismatch');
    }
    if ((lifecycle == WebDavSyncLifecycle.awaitingSeedCommit &&
            typedCircleId != null) ||
        ((lifecycle == WebDavSyncLifecycle.rootVerified ||
                lifecycle == WebDavSyncLifecycle.awaitingAdoption ||
                lifecycle == WebDavSyncLifecycle.active) &&
            typedCircleId == null)) {
      throw const FormatException('Invalid WebDAV sync lifecycle identity');
    }
    final parsedLocation = WebDavSyncFolderLocation.fromJson(
      Map<String, dynamic>.from(location),
    );
    if (id != parsedLocation.fingerprint) {
      throw const FormatException('WebDAV sync binding fingerprint mismatch');
    }
    return WebDavSyncBinding(
      id: id,
      location: parsedLocation,
      lifecycle: lifecycle,
      namespaceId: namespaceId,
      sealedSecrets: sealedSecrets,
      updatedAt: parsedTime.toUtc(),
      circleId: typedCircleId,
      errorMessage: error as String?,
      completeOnboarding: completeOnboarding,
    );
  }
}

String webDavSyncAuthorityHash(List<int> bytes) =>
    crypto.sha256.convert(bytes).toString();

Uint8List webDavSyncInnerMarker(List<int> bytes) {
  try {
    return WebDavSyncAuthorityFile.parse(bytes).markerBytes;
  } on WebDavSyncAuthorityFileException {
    return Uint8List.fromList(bytes);
  }
}

final class WebDavSyncNamespace {
  const WebDavSyncNamespace({
    required this.id,
    required this.deviceId,
    this.markerBytes,
    this.authorityContentHash,
    this.values = const <String, Object?>{},
  });

  final String id;
  final String deviceId;
  final Uint8List? markerBytes;
  final String? authorityContentHash;

  String? get pinnedAuthorityHash =>
      authorityContentHash ??
      (markerBytes == null ? null : webDavSyncAuthorityHash(markerBytes!));

  bool matchesAuthority(List<int> bytes) =>
      pinnedAuthorityHash == webDavSyncAuthorityHash(bytes);

  /// Cycle pins may carry the full authority or its persisted inner marker.
  /// The separate authority hash must still identify the pinned authority.
  bool matchesAuthorityPin(List<int>? bytes, String? contentHash) {
    if (bytes == null ||
        markerBytes == null ||
        contentHash != pinnedAuthorityHash) {
      return false;
    }
    return matchesAuthority(bytes) ||
        webDavSyncAuthorityHash(bytes) == webDavSyncAuthorityHash(markerBytes!);
  }

  final Map<String, Object?> values;

  WebDavSyncNamespace copyWith({
    String? id,
    String? deviceId,
    Uint8List? markerBytes,
    String? authorityContentHash,
    bool clearMarker = false,
    Map<String, Object?>? values,
  }) => WebDavSyncNamespace(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    markerBytes: clearMarker ? null : (markerBytes ?? this.markerBytes),
    authorityContentHash: clearMarker
        ? null
        : (authorityContentHash ?? this.authorityContentHash),
    values: values ?? this.values,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'deviceId': deviceId,
    if (markerBytes != null)
      'markerBytes': base64Encode(webDavSyncInnerMarker(markerBytes!)),
    if (pinnedAuthorityHash != null)
      'authorityContentHash': pinnedAuthorityHash,
    if (values.isNotEmpty) 'values': values,
  };

  factory WebDavSyncNamespace.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final deviceId = json['deviceId'];
    final encodedMarker = json['markerBytes'];
    final rawValues = json['values'];
    if (id is! String ||
        id.isEmpty ||
        !_isNamespaceId(id) ||
        deviceId is! String ||
        !_safeSyncId.hasMatch(deviceId) ||
        encodedMarker != null && encodedMarker is! String ||
        rawValues != null && rawValues is! Map) {
      throw const FormatException('Invalid WebDAV sync namespace');
    }
    Uint8List? marker;
    try {
      marker = encodedMarker == null
          ? null
          : Uint8List.fromList(base64Decode(encodedMarker as String));
    } on FormatException {
      throw const FormatException('Invalid WebDAV sync marker pin');
    }
    if (marker != null &&
        (marker.isEmpty || marker.length > WebDavSyncAuthorityFile.maxBytes)) {
      throw const FormatException('Invalid WebDAV sync marker pin');
    }
    if ((id.startsWith('circle:') && marker == null) ||
        (id.startsWith('candidate:') && marker != null)) {
      throw const FormatException('Invalid WebDAV sync namespace marker');
    }
    return WebDavSyncNamespace(
      id: id,
      deviceId: deviceId,
      markerBytes: marker == null ? null : webDavSyncInnerMarker(marker),
      authorityContentHash: json['authorityContentHash'] is String
          ? json['authorityContentHash'] as String
          : (marker == null ? null : webDavSyncAuthorityHash(marker)),
      values: rawValues == null
          ? const <String, Object?>{}
          : Map<String, Object?>.from(rawValues as Map),
    );
  }
}

final class WebDavSyncStoreSnapshot {
  const WebDavSyncStoreSnapshot({
    this.activeBindingId,
    this.stagedBindingId,
    this.bindings = const <String, WebDavSyncBinding>{},
    this.namespaces = const <String, WebDavSyncNamespace>{},
  });

  final String? activeBindingId;
  final String? stagedBindingId;
  final Map<String, WebDavSyncBinding> bindings;
  final Map<String, WebDavSyncNamespace> namespaces;

  WebDavSyncBinding? get activeBinding =>
      activeBindingId == null ? null : bindings[activeBindingId];

  WebDavSyncBinding? get stagedBinding =>
      stagedBindingId == null ? null : bindings[stagedBindingId];

  WebDavSyncNamespace? namespaceFor(WebDavSyncBinding binding) =>
      namespaces[binding.namespaceId];

  /// Resolves transport authority from the persisted pointer, never from an
  /// arbitrary binding that happens to share the same circle namespace.
  /// Multiple folders may authenticate the same root, so namespace identity
  /// alone cannot decide which endpoint a cycle is allowed to contact.
  WebDavSyncBinding? bindingForCycle({
    required String namespaceId,
    required bool preActivation,
  }) {
    final binding = preActivation ? stagedBinding : activeBinding;
    if (binding == null || binding.namespaceId != namespaceId) return null;
    final validLifecycle = preActivation
        ? binding.lifecycle == WebDavSyncLifecycle.rootVerified ||
              binding.lifecycle == WebDavSyncLifecycle.awaitingAdoption
        : binding.lifecycle == WebDavSyncLifecycle.active;
    return validLifecycle ? binding : null;
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    if (activeBindingId != null) 'activeBindingId': activeBindingId,
    if (stagedBindingId != null) 'stagedBindingId': stagedBindingId,
    'bindings': <String, Object?>{
      for (final entry in bindings.entries) entry.key: entry.value.toJson(),
    },
    'namespaces': <String, Object?>{
      for (final entry in namespaces.entries) entry.key: entry.value.toJson(),
    },
  };

  factory WebDavSyncStoreSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        json['bindings'] is! Map ||
        json['namespaces'] is! Map) {
      throw const FormatException('Unsupported WebDAV sync state');
    }
    final rawBindings = json['bindings'] as Map;
    final rawNamespaces = json['namespaces'] as Map;
    if (rawBindings.length > 32 || rawNamespaces.length > 32) {
      throw const FormatException(
        'WebDAV sync binding state exceeds its limit',
      );
    }
    final bindings = <String, WebDavSyncBinding>{};
    for (final entry in rawBindings.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid WebDAV sync bindings');
      }
      final binding = WebDavSyncBinding.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (binding.id != entry.key) {
        throw const FormatException('WebDAV sync binding key mismatch');
      }
      bindings[entry.key as String] = binding;
    }
    final namespaces = <String, WebDavSyncNamespace>{};
    for (final entry in rawNamespaces.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Invalid WebDAV sync namespaces');
      }
      final namespace = WebDavSyncNamespace.fromJson(
        Map<String, dynamic>.from(entry.value as Map),
      );
      if (namespace.id != entry.key) {
        throw const FormatException('WebDAV sync namespace key mismatch');
      }
      namespaces[entry.key as String] = namespace;
    }
    String? pointer(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is! String || !bindings.containsKey(value)) {
        throw const FormatException('Invalid WebDAV sync binding pointer');
      }
      return value;
    }

    for (final binding in bindings.values) {
      if (!namespaces.containsKey(binding.namespaceId)) {
        throw const FormatException('WebDAV sync namespace is missing');
      }
    }
    return WebDavSyncStoreSnapshot(
      activeBindingId: pointer('activeBindingId'),
      stagedBindingId: pointer('stagedBindingId'),
      bindings: Map<String, WebDavSyncBinding>.unmodifiable(bindings),
      namespaces: Map<String, WebDavSyncNamespace>.unmodifiable(namespaces),
    );
  }
}

final RegExp _safeSyncId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$');

bool _isNamespaceId(String value) {
  if (value.startsWith('circle:')) {
    return _safeSyncId.hasMatch(value.substring('circle:'.length));
  }
  if (value.startsWith('candidate:')) {
    return RegExp(
      r'^[0-9a-f]{64}$',
    ).hasMatch(value.substring('candidate:'.length));
  }
  return false;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
