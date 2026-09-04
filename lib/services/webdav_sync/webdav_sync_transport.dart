import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';
import 'package:http/http.dart' as http;

import '../webdav_protocol_client.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_hot_models.dart';
import 'webdav_sync_models.dart';

final class WebDavSyncPeerListing {
  const WebDavSyncPeerListing({
    required this.deviceIds,
    required this.metadata,
  });

  final List<String> deviceIds;
  final WebDavResponseMetadata metadata;
}

/// Cheap server metadata used only to decide whether a full, authenticated
/// manifest read is worthwhile. ETags take precedence over the metadata pair.
final class WebDavSyncManifestValidator {
  const WebDavSyncManifestValidator.etag(this.etag)
    : lastModified = null,
      contentLength = null;

  const WebDavSyncManifestValidator.metadata({
    required this.lastModified,
    required this.contentLength,
  }) : etag = null;

  final String? etag;
  final String? lastModified;
  final int? contentLength;

  static WebDavSyncManifestValidator? fromMetadata(
    WebDavResponseMetadata metadata,
  ) {
    final etag = metadata.etag?.trim();
    if (etag != null && etag.isNotEmpty) {
      return WebDavSyncManifestValidator.etag(etag);
    }
    final lastModified = _header(
      metadata.headers,
      HttpHeaders.lastModifiedHeader,
    )?.trim();
    final rawLength = _header(
      metadata.headers,
      HttpHeaders.contentLengthHeader,
    )?.trim();
    final contentLength = rawLength == null ? null : int.tryParse(rawLength);
    if (lastModified == null ||
        lastModified.isEmpty ||
        contentLength == null ||
        contentLength < 0) {
      return null;
    }
    return WebDavSyncManifestValidator.metadata(
      lastModified: lastModified,
      contentLength: contentLength,
    );
  }

  Map<String, Object?> toJson() => etag != null
      ? <String, Object?>{'etag': etag}
      : <String, Object?>{
          'lastModified': lastModified,
          'contentLength': contentLength,
        };

  factory WebDavSyncManifestValidator.fromJson(Object? source) {
    if (source is! Map) {
      throw const FormatException('Invalid WebDAV manifest validator');
    }
    final etag = source['etag'];
    final lastModified = source['lastModified'];
    final contentLength = source['contentLength'];
    if (etag is String &&
        etag.trim().isNotEmpty &&
        lastModified == null &&
        contentLength == null) {
      return WebDavSyncManifestValidator.etag(etag.trim());
    }
    if (etag == null &&
        lastModified is String &&
        lastModified.trim().isNotEmpty &&
        contentLength is int &&
        contentLength >= 0) {
      return WebDavSyncManifestValidator.metadata(
        lastModified: lastModified.trim(),
        contentLength: contentLength,
      );
    }
    throw const FormatException('Invalid WebDAV manifest validator');
  }

  @override
  bool operator ==(Object other) =>
      other is WebDavSyncManifestValidator &&
      other.etag == etag &&
      other.lastModified == lastModified &&
      other.contentLength == contentLength;

  @override
  int get hashCode => Object.hash(etag, lastModified, contentLength);

  static String? _header(Map<String, String> headers, String name) {
    final direct = headers[name];
    if (direct != null) return direct;
    final lowerName = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lowerName) return entry.value;
    }
    return null;
  }
}

final class WebDavSyncManifestProbe {
  const WebDavSyncManifestProbe({
    required this.exists,
    required this.validator,
  });

  final bool exists;
  final WebDavSyncManifestValidator? validator;
}

/// Validates the representation metadata a successful immutable-section PUT
/// returned without issuing another request. Servers are allowed to omit all
/// of these fields; readers still authenticate the content-addressed section.
void validateWebDavSyncSectionWriteMetadata(
  WebDavResponseMetadata metadata, {
  required int expectedBytes,
}) {
  final headerEtag = _responseHeader(metadata.headers, HttpHeaders.etagHeader);
  final etagWasProvided = metadata.etag != null || headerEtag != null;
  final etag = metadata.etag ?? headerEtag;
  if (etagWasProvided && (etag == null || etag.trim().isEmpty)) {
    throw StateError('WebDAV sync section PUT returned an empty ETag');
  }

  // Some object-backed WebDAV servers expose the stored/uploaded size under
  // an explicit response header. Those values do describe the resource and
  // therefore must agree with the bytes whose hash names the section.
  for (final name in const <String>[
    'x-upload-content-length',
    'x-stored-content-length',
    'x-goog-stored-content-length',
    'x-file-size',
    'x-resource-size',
    'oc-total-length',
  ]) {
    final raw = _responseHeader(metadata.headers, name);
    if (raw == null) continue;
    final parsed = int.tryParse(raw.trim());
    if (parsed == null || parsed < 0 || parsed != expectedBytes) {
      throw StateError(
        'WebDAV sync section PUT returned contradictory size metadata',
      );
    }
  }

  final contentRange = _responseHeader(
    metadata.headers,
    HttpHeaders.contentRangeHeader,
  );
  if (contentRange != null) {
    final match = RegExp(r'/([0-9]+)$').firstMatch(contentRange.trim());
    final total = match == null ? null : int.tryParse(match.group(1)!);
    if (total == null || total != expectedBytes) {
      throw StateError(
        'WebDAV sync section PUT returned a contradictory Content-Range',
      );
    }
  }
}

String? _responseHeader(Map<String, String> headers, String name) {
  final direct = headers[name];
  if (direct != null) return direct;
  final lowerName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lowerName) return entry.value;
  }
  return null;
}

abstract interface class WebDavSyncTransport {
  Future<WebDavBytesResult> readRootMarker();

  Future<WebDavSyncPeerListing> listDeviceIds();

  Future<WebDavBytesResult> readManifest(String deviceId);

  Future<WebDavSyncManifestProbe> probeManifest(String deviceId);

  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  });

  Future<void> ensureOwnLayout(String deviceId);

  Future<WebDavResponseMetadata> writeSection(
    String deviceId,
    String contentHash,
    Uint8List bytes, {
    required int maxBytes,
  });

  Future<WebDavResponseMetadata> writeManifest(
    String deviceId,
    Uint8List bytes,
  );

  void close();
}

/// Optional disk-streaming surface used for the potentially large bootstrap
/// and graph sections. Small hot documents keep the simpler byte API.
abstract interface class WebDavSyncFileTransport {
  Future<WebDavFileResult> readSectionToFile(
    String deviceId,
    WebDavSyncSectionReference reference,
    File destination, {
    required int maxBytes,
  });

  Future<WebDavResponseMetadata> writeSectionFile(
    String deviceId,
    String contentHash,
    File file, {
    required int maxBytes,
  });
}

final class WebDavSyncStoredSection {
  const WebDavSyncStoredSection({
    required this.contentHash,
    required this.lastModifiedMs,
  });

  final String contentHash;
  final int lastModifiedMs;
}

/// Optional own-device maintenance surface. Implementations expose only
/// content-addressed section files, never peer directories or manifests.
abstract interface class WebDavSyncSectionGcTransport {
  Future<List<WebDavSyncStoredSection>> listOwnSections(String deviceId);

  Future<void> deleteOwnSection(String deviceId, String contentHash);
}

/// M5-only mutation surface. Ordinary M4 cycles receive the narrower
/// [WebDavSyncTransport] and therefore cannot create or delete a sync root.
abstract interface class WebDavSyncActivationTransport
    implements WebDavSyncTransport {
  Future<WebDavResponseMetadata> createRootMarker(Uint8List bytes);

  Future<void> deleteDeviceDirectory(String deviceId);
}

final class ProtocolWebDavSyncTransport
    implements
        WebDavSyncActivationTransport,
        WebDavSyncFileTransport,
        WebDavSyncSectionGcTransport {
  ProtocolWebDavSyncTransport({
    required WebDavSyncFolderLocation location,
    required WebDavCredentials credentials,
    http.Client? client,
  }) : _location = location,
       _client = WebDavProtocolClient(
         endpoint: location.endpoint,
         credentials: credentials,
         client: client,
       );

  static const String _listingBody =
      '<?xml version="1.0" encoding="utf-8" ?>'
      '<D:propfind xmlns:D="DAV:"><D:prop><D:displayname/>'
      '<D:resourcetype/></D:prop></D:propfind>';
  static const String _sectionListingBody =
      '<?xml version="1.0" encoding="utf-8" ?>'
      '<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/>'
      '<D:getlastmodified/></D:prop></D:propfind>';

  final WebDavSyncFolderLocation _location;
  final WebDavProtocolClient _client;

  String get _syncRoot => _join(_location.folderPath, 'debrify-sync');
  String get _devices => _join(_syncRoot, 'devices');

  @override
  Future<WebDavBytesResult> readRootMarker() => _client.getBytes(
    path: _location.rootMarkerPath,
    maxBytes: WebDavSyncCodec.rootMarkerMaxBytes,
  );

  @override
  Future<WebDavSyncPeerListing> listDeviceIds() async {
    final result = await _client.propfind(
      path: _devices,
      depth: 1,
      body: _listingBody,
      collection: true,
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
    late final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(result.bytes));
    } on Exception catch (error) {
      throw WebDavException.malformed(
        'WebDAV returned an invalid sync device listing',
        cause: error,
      );
    }
    final responseNodes = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'response')
        .toList(growable: false);
    if (responseNodes.length > WebDavSyncLimits.maxPeers + 1) {
      throw const WebDavException(
        kind: WebDavErrorKind.malformedResponse,
        message: 'WebDAV sync device listing exceeds its peer limit',
      );
    }
    final ids = <String>{};
    for (final response in responseNodes) {
      final isCollection = response.descendants.whereType<XmlElement>().any(
        (element) => element.name.local == 'collection',
      );
      if (!isCollection) continue;
      final href = _childText(response, 'href');
      if (href == null) continue;
      final id = _lastPathSegment(href);
      if (id == null || id == 'devices') continue;
      if (!_safeDeviceId.hasMatch(id)) continue;
      ids.add(id);
    }
    if (ids.length > WebDavSyncLimits.maxPeers) {
      throw const WebDavException(
        kind: WebDavErrorKind.malformedResponse,
        message: 'WebDAV sync device listing exceeds its peer limit',
      );
    }
    return WebDavSyncPeerListing(
      deviceIds: List<String>.unmodifiable(ids.toList()..sort()),
      metadata: result.metadata,
    );
  }

  @override
  Future<WebDavBytesResult> readManifest(String deviceId) {
    _validateDeviceId(deviceId);
    return _client.getBytes(
      path: _join(_devices, '$deviceId/manifest.enc'),
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
  }

  @override
  Future<WebDavSyncManifestProbe> probeManifest(String deviceId) async {
    _validateDeviceId(deviceId);
    final result = await _client.exists(
      path: _join(_devices, '$deviceId/manifest.enc'),
    );
    return WebDavSyncManifestProbe(
      exists: result.exists,
      validator: result.exists
          ? WebDavSyncManifestValidator.fromMetadata(result.metadata)
          : null,
    );
  }

  @override
  Future<WebDavBytesResult> readSection(
    String deviceId,
    WebDavSyncSectionReference reference, {
    required int maxBytes,
  }) {
    _validateDeviceId(deviceId);
    if (reference.size > maxBytes) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV sync section exceeds its byte limit',
      );
    }
    return _client.getBytes(
      path: _join(_devices, '$deviceId/sections/${reference.contentHash}.enc'),
      maxBytes: maxBytes,
      // Servers throttle repeated large-object reads with mid-body pauses;
      // a large section is allowed a longer stall before it counts as dead.
      bodyInactivityTimeout: reference.size > 8 * 1024 * 1024
          ? const Duration(seconds: 90)
          : null,
    );
  }

  @override
  Future<WebDavFileResult> readSectionToFile(
    String deviceId,
    WebDavSyncSectionReference reference,
    File destination, {
    required int maxBytes,
  }) {
    _validateDeviceId(deviceId);
    if (reference.size > maxBytes) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV sync section exceeds its byte limit',
      );
    }
    return _client.downloadToFile(
      path: _join(_devices, '$deviceId/sections/${reference.contentHash}.enc'),
      destination: destination,
      maxBytes: maxBytes,
    );
  }

  @override
  Future<void> ensureOwnLayout(String deviceId) async {
    _validateDeviceId(deviceId);
    await _client.ensureCollection(_join(_devices, '$deviceId/sections'));
  }

  @override
  Future<WebDavResponseMetadata> writeSection(
    String deviceId,
    String contentHash,
    Uint8List bytes, {
    required int maxBytes,
  }) {
    _validateDeviceId(deviceId);
    _validateHash(contentHash);
    return _client.putBytes(
      path: _join(_devices, '$deviceId/sections/$contentHash.enc'),
      bytes: bytes,
      maxBytes: maxBytes,
      ifNoneMatch: '*',
    );
  }

  @override
  Future<WebDavResponseMetadata> writeSectionFile(
    String deviceId,
    String contentHash,
    File file, {
    required int maxBytes,
  }) {
    _validateDeviceId(deviceId);
    _validateHash(contentHash);
    return _client.uploadFile(
      path: _join(_devices, '$deviceId/sections/$contentHash.enc'),
      file: file,
      maxBytes: maxBytes,
      ifNoneMatch: '*',
    );
  }

  @override
  Future<WebDavResponseMetadata> writeManifest(
    String deviceId,
    Uint8List bytes,
  ) {
    _validateDeviceId(deviceId);
    return _client.putBytes(
      path: _join(_devices, '$deviceId/manifest.enc'),
      bytes: bytes,
      maxBytes: WebDavSyncLimits.maxManifestBytes,
    );
  }

  @override
  Future<WebDavResponseMetadata> createRootMarker(Uint8List bytes) async {
    final metadata = await _client.putBytes(
      path: _location.rootMarkerPath,
      bytes: bytes,
      maxBytes: WebDavSyncCodec.rootMarkerMaxBytes,
      ifNoneMatch: '*',
      createParents: false,
    );
    if (metadata.statusCode != 201) {
      throw WebDavException(
        kind: WebDavErrorKind.unexpectedStatus,
        message: 'WebDAV did not prove create-only sync root ownership',
        statusCode: metadata.statusCode,
        uri: metadata.uri,
      );
    }
    return metadata;
  }

  @override
  Future<void> deleteDeviceDirectory(String deviceId) async {
    _validateDeviceId(deviceId);
    await _client.deletePath(path: _join(_devices, deviceId), collection: true);
  }

  @override
  Future<List<WebDavSyncStoredSection>> listOwnSections(String deviceId) async {
    _validateDeviceId(deviceId);
    final result = await _client.propfind(
      path: _join(_devices, '$deviceId/sections'),
      depth: 1,
      body: _sectionListingBody,
      collection: true,
      maxBytes: WebDavSyncLimits.maxSectionListingBytes,
    );
    late final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(result.bytes));
    } on Exception catch (error) {
      throw WebDavException.malformed(
        'WebDAV returned an invalid sync section listing',
        cause: error,
      );
    }
    final responseNodes = document.descendants
        .whereType<XmlElement>()
        .where((element) => element.name.local == 'response')
        .toList(growable: false);
    final sections = <String, WebDavSyncStoredSection>{};
    for (final response in responseNodes) {
      final isCollection = response.descendants.whereType<XmlElement>().any(
        (element) => element.name.local == 'collection',
      );
      if (isCollection) continue;
      final href = _childText(response, 'href');
      final name = href == null ? null : _lastPathSegment(href);
      if (name == null || !name.endsWith('.enc')) continue;
      final contentHash = name.substring(0, name.length - 4);
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(contentHash)) continue;
      final rawModified = _childText(response, 'getlastmodified');
      if (rawModified == null) continue;
      try {
        sections[contentHash] = WebDavSyncStoredSection(
          contentHash: contentHash,
          lastModifiedMs: HttpDate.parse(
            rawModified.trim(),
          ).toUtc().millisecondsSinceEpoch,
        );
      } on Exception {
        // Unknown age is never safe to collect.
      }
    }
    final ordered = sections.values.toList(growable: false)
      ..sort((left, right) {
        final byAge = left.lastModifiedMs.compareTo(right.lastModifiedMs);
        return byAge != 0
            ? byAge
            : left.contentHash.compareTo(right.contentHash);
      });
    // The response itself is already byte-bounded. Return the oldest bounded
    // batch instead of rejecting an over-cap directory: rejection would make
    // GC permanently unable to delete the entries that caused the overflow.
    final bounded = ordered.length > WebDavSyncLimits.maxStoredSectionsPerDevice
        ? ordered.sublist(0, WebDavSyncLimits.maxStoredSectionsPerDevice)
        : ordered;
    return List<WebDavSyncStoredSection>.unmodifiable(bounded);
  }

  @override
  Future<void> deleteOwnSection(String deviceId, String contentHash) async {
    _validateDeviceId(deviceId);
    _validateHash(contentHash);
    await _client.deletePath(
      path: _join(_devices, '$deviceId/sections/$contentHash.enc'),
    );
  }

  @override
  void close() => _client.close();

  static String _join(String left, String right) => <String>[
    ...left.split('/').where((segment) => segment.isNotEmpty),
    ...right.split('/').where((segment) => segment.isNotEmpty),
  ].join('/');

  static String? _childText(XmlElement parent, String localName) {
    for (final element in parent.descendants.whereType<XmlElement>()) {
      if (element.name.local == localName) return element.innerText;
    }
    return null;
  }

  static String? _lastPathSegment(String href) {
    try {
      final trimmed = href.trim();
      final rawSegments = trimmed.split('/');
      if (rawSegments.any((value) {
        final decoded = Uri.decodeComponent(value);
        return decoded == '.' || decoded == '..';
      })) {
        return null;
      }
      final uri = Uri.parse(trimmed);
      final segments = uri.pathSegments.where((value) => value.isNotEmpty);
      if (segments.any((value) => value == '.' || value == '..')) return null;
      return segments.isEmpty ? null : segments.last;
    } on FormatException {
      return null;
    }
  }

  static void _validateDeviceId(String value) {
    if (!_safeDeviceId.hasMatch(value)) {
      throw ArgumentError.value(value, 'deviceId', 'Invalid sync device ID');
    }
  }

  static void _validateHash(String value) {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
      throw ArgumentError.value(value, 'contentHash', 'Invalid content hash');
    }
  }
}

final RegExp _safeDeviceId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$');
