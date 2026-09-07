import 'dart:convert';
import 'dart:isolate';
import 'package:collection/collection.dart';

import 'webdav_sync_hot_models.dart';

/// Collections have their own bounded sections. Legacy clients keep reading the
/// small hot section, and never parse/rewrite the richer collection payloads.
typedef PreparedCollectionSection = ({
  WebDavSyncHotDocument document,
  String digest,
});

final class WebDavSyncCollectionSections {
  final _cache =
      <
        String,
        ({
          WebDavSyncHotDocument source,
          Map<String, PreparedCollectionSection> parts,
        })
      >{};

  Future<Map<String, PreparedCollectionSection>> prepare(
    String key,
    WebDavSyncHotDocument source,
  ) async {
    final cached = _cache.remove(key);
    Map<String, Object?> projection(WebDavSyncHotDocument doc) => {
      'records': {
        for (final e in doc.watchState.records.entries)
          if (isCollectionRecord(e.key)) e.key: e.value.toJson(),
      },
      'orders': {
        for (final e in doc.watchState.orders.entries)
          if (isCollectionOrder(e.key)) e.key: e.value.toJson(),
      },
    };
    if (cached != null &&
        const DeepCollectionEquality().equals(
          projection(cached.source),
          projection(source),
        )) {
      _cache[key] = cached;
      final hot = await _prepareInWorker(source, false);
      return {...hot, ...cached.parts};
    }
    final parts = await _prepareInWorker(source, true);
    if (_cache.length >= 4) _cache.remove(_cache.keys.first);
    _cache[key] = (
      source: source,
      parts: {
        for (final e in parts.entries)
          if (e.key.startsWith(prefix)) e.key: e.value,
      },
    );
    return parts;
  }

  static Future<Map<String, PreparedCollectionSection>> _prepareInWorker(
    WebDavSyncHotDocument source,
    bool collections,
  ) => Isolate.run(
    () => {
      for (final e in split(source, includeCollections: collections).entries)
        e.key: (document: e.value, digest: e.value.semanticDigest),
    },
  );

  static const prefix = 'collections-v2/';
  static const maxBytes = 32 * 1024 * 1024;
  static const _targetBytes = 8 * 1024 * 1024;

  static bool isCollectionRecord(String key) =>
      key.startsWith('homecollection/');
  static bool isCollectionOrder(String key) => key == 'homecollections/items';

  static Map<String, WebDavSyncHotDocument> split(
    WebDavSyncHotDocument source, {
    bool includeCollections = true,
  }) {
    final result = <String, WebDavSyncHotDocument>{};
    WebDavSyncHotDocument part(
      Map<String, WebDavSyncStampedValue> records,
      Map<String, WebDavSyncOrderValue> orders, {
      bool scalars = false,
    }) {
      var stamp = const WebDavSyncStamp(
        normalizedTimeMs: 0,
        originDeviceId: 'collections',
      );
      for (final candidate in [
        ...records.values.map((v) => v.stamp),
        ...orders.values.map((v) => v.stamp),
      ]) {
        if (candidate.normalizedTimeMs > stamp.normalizedTimeMs ||
            (candidate.normalizedTimeMs == stamp.normalizedTimeMs &&
                candidate.originDeviceId.compareTo(stamp.originDeviceId) > 0)) {
          stamp = candidate;
        }
      }
      final watch = WebDavSyncWatchPart(
        stamp: scalars ? source.watchState.stamp : stamp,
        semanticDigest: semanticDigestOf({
          'records': {for (final e in records.entries) e.key: e.value.toJson()},
          'orders': {for (final e in orders.entries) e.key: e.value.toJson()},
        }),
        records: Map.unmodifiable(records),
        orders: Map.unmodifiable(orders),
      );
      return WebDavSyncHotDocument(
        circleProfileId: source.circleProfileId,
        scalars: scalars
            ? source.scalars
            : WebDavSyncScalarPart(
                semanticDigest: semanticDigestOf(<String, Object>{}),
                entries: const {},
              ),
        watchState: watch,
      );
    }

    result['hot/${source.circleProfileId}'] = part(
      {
        for (final e in source.watchState.records.entries)
          if (!isCollectionRecord(e.key)) e.key: e.value,
      },
      {
        for (final e in source.watchState.orders.entries)
          if (!isCollectionOrder(e.key)) e.key: e.value,
      },
      scalars: true,
    );

    if (!includeCollections) return result;
    if (!source.watchState.records.keys.any(isCollectionRecord) &&
        !source.watchState.orders.keys.any(isCollectionOrder)) {
      return result;
    }
    var batch = <String, WebDavSyncStampedValue>{};
    var orders = <String, WebDavSyncOrderValue>{
      for (final e in source.watchState.orders.entries)
        if (isCollectionOrder(e.key)) e.key: e.value,
    };
    var size = 0;
    var index = 0;
    void flush() {
      result['$prefix${source.circleProfileId}/${index++}'] = part(
        batch,
        orders,
      );
      batch = {};
      orders = {};
      size = 0;
    }

    final keys =
        source.watchState.records.keys.where(isCollectionRecord).toList()
          ..sort();
    for (final key in keys) {
      final value = source.watchState.records[key]!;
      final bytes = utf8.encode(jsonEncode({key: value.toJson()})).length;
      if (bytes > maxBytes - 1024 * 1024) {
        throw const FormatException(
          'A collection exceeds its sync section limit.',
        );
      }
      if (size + bytes > _targetBytes && batch.isNotEmpty) flush();
      batch[key] = value;
      size += bytes;
    }
    // Publish an empty first shard too, so deletion of the last collection has
    // an explicit current snapshot and obsolete shard references can be removed.
    if (batch.isNotEmpty || index == 0) flush();
    return result;
  }

  static void validate(WebDavSyncHotDocument document) {
    if (document.scalars.entries.isNotEmpty ||
        document.watchState.records.keys.any((k) => !isCollectionRecord(k)) ||
        document.watchState.orders.keys.any((k) => !isCollectionOrder(k))) {
      throw const FormatException('Invalid collection sync section.');
    }
  }
}
