import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import 'webdav_sync_codec.dart';
import 'webdav_sync_circle_models.dart';
import 'webdav_sync_hot_models.dart';

/// Why a durable library row is being changed.
///
/// Only [user] mutations create local stamps. Ambient-library writers also
/// schedule recurring sync; Debrify TV writers instead set their per-profile
/// manual-sync marker. Sync materialization has its own exact-stamp writer;
/// the remaining origins deliberately leave the sidecar untouched.
enum WebDavSyncMutationOrigin {
  user,
  syncApply,
  migration,
  maintenance,
  rollback,
}

abstract final class WebDavSyncLibraryKinds {
  static const String tvChannels = 'tv_channels';
  static const String tvPoolGeneration = 'tv_pool_generation';
  static const String hiddenGroups = 'hidden_groups';
  static const String categoryManualOrders = 'category_manual_orders';
  static const String iptvCategoryChannelOrders =
      'iptv_category_channel_orders';
  static const String iptvLists = 'iptv_lists';
  static const String iptvListChannels = 'iptv_list_channels';
  static const String iptvWatchHistory = 'iptv_watch_history';
  static const String videoResume = 'video_resume';

  static bool isTvKind(String kind) =>
      kind == tvChannels || kind == tvPoolGeneration;

  static bool isTvWireKey(String key) => key.startsWith('tv/');
}

final class WebDavSyncTvChannelTarget {
  const WebDavSyncTvChannelTarget({
    required this.channelId,
    required this.name,
    required this.avoidNsfw,
    required this.desiredChannelNumber,
    required this.createdAtMs,
    required this.keywords,
    required this.leaf,
  });

  final String channelId;
  final String name;
  final bool avoidNsfw;
  final int desiredChannelNumber;
  final int createdAtMs;
  final List<String> keywords;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

final class WebDavSyncTvPoolGenerationTarget {
  const WebDavSyncTvPoolGenerationTarget({
    required this.channelId,
    required this.generationId,
    required this.leaf,
  });

  final String channelId;
  final String generationId;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

final class WebDavSyncTvPoolTarget {
  const WebDavSyncTvPoolTarget({
    required this.channelId,
    required this.infohash,
    required this.generationId,
    required this.name,
    required this.sizeBytes,
    required this.keywords,
    required this.rank,
    required this.leaf,
  });

  final String channelId;
  final String infohash;
  final String generationId;
  final String name;
  final int sizeBytes;
  final List<String> keywords;
  final int rank;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

final class WebDavSyncRecordState {
  const WebDavSyncRecordState({
    required this.kind,
    required this.ownerKey,
    required this.itemKey,
    required this.stamp,
    required this.deleted,
    this.aux,
    this.value,
  });

  final String kind;
  final String ownerKey;
  final String itemKey;
  final WebDavSyncStamp stamp;
  final bool deleted;
  final String? aux;

  /// Physical value captured in the same transaction as the sidecar. It is
  /// local-only and is never used for a deleted leaf. Maintenance-pruned
  /// history states deliberately have no value, which makes them an omission
  /// (the prior wire winner is preserved) rather than an accidental delete.
  final Map<String, Object?>? value;
}

final class WebDavSyncDatabaseStateSnapshot {
  const WebDavSyncDatabaseStateSnapshot({
    required this.mutationRevision,
    this.records = const <WebDavSyncRecordState>[],
    this.tvPools = const <WebDavSyncTvPoolSnapshot>[],
    this.tvPendingRevision = 0,
  });

  final int mutationRevision;
  final List<WebDavSyncRecordState> records;
  final List<WebDavSyncTvPoolSnapshot> tvPools;
  final int tvPendingRevision;
}

final class WebDavSyncTvSyncMetadata {
  const WebDavSyncTvSyncMetadata({
    required this.changesPending,
    required this.pendingRevision,
    this.lastSyncedMs,
  });

  final bool changesPending;
  final int pendingRevision;
  final int? lastSyncedMs;
}

final class WebDavSyncTvPoolSnapshot {
  const WebDavSyncTvPoolSnapshot({
    required this.channelId,
    required this.infohash,
    required this.generationId,
    required this.name,
    required this.sizeBytes,
    required this.keywords,
    required this.rank,
    required this.stamp,
  });

  final String channelId;
  final String infohash;
  final String generationId;
  final String name;
  final int sizeBytes;
  final List<String> keywords;
  final int rank;
  final WebDavSyncStamp stamp;
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

final class WebDavSyncCategoryOrderTarget {
  const WebDavSyncCategoryOrderTarget({
    required this.catalogKey,
    required this.groups,
    required this.leaf,
  });

  final String catalogKey;
  final List<String> groups;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

final class WebDavSyncIptvOrderItem {
  const WebDavSyncIptvOrderItem({
    required this.url,
    required this.name,
    required this.occurrence,
  });

  final String url;
  final String name;
  final int occurrence;
}

final class WebDavSyncIptvOrderTarget {
  const WebDavSyncIptvOrderTarget({
    required this.sourceId,
    required this.group,
    required this.items,
    required this.leaf,
  });

  final String sourceId;
  final String group;
  final List<WebDavSyncIptvOrderItem> items;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

final class WebDavSyncIptvListTarget {
  const WebDavSyncIptvListTarget({
    required this.listId,
    required this.name,
    required this.desiredPosition,
    required this.createdAtMs,
    required this.leaf,
  });

  final String listId;
  final String name;
  final int desiredPosition;
  final int createdAtMs;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

final class WebDavSyncIptvListChannelTarget {
  const WebDavSyncIptvListChannelTarget({
    required this.listId,
    required this.url,
    required this.localSourceId,
    required this.leaf,
  });

  final String listId;
  final String url;
  final String localSourceId;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

final class WebDavSyncIptvWatchTarget {
  const WebDavSyncIptvWatchTarget({
    required this.sourceId,
    required this.url,
    required this.leaf,
  });

  final String sourceId;
  final String url;
  final WebDavSyncCircleLeaf<Map<String, Object?>> leaf;
}

final class WebDavSyncVideoResumeTarget {
  const WebDavSyncVideoResumeTarget({
    required this.sourceId,
    required this.resumeKey,
    required this.leaf,
  });

  /// Null is the generic-video `_` wire bucket.
  final String? sourceId;
  final String resumeKey;
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
  }) : _semanticDigest = null;

  const WebDavSyncLibraryDocument._withSemanticDigest({
    required this.circleProfileId,
    required this.records,
    required String semanticDigest,
  }) : _semanticDigest = semanticDigest;

  static const int schemaVersion = 1;
  static const int maxEncodedBytes = 64 * 1024 * 1024;
  static const int maxLeaves = 100000;
  // Live activity limit; retained deletions share the larger wire budget.
  static const int maxAmbientLeaves = 20000;

  final String circleProfileId;
  final Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>> records;
  final String? _semanticDigest;

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

  String get semanticDigest => _semanticDigest ?? semanticDigestOf(toJson());

  WebDavSyncLibraryDocument withComputedSemanticDigest() {
    if (_semanticDigest != null) return this;
    return WebDavSyncLibraryDocument._withSemanticDigest(
      circleProfileId: circleProfileId,
      records: records,
      semanticDigest: semanticDigestOf(toJson()),
    );
  }

  WebDavSyncLibraryDocument withoutTvRecords() {
    if (!records.keys.any(WebDavSyncLibraryKinds.isTvWireKey)) return this;
    return WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records:
          Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>>.unmodifiable(
            <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
              for (final entry in records.entries)
                if (!WebDavSyncLibraryKinds.isTvWireKey(entry.key))
                  entry.key: entry.value,
            },
          ),
    );
  }

  WebDavSyncLibraryDocument onlyTvRecords() {
    if (records.keys.every(WebDavSyncLibraryKinds.isTvWireKey)) return this;
    return WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records:
          Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>>.unmodifiable(
            <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{
              for (final entry in records.entries)
                if (WebDavSyncLibraryKinds.isTvWireKey(entry.key))
                  entry.key: entry.value,
            },
          ),
    );
  }

  factory WebDavSyncLibraryDocument.fromJson(Object? source) {
    final canonicalBytes = WebDavSyncCodec.canonicalJsonBytes(source);
    if (canonicalBytes.length > maxEncodedBytes) {
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
    return WebDavSyncLibraryDocument._withSemanticDigest(
      circleProfileId: circleProfileId,
      records:
          Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>>.unmodifiable(
            records,
          ),
      semanticDigest: crypto.sha256.convert(canonicalBytes).toString(),
    );
  }
}

Object? encodeWebDavSyncLibraryDocument(Object? source) {
  if (source is! WebDavSyncLibraryDocument) {
    throw const FormatException('Invalid WebDAV sync library document');
  }
  return source.toJson();
}

Object? decodeWebDavSyncLibraryDocument(Object? source) =>
    WebDavSyncLibraryDocument.fromJson(source);

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
    // Winner values stay byte-for-byte attached to their stamps. SQLite-only
    // number/position collision repair belongs to the materializer.
    _pruneSuppressedTvChildren(winners);
    _pruneSuppressedIptvListChildren(winners);
    return WebDavSyncLibraryDocument(
      circleProfileId: circleProfileId,
      records:
          Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>>.unmodifiable(
            winners,
          ),
    );
  }

  /// A pool generation is the one authoritative membership boundary. Leaves
  /// from a superseded generation are deliberately pruned from the publisher's
  /// next full library document, so repeated rescrapes cannot grow it without
  /// bound. The outer 64 MiB/100,000-leaf checks remain the fail-closed backstop.
  /// A winning channel tombstone similarly suppresses every child record.
  static void _pruneSuppressedTvChildren(
    Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>> winners,
  ) {
    final channels = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{};
    final generations = <String, WebDavSyncCircleLeaf<Map<String, Object?>>>{};
    for (final entry in winners.entries) {
      final parts = entry.key.split('/');
      if (parts.length == 3 && parts[0] == 'tv' && parts[1] == 'ch') {
        channels[parts[2]] = entry.value;
      } else if (parts.length == 3 &&
          parts[0] == 'tv' &&
          parts[1] == 'pool-gen') {
        generations[parts[2]] = entry.value;
      }
    }
    winners.removeWhere((key, leaf) {
      final parts = key.split('/');
      final isGeneration =
          parts.length == 3 && parts[0] == 'tv' && parts[1] == 'pool-gen';
      final isPool =
          parts.length == 4 && parts[0] == 'tv' && parts[1] == 'pool';
      if (!isGeneration && !isPool) return false;
      final channel = channels[parts[2]];
      if (channel?.value == null && channel != null) return true;
      if (!isPool) return false;
      final generation = generations[parts[2]]?.value?['generationId'];
      return generation is String && leaf.value?['generationId'] != generation;
    });
  }

  /// A custom-list tombstone is the sole membership boundary for deletion.
  /// Individual member tombstones would make list removal proportional to its
  /// size, so every child of a dead list is removed by this normalizer.
  static void _pruneSuppressedIptvListChildren(
    Map<String, WebDavSyncCircleLeaf<Map<String, Object?>>> winners,
  ) {
    final deadLists = <String>{};
    final forbiddenBuiltinMetadata = <String>[];
    for (final entry in winners.entries) {
      final parts = entry.key.split('/');
      if (parts.length == 3 && parts[0] == 'iptv' && parts[1] == 'list') {
        if (_tryDecodeBase64Part(parts[2]) == 'favorites') {
          forbiddenBuiltinMetadata.add(entry.key);
          continue;
        }
        if (entry.value.value != null) continue;
        deadLists.add(parts[2]);
      }
    }
    for (final key in forbiddenBuiltinMetadata) {
      winners.remove(key);
    }
    if (deadLists.isEmpty) return;
    winners.removeWhere((key, _) {
      final parts = key.split('/');
      return parts.length == 4 &&
          parts[0] == 'iptv' &&
          parts[1] == 'list-ch' &&
          deadLists.contains(parts[2]);
    });
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

String? _tryDecodeBase64Part(String source) {
  final padding = '=' * ((4 - source.length % 4) % 4);
  try {
    final decoded = utf8.decode(base64Url.decode('$source$padding'));
    return decoded.isNotEmpty &&
            base64UrlEncode(utf8.encode(decoded)).replaceAll('=', '') == source
        ? decoded
        : null;
  } on FormatException {
    return null;
  }
}

/// Strictly increasing wall-clock stamps per clock source.
///
/// An NTP step backwards (or a frozen clock) can otherwise mint two different
/// user mutations carrying an identical (time, origin) stamp; per-key LWW then
/// tie-breaks by value digest and may pick related leaves — a pool generation
/// and its rows — from different writes. Swapping the clock function (tests do)
/// starts a new epoch so fixed-clock fixtures keep their exact values.
final class WebDavSyncMonotonicStamp {
  DateTime Function()? _clock;
  int _lastMs = 0;

  int next(DateTime Function() clock) {
    final now = clock().millisecondsSinceEpoch;
    if (!identical(clock, _clock)) {
      _clock = clock;
      _lastMs = now;
      return now;
    }
    _lastMs = now > _lastMs ? now : _lastMs + 1;
    return _lastMs;
  }
}
