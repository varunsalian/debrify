import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'webdav_sync_codec.dart';

abstract final class WebDavSyncLimits {
  static const int maxPeers = 64;
  static const int maxManifestBytes = 256 * 1024;
  static const int maxHotDocumentBytes = 1024 * 1024;
  static const int maxTombstoneDocumentBytes = 512 * 1024;
  static const int maxGraphDocumentBytes = 256 * 1024 * 1024;
  static const int maxSectionsPerManifest = 512;
  static const int maxStoredSectionsPerDevice = 4096;
  static const int maxSectionListingBytes = 4 * 1024 * 1024;
  static const int maxRecordsPerHotDocument = 20000;
  static const int maxTombstonesPerProfile = 20000;
  static const int maxMapEntries = 4096;
  static const int maxLogicalKeyBytes = 1024;
  static const int maxTimestampMs = 253402300799999; // 9999-12-31 UTC.
}

final class WebDavSyncStamp {
  const WebDavSyncStamp({
    required this.normalizedTimeMs,
    required this.originDeviceId,
  });

  final int normalizedTimeMs;
  final String originDeviceId;

  Map<String, Object?> toJson() => <String, Object?>{
    'time': normalizedTimeMs,
    'origin': originDeviceId,
  };

  factory WebDavSyncStamp.fromJson(Object? source) {
    final json = _object(source, 'stamp');
    _onlyKeys(json, const <String>{'time', 'origin'});
    return WebDavSyncStamp(
      normalizedTimeMs: _timestamp(json['time'], 'stamp time'),
      originDeviceId: _syncId(json['origin'], 'stamp origin'),
    );
  }
}

final class WebDavSyncStampedValue {
  const WebDavSyncStampedValue({required this.stamp, required this.value});

  final WebDavSyncStamp stamp;
  final Object? value;

  Map<String, Object?> toJson() => <String, Object?>{
    'stamp': stamp.toJson(),
    'value': value,
  };

  factory WebDavSyncStampedValue.fromJson(Object? source) {
    final json = _object(source, 'stamped value');
    _onlyKeys(json, const <String>{'stamp', 'value'});
    final value = _jsonValue(json['value'], depth: 0);
    return WebDavSyncStampedValue(
      stamp: WebDavSyncStamp.fromJson(json['stamp']),
      value: value,
    );
  }
}

final class WebDavSyncOrderValue {
  const WebDavSyncOrderValue({required this.stamp, required this.keys});

  final WebDavSyncStamp stamp;
  final List<String> keys;

  Map<String, Object?> toJson() => <String, Object?>{
    'stamp': stamp.toJson(),
    'keys': keys,
  };

  factory WebDavSyncOrderValue.fromJson(Object? source) {
    final json = _object(source, 'order value');
    _onlyKeys(json, const <String>{'stamp', 'keys'});
    final raw = json['keys'];
    if (raw is! List ||
        raw.length > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException('Invalid WebDAV sync order');
    }
    final keys = <String>[];
    final seen = <String>{};
    for (final value in raw) {
      final key = _logicalKey(value, 'order key');
      if (!seen.add(key)) {
        throw const FormatException('Duplicate WebDAV sync order key');
      }
      keys.add(key);
    }
    return WebDavSyncOrderValue(
      stamp: WebDavSyncStamp.fromJson(json['stamp']),
      keys: List<String>.unmodifiable(keys),
    );
  }
}

final class WebDavSyncScalarPart {
  const WebDavSyncScalarPart({
    required this.semanticDigest,
    required this.entries,
  });

  final String semanticDigest;
  final Map<String, WebDavSyncStampedValue> entries;

  Map<String, Object> get values =>
      Map<String, Object>.unmodifiable(<String, Object>{
        for (final entry in entries.entries)
          entry.key: entry.value.value as Object,
      });

  Map<String, Object?> toJson() => <String, Object?>{
    'semanticDigest': semanticDigest,
    'values': <String, Object?>{
      for (final entry in entries.entries) entry.key: entry.value.toJson(),
    },
  };

  factory WebDavSyncScalarPart.fromJson(Object? source) {
    final json = _object(source, 'scalar part');
    _onlyKeys(json, const <String>{'semanticDigest', 'values'});
    final rawValues = _object(json['values'], 'scalar values');
    if (rawValues.length > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException('Too many WebDAV sync scalar values');
    }
    final values = <String, WebDavSyncStampedValue>{};
    for (final entry in rawValues.entries) {
      final key = _logicalKey(entry.key, 'scalar key');
      final stamped = WebDavSyncStampedValue.fromJson(entry.value);
      final value = _jsonPreferenceValue(stamped.value);
      if (value == null) {
        throw const FormatException('WebDAV sync scalar values cannot be null');
      }
      values[key] = WebDavSyncStampedValue(stamp: stamped.stamp, value: value);
    }
    final digest = _digest(json['semanticDigest'], 'scalar digest');
    final part = WebDavSyncScalarPart(
      semanticDigest: digest,
      entries: Map<String, WebDavSyncStampedValue>.unmodifiable(values),
    );
    if (semanticDigestOf(part.values) != digest) {
      throw const FormatException('WebDAV sync scalar digest mismatch');
    }
    return part;
  }

  factory WebDavSyncScalarPart._fromLegacyJson(Object? source) {
    final json = _object(source, 'legacy scalar part');
    _onlyKeys(json, const <String>{'stamp', 'semanticDigest', 'values'});
    final stamp = WebDavSyncStamp.fromJson(json['stamp']);
    final rawValues = _object(json['values'], 'legacy scalar values');
    if (rawValues.length > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException('Too many WebDAV sync scalar values');
    }
    final values = <String, WebDavSyncStampedValue>{};
    final semanticValues = <String, Object>{};
    for (final entry in rawValues.entries) {
      final key = _logicalKey(entry.key, 'scalar key');
      final value = _jsonPreferenceValue(entry.value);
      if (value == null) {
        throw const FormatException('WebDAV sync scalar values cannot be null');
      }
      values[key] = WebDavSyncStampedValue(stamp: stamp, value: value);
      semanticValues[key] = value;
    }
    final digest = _digest(json['semanticDigest'], 'scalar digest');
    if (semanticDigestOf(semanticValues) != digest) {
      throw const FormatException('WebDAV sync scalar digest mismatch');
    }
    return WebDavSyncScalarPart(
      semanticDigest: digest,
      entries: Map<String, WebDavSyncStampedValue>.unmodifiable(values),
    );
  }
}

final class WebDavSyncWatchPart {
  const WebDavSyncWatchPart({
    required this.stamp,
    required this.semanticDigest,
    required this.records,
    required this.orders,
  });

  final WebDavSyncStamp stamp;
  final String semanticDigest;
  final Map<String, WebDavSyncStampedValue> records;
  final Map<String, WebDavSyncOrderValue> orders;

  Map<String, Object?> get semanticPayload => <String, Object?>{
    'records': <String, Object?>{
      for (final entry in records.entries) entry.key: entry.value.toJson(),
    },
    'orders': <String, Object?>{
      for (final entry in orders.entries) entry.key: entry.value.toJson(),
    },
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'stamp': stamp.toJson(),
    'semanticDigest': semanticDigest,
    ...semanticPayload,
  };

  factory WebDavSyncWatchPart.fromJson(Object? source) {
    final json = _object(source, 'watch-state part');
    _onlyKeys(json, const <String>{
      'stamp',
      'semanticDigest',
      'records',
      'orders',
    });
    final rawRecords = _object(json['records'], 'watch records');
    final rawOrders = _object(json['orders'], 'watch orders');
    if (rawRecords.length + rawOrders.length >
        WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException('Too many WebDAV sync watch records');
    }
    final records = <String, WebDavSyncStampedValue>{};
    for (final entry in rawRecords.entries) {
      records[_logicalKey(entry.key, 'watch record key')] =
          WebDavSyncStampedValue.fromJson(entry.value);
    }
    final orders = <String, WebDavSyncOrderValue>{};
    for (final entry in rawOrders.entries) {
      orders[_logicalKey(entry.key, 'watch order key')] =
          WebDavSyncOrderValue.fromJson(entry.value);
    }
    final part = WebDavSyncWatchPart(
      stamp: WebDavSyncStamp.fromJson(json['stamp']),
      semanticDigest: _digest(json['semanticDigest'], 'watch digest'),
      records: Map<String, WebDavSyncStampedValue>.unmodifiable(records),
      orders: Map<String, WebDavSyncOrderValue>.unmodifiable(orders),
    );
    if (semanticDigestOf(part.semanticPayload) != part.semanticDigest) {
      throw const FormatException('WebDAV sync watch digest mismatch');
    }
    return part;
  }
}

final class WebDavSyncHotDocument {
  const WebDavSyncHotDocument({
    required this.circleProfileId,
    required this.scalars,
    required this.watchState,
  });

  static const int schemaVersion = 2;

  final String circleProfileId;
  final WebDavSyncScalarPart scalars;
  final WebDavSyncWatchPart watchState;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'circleProfileId': circleProfileId,
    'scalars': scalars.toJson(),
    'watchState': watchState.toJson(),
  };

  String get semanticDigest => semanticDigestOf(toJson());

  factory WebDavSyncHotDocument.fromJson(Object? source) {
    final json = _object(source, 'hot document');
    _onlyKeys(json, const <String>{
      'version',
      'circleProfileId',
      'scalars',
      'watchState',
    });
    final version = json['version'];
    if (version != 1 && version != schemaVersion) {
      throw const FormatException('Unsupported WebDAV sync hot schema');
    }
    return WebDavSyncHotDocument(
      circleProfileId: _syncId(json['circleProfileId'], 'profile ID'),
      scalars: version == 1
          ? WebDavSyncScalarPart._fromLegacyJson(json['scalars'])
          : WebDavSyncScalarPart.fromJson(json['scalars']),
      watchState: WebDavSyncWatchPart.fromJson(json['watchState']),
    );
  }
}

final class WebDavSyncTombstone {
  const WebDavSyncTombstone({
    required this.key,
    required this.stamp,
    this.firstPublishedAtMs,
    this.rawLocalTime = false,
  });

  final String key;
  final WebDavSyncStamp stamp;
  final int? firstPublishedAtMs;

  /// Local-only marker. It is never serialized to the authenticated wire doc.
  final bool rawLocalTime;

  bool get pendingPublication => firstPublishedAtMs == null;

  WebDavSyncTombstone copyWith({
    WebDavSyncStamp? stamp,
    int? firstPublishedAtMs,
    bool? rawLocalTime,
  }) => WebDavSyncTombstone(
    key: key,
    stamp: stamp ?? this.stamp,
    firstPublishedAtMs: firstPublishedAtMs ?? this.firstPublishedAtMs,
    rawLocalTime: rawLocalTime ?? this.rawLocalTime,
  );

  WebDavSyncTombstone copyWithKey(String replacement) => WebDavSyncTombstone(
    key: replacement,
    stamp: stamp,
    firstPublishedAtMs: firstPublishedAtMs,
    rawLocalTime: rawLocalTime,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'stamp': stamp.toJson(),
    'firstPublishedAt': firstPublishedAtMs,
  };

  factory WebDavSyncTombstone.fromJson(Object? source) {
    final json = _object(source, 'tombstone');
    _onlyKeys(json, const <String>{'key', 'stamp', 'firstPublishedAt'});
    final firstPublished = json['firstPublishedAt'];
    return WebDavSyncTombstone(
      key: _logicalKey(json['key'], 'tombstone key'),
      stamp: WebDavSyncStamp.fromJson(json['stamp']),
      firstPublishedAtMs: firstPublished == null
          ? null
          : _timestamp(firstPublished, 'first publication time'),
    );
  }
}

final class WebDavSyncTombstoneDocument {
  const WebDavSyncTombstoneDocument({
    required this.circleProfileId,
    required this.items,
  });

  static const int schemaVersion = 1;

  final String circleProfileId;
  final Map<String, WebDavSyncTombstone> items;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'circleProfileId': circleProfileId,
    'items': <String, Object?>{
      for (final entry in items.entries) entry.key: entry.value.toJson(),
    },
  };

  String get semanticDigest => semanticDigestOf(toJson());

  factory WebDavSyncTombstoneDocument.fromJson(Object? source) {
    final json = _object(source, 'tombstone document');
    _onlyKeys(json, const <String>{'version', 'circleProfileId', 'items'});
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported WebDAV sync tombstone schema');
    }
    final rawItems = _object(json['items'], 'tombstone items');
    if (rawItems.length > WebDavSyncLimits.maxTombstonesPerProfile) {
      throw const FormatException('Too many WebDAV sync tombstones');
    }
    final items = <String, WebDavSyncTombstone>{};
    for (final entry in rawItems.entries) {
      final key = _logicalKey(entry.key, 'tombstone map key');
      final item = WebDavSyncTombstone.fromJson(entry.value);
      if (item.key != key ||
          item.rawLocalTime ||
          item.firstPublishedAtMs == null ||
          item.firstPublishedAtMs! < item.stamp.normalizedTimeMs) {
        throw const FormatException('WebDAV sync tombstone key mismatch');
      }
      items[key] = item;
    }
    return WebDavSyncTombstoneDocument(
      circleProfileId: _syncId(json['circleProfileId'], 'profile ID'),
      items: Map<String, WebDavSyncTombstone>.unmodifiable(items),
    );
  }
}

final class WebDavSyncSectionReference {
  const WebDavSyncSectionReference({
    required this.name,
    required this.contentHash,
    required this.semanticDigest,
    required this.updatedAtMs,
    required this.schemaVersion,
    required this.size,
  });

  final String name;
  final String contentHash;
  final String semanticDigest;
  final int updatedAtMs;
  final int schemaVersion;
  final int size;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'contentHash': contentHash,
    'semanticDigest': semanticDigest,
    'updatedAt': updatedAtMs,
    'schemaVersion': schemaVersion,
    'size': size,
  };

  factory WebDavSyncSectionReference.fromJson(Object? source) {
    final json = _object(source, 'section reference');
    _onlyKeys(json, const <String>{
      'name',
      'contentHash',
      'semanticDigest',
      'updatedAt',
      'schemaVersion',
      'size',
    });
    final name = _logicalKey(json['name'], 'section name');
    final schema = json['schemaVersion'];
    final size = json['size'];
    if (schema is! int || schema < 1 || schema > 0x7fffffff) {
      throw const FormatException('Invalid WebDAV sync section schema');
    }
    if (size is! int || size < 1 || size > 256 * 1024 * 1024) {
      throw const FormatException('Invalid WebDAV sync section size');
    }
    return WebDavSyncSectionReference(
      name: name,
      contentHash: _digest(json['contentHash'], 'content hash'),
      semanticDigest: _digest(json['semanticDigest'], 'semantic digest'),
      updatedAtMs: _timestamp(json['updatedAt'], 'section timestamp'),
      schemaVersion: schema,
      size: size,
    );
  }
}

final class WebDavSyncManifest {
  const WebDavSyncManifest({
    required this.circleId,
    required this.deviceId,
    required this.updatedAtMs,
    required this.clockOffsetMs,
    required this.graphSchemaClaim,
    required this.profileMap,
    required this.resourceMap,
    required this.sections,
  });

  static const int schemaVersion = 1;

  final String circleId;
  final String deviceId;
  final int updatedAtMs;
  final int clockOffsetMs;
  final int graphSchemaClaim;

  /// Wire graph backup IDs -> stable circle IDs. Neither side is a local ID.
  final Map<String, String> profileMap;
  final Map<String, String> resourceMap;
  final List<WebDavSyncSectionReference> sections;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': schemaVersion,
    'circleId': circleId,
    'deviceId': deviceId,
    'updatedAt': updatedAtMs,
    'clockOffsetMs': clockOffsetMs,
    'graphSchemaClaim': graphSchemaClaim,
    'profileMap': profileMap,
    'resourceMap': resourceMap,
    'sections': sections.map((entry) => entry.toJson()).toList(),
  };

  WebDavSyncSectionReference? section(String name) =>
      sections.where((entry) => entry.name == name).firstOrNull;

  factory WebDavSyncManifest.fromJson(Object? source) {
    final json = _object(source, 'manifest');
    _onlyKeys(json, const <String>{
      'version',
      'circleId',
      'deviceId',
      'updatedAt',
      'clockOffsetMs',
      'graphSchemaClaim',
      'profileMap',
      'resourceMap',
      'sections',
    });
    if (json['version'] != schemaVersion) {
      throw const FormatException('Unsupported WebDAV sync manifest schema');
    }
    final offset = json['clockOffsetMs'];
    final graphSchema = json['graphSchemaClaim'];
    if (offset is! int || offset.abs() > WebDavSyncLimits.maxTimestampMs) {
      throw const FormatException('Invalid WebDAV sync clock offset');
    }
    if (graphSchema is! int || graphSchema < 1 || graphSchema > 0x7fffffff) {
      throw const FormatException('Invalid WebDAV sync graph schema claim');
    }
    final profileMap = _idMap(json['profileMap'], 'profile map');
    final resourceMap = _idMap(json['resourceMap'], 'resource map');
    final rawSections = json['sections'];
    if (rawSections is! List ||
        rawSections.isEmpty ||
        rawSections.length > WebDavSyncLimits.maxSectionsPerManifest) {
      throw const FormatException('Invalid WebDAV sync manifest sections');
    }
    final sections = <WebDavSyncSectionReference>[];
    final names = <String>{};
    final updatedAt = _timestamp(json['updatedAt'], 'manifest timestamp');
    for (final raw in rawSections) {
      final section = WebDavSyncSectionReference.fromJson(raw);
      if (!names.add(section.name)) {
        throw const FormatException('Duplicate WebDAV sync manifest section');
      }
      if (section.updatedAtMs > updatedAt) {
        throw const FormatException(
          'WebDAV sync section is newer than its manifest',
        );
      }
      sections.add(section);
    }
    final circleId = _syncId(json['circleId'], 'circle ID');
    final deviceId = _syncId(json['deviceId'], 'device ID');
    return WebDavSyncManifest(
      circleId: circleId,
      deviceId: deviceId,
      updatedAtMs: updatedAt,
      clockOffsetMs: offset,
      graphSchemaClaim: graphSchema,
      profileMap: Map<String, String>.unmodifiable(profileMap),
      resourceMap: Map<String, String>.unmodifiable(resourceMap),
      sections: List<WebDavSyncSectionReference>.unmodifiable(sections),
    );
  }
}

String semanticDigestOf(Object? value) =>
    crypto.sha256.convert(WebDavSyncCodec.canonicalJsonBytes(value)).toString();

String contentHashOf(List<int> bytes) =>
    crypto.sha256.convert(bytes).toString();

Map<String, dynamic> _object(Object? value, String label) {
  if (value is! Map) throw FormatException('Invalid WebDAV sync $label');
  try {
    return Map<String, dynamic>.from(value);
  } on TypeError {
    throw FormatException('Invalid WebDAV sync $label');
  }
}

void _onlyKeys(Map<String, dynamic> value, Set<String> expected) {
  if (value.length != expected.length ||
      value.keys.any((key) => !expected.contains(key))) {
    throw const FormatException('Unexpected WebDAV sync document fields');
  }
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

String _digest(Object? value, String label) {
  if (value is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(value)) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return value;
}

int _timestamp(Object? value, String label) {
  if (value is! int || value < 0 || value > WebDavSyncLimits.maxTimestampMs) {
    throw FormatException('Invalid WebDAV sync $label');
  }
  return value;
}

Object? _jsonValue(Object? value, {required int depth}) {
  if (depth > 32) {
    throw const FormatException('WebDAV sync value nesting is too deep');
  }
  if (value == null || value is bool || value is String) return value;
  if (value is num && value.isFinite) return value;
  if (value is List) {
    if (value.length > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException('WebDAV sync list exceeds its limit');
    }
    return <Object?>[
      for (final item in value) _jsonValue(item, depth: depth + 1),
    ];
  }
  if (value is Map) {
    final source = _object(value, 'nested value');
    if (source.length > WebDavSyncLimits.maxRecordsPerHotDocument) {
      throw const FormatException('WebDAV sync map exceeds its limit');
    }
    return <String, Object?>{
      for (final entry in source.entries)
        _logicalKey(entry.key, 'nested key'): _jsonValue(
          entry.value,
          depth: depth + 1,
        ),
    };
  }
  throw const FormatException('Unsupported WebDAV sync JSON value');
}

Object? _jsonPreferenceValue(Object? value) {
  if (value == null || value is bool || value is String) return value;
  if (value is int || value is double && value.isFinite) return value;
  if (value is List && value.every((entry) => entry is String)) {
    return List<String>.unmodifiable(value.cast<String>());
  }
  throw const FormatException('Unsupported WebDAV sync preference value');
}

Map<String, String> _idMap(Object? source, String label) {
  final raw = _object(source, label);
  if (raw.length > WebDavSyncLimits.maxMapEntries) {
    throw FormatException('WebDAV sync $label exceeds its limit');
  }
  return <String, String>{
    for (final entry in raw.entries)
      _syncId(entry.key, '$label key'): _syncId(entry.value, '$label value'),
  };
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
