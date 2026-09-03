import 'dart:convert';

import 'webdav_sync_codec.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_hot_models.dart';

/// Why a durable library row is being changed.
///
/// Only [user] mutations create local stamps and schedule recurring sync.
/// Sync materialization has its own exact-stamp writer; the remaining origins
/// deliberately leave the sidecar untouched.
enum WebDavSyncMutationOrigin {
  user,
  syncApply,
  migration,
  maintenance,
  rollback,
}

abstract final class WebDavSyncLibraryKinds {
  static const String hiddenGroups = 'hidden_groups';
}

final class WebDavSyncRecordState {
  const WebDavSyncRecordState({
    required this.kind,
    required this.ownerKey,
    required this.itemKey,
    required this.stamp,
    required this.deleted,
    this.aux,
  });

  final String kind;
  final String ownerKey;
  final String itemKey;
  final WebDavSyncStamp stamp;
  final bool deleted;
  final String? aux;
}

final class WebDavSyncDatabaseStateSnapshot {
  const WebDavSyncDatabaseStateSnapshot({
    required this.mutationRevision,
    this.records = const <WebDavSyncRecordState>[],
  });

  final int mutationRevision;
  final List<WebDavSyncRecordState> records;
}

final class WebDavSyncDatabaseRevisions {
  const WebDavSyncDatabaseRevisions({
    required this.debrifyTv,
    required this.iptvCatalog,
  });

  final int debrifyTv;
  final int iptvCatalog;

  Map<String, Object?> toJson() => <String, Object?>{
    'debrifyTv': debrifyTv,
    'iptvCatalog': iptvCatalog,
  };

  factory WebDavSyncDatabaseRevisions.fromJson(Object? source) {
    final json = _object(source, 'database revisions');
    final tv = json['debrifyTv'];
    final catalog = json['iptvCatalog'];
    if (json.length != 2 ||
        tv is! int ||
        tv < 0 ||
        catalog is! int ||
        catalog < 0) {
      throw const FormatException('Invalid WebDAV sync database revisions');
    }
    return WebDavSyncDatabaseRevisions(debrifyTv: tv, iptvCatalog: catalog);
  }
}

enum WebDavSyncLibraryApplyResult { applied, conflict }

final class WebDavSyncHiddenGroupTarget {
  const WebDavSyncHiddenGroupTarget({
    required this.catalogKey,
    required this.group,
    required this.leaf,
  });

  final String catalogKey;
  final String group;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

/// Local-only hint retained in sidecar [WebDavSyncRecordState.aux] when a
/// catalog key is about to become unreachable after a credential edit. It is
/// never copied to a library document: the local resource ID is projected
/// through the authenticated identity map first, and only while still granted
/// to the profile.
final class WebDavSyncCatalogOwnerReference {
  const WebDavSyncCatalogOwnerReference({
    required this.localResourceId,
    required this.variant,
  });

  static const Set<String> variants = <String>{
    'local',
    'm3u',
    'xc-live',
    'xc-vod',
    'xc-series',
  };

  final String localResourceId;
  final String variant;

  String toAux() {
    if (!_isLocalResourceId(localResourceId) || !variants.contains(variant)) {
      throw const FormatException('Invalid WebDAV sync catalog owner hint');
    }
    return WebDavSyncCodec.canonicalJson(<String, Object?>{
      'localResourceId': localResourceId,
      'variant': variant,
    });
  }

  static WebDavSyncCatalogOwnerReference? tryFromAux(String? source) {
    if (source == null || source.length > 512) return null;
    try {
      final json = _object(jsonDecode(source), 'catalog owner hint');
      final localResourceId = json['localResourceId'];
      final variant = json['variant'];
      if (json.length != 2 ||
          localResourceId is! String ||
          !_isLocalResourceId(localResourceId) ||
          variant is! String ||
          !variants.contains(variant)) {
        return null;
      }
      return WebDavSyncCatalogOwnerReference(
        localResourceId: localResourceId,
        variant: variant,
      );
    } catch (_) {
      return null;
    }
  }
}

/// The v3 per-profile durable-library section.
///
/// Values intentionally remain generic JSON maps. Newer builds can carry
/// namespaces an older build does not understand without interpreting or
/// discarding them. Per the v3 wire ruling, playback-required raw URLs and
/// headers may occur inside these sealed values only; record keys and
/// diagnostics must never expose them.
final class WebDavSyncLibraryDocument {
  const WebDavSyncLibraryDocument({
    required this.circleProfileId,
    required this.records,
  });

  static const int schemaVersion = 1;
  static const int maxEncodedBytes = 64 * 1024 * 1024;
  static const int maxLeaves = 100000;

  final String circleProfileId;
  final Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>> records;

  Map<String, Object?> toJson() {
    if (records.length > maxLeaves) {
      throw const FormatException('Too many WebDAV sync library records');
    }
    return <String, Object?>{
      'version': schemaVersion,
      'circleProfileId': circleProfileId,
      'records': <String, Object?>{
        for (final entry in records.entries)
          entry.key: entry.value.toJson((value) => value),
      },
    };
  }

  String get semanticDigest => semanticDigestOf(toJson());

  factory WebDavSyncLibraryDocument.fromJson(Object? source) {
    if (utf8.encode(WebDavSyncCodec.canonicalJson(source)).length >
        maxEncodedBytes) {
      throw const FormatException('WebDAV sync library document too large');
    }
    final json = _object(source, 'library document');
    if (json.length != 3 ||
        json['version'] != schemaVersion ||
        !json.containsKey('circleProfileId') ||
        !json.containsKey('records')) {
      throw const FormatException('Unsupported WebDAV sync library schema');
    }
    final circleProfileId = _syncId(
      json['circleProfileId'],
      'library profile ID',
    );
    final rawRecords = _object(json['records'], 'library records');
    if (rawRecords.length > maxLeaves) {
      throw const FormatException('Too many WebDAV sync library records');
    }
    final records = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{};
    for (final entry in rawRecords.entries) {
      final key = _logicalKey(entry.key, 'library record key');
      final leafJson = _object(entry.value, 'library leaf');
      if (leafJson.length != 2 ||
          !leafJson.containsKey('stamp') ||
          !leafJson.containsKey('value')) {
        throw const FormatException('Invalid WebDAV sync library leaf');
      }
      final value = leafJson['value'];
      records[key] = WebDavSyncCircleLeaf<Map<String, Object?>>(
        stamp: WebDavSyncStamp.fromJson(leafJson['stamp']),
        value: value == null
            ? null
            : Map<String, Object?>.unmodifiable(
                _jsonObject(value, 'library record value'),
              ),
      );
    }
    return WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records:
          Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>>.unmodifiable(
            records,
          ),
    );
  }
}

/// Pure per-record LWW. Equal stamps use the canonical value digest so every
/// device chooses the same winner, including live-vs-null ties.
abstract final class WebDavSyncLibraryMerge {
  static WebDavSyncLibraryDocument merge({
    required String circleProfileId,
    required Iterable<WebDavSyncLibraryDocument> documents,
  }) {
    final winners = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{};
    for (final document in documents) {
      if (document.circleProfileId != circleProfileId) {
        throw const FormatException('WebDAV sync library profile mismatch');
      }
      for (final entry in document.records.entries) {
        final current = winners[entry.key];
        if (current == null || compareLeaves(entry.value, current) > 0) {
          winners[entry.key] = entry.value;
        }
      }
    }
    return WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records:
          Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>>.unmodifiable(
            winners,
          ),
    );
  }

  static int compareLeaves(
    WebDavSyncCircleLeaf<Map<String, Object?>> left,
    WebDavSyncCircleLeaf<Map<String, Object?>> right,
  ) {
    final time = left.stamp.normalizedTimeMs.compareTo(
      right.stamp.normalizedTimeMs,
    );
    if (time != 0) return time;
    final origin = left.stamp.originDeviceId.compareTo(
      right.stamp.originDeviceId,
    );
    if (origin != 0) return origin;
    return semanticDigestOf(
      left.value,
    ).compareTo(semanticDigestOf(right.value));
  }
}

bool _isLocalResourceId(String value) =>
    value.isNotEmpty &&
    utf8.encode(value).length <= 256 &&
    !value.contains('\u0000');

Map<String, dynamic> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid WebDAV sync $label');
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw FormatException('Invalid WebDAV sync $label');
  }
}

Map<String, Object?> _jsonObject(Object? value, String label) {
  final source = _object(value, label);
  return <String, Object?>{
    for (final entry in source.entries)
      _logicalKey(entry.key, '$label key'): _jsonValue(entry.value, depth: 0),
  };
}

Object? _jsonValue(Object? value, {required int depth}) {
  if (depth > 32) {
    throw const FormatException('WebDAV sync library value is too deep');
  }
  if (value == null || value is bool || value is String) return value;
  if (value is num && value.isFinite) return value;
  if (value is List) {
    if (value.length > WebDavSyncLibraryDocument.maxLeaves) {
      throw const FormatException('WebDAV sync library list is too large');
    }
    return <Object?>[
      for (final item in value) _jsonValue(item, depth: depth + 1),
    ];
  }
  if (value is Map) {
    final map = _object(value, 'library nested value');
    if (map.length > WebDavSyncLibraryDocument.maxLeaves) {
      throw const FormatException('WebDAV sync library map is too large');
    }
    return <String, Object?>{
      for (final entry in map.entries)
        _logicalKey(entry.key, 'library nested key'): _jsonValue(
          entry.value,
          depth: depth + 1,
        ),
    };
  }
  throw const FormatException('Unsupported WebDAV sync library JSON value');
}

String _syncId(Object? value, String label) {
  if (value is! String ||
      !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,95}$').hasMatch(value)) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return value;
}

String _logicalKey(Object? value, String label) {
  if (value is! String ||
      value.isEmpty ||
      utf8.encode(value).length > WebDavSyncLimits.maxLogicalKeyBytes ||
      value.contains('\u0000')) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return value;
}
