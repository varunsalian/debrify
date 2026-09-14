import 'dart:convert';
import 'dart:isolate';

import '../../utils/canonical_json.dart';
import 'webdav_sync_hot_models.dart';
import '../transfer/transfer_io.dart';

/// Collections have their own bounded sections. Legacy clients keep reading the
/// small hot section, and never parse/rewrite the richer collection payloads.
typedef PreparedCollectionSection = ({
  WebDavSyncHotDocument document,
  String digest,
});

final class WebDavSyncCollectionPlan {
  const WebDavSyncCollectionPlan(this.targetBytes, this.sectionCounts);
  final int targetBytes;
  // Upper bounds in the fast path; exact greedy shard counts after sizing.
  final Map<String, int> sectionCounts;
}

final class WebDavSyncCollectionSections {
  Future<Map<String, PreparedCollectionSection>> prepare(
    String key,
    WebDavSyncHotDocument source, {
    int? targetBytes,
  }) => _prepareInWorker(source, true, targetBytes);

  static Future<Map<String, PreparedCollectionSection>> _prepareInWorker(
    WebDavSyncHotDocument source,
    bool collections,
    int? targetBytes,
  ) => TransferIo.largeWorker.synchronized(
    () => Isolate.run(
      () => {
        for (final e in split(
          source,
          includeCollections: collections,
          targetBytes: targetBytes,
        ).entries)
          e.key: (document: e.value, digest: e.value.semanticDigest),
      },
    ),
  );

  static const prefix = 'collections-v2/';
  static const maxBytes = 32 * 1024 * 1024;
  static const _targetBytes = 512 * 1024;
  static const _maxRecordBytes = maxBytes - 1024 * 1024;

  /// Reserve current and future non-collection sections before sharing the
  /// remaining manifest slots between profiles. Unknown retained sections and
  /// collection sections belonging to profiles outside this cycle also count.
  static int reservedSectionCount(
    Iterable<String> profileIds, {
    Iterable<WebDavSyncSectionReference> retained = const [],
  }) {
    final profiles = profileIds.toSet();
    final replacedPrefixes = profiles.map((id) => '$prefix$id/').toList();
    return {
      'bootstrap',
      'profiles',
      'resources',
      for (final id in profiles) ...[
        'hot/$id',
        'tombstones/$id',
        'library/$id',
        'tv-library/$id',
      ],
      for (final section in retained)
        if (section.name != 'graph' &&
            !replacedPrefixes.any(section.name.startsWith))
          section.name,
    }.length;
  }

  /// Ordinary inventories need no byte scan. Only when one shard per record
  /// could exceed the shared budget do we measure, one profile worker at a time.
  static Future<WebDavSyncCollectionPlan> plan(
    Iterable<WebDavSyncHotDocument> sources, {
    required int reservedSections,
    // These profiles keep their published partition unless fitting the shared
    // budget requires fewer shards. Avoid scanning large unchanged inventories.
    Map<String, int> unchangedSectionCounts = const {},
  }) async {
    final documents = sources.toList();
    final counts = {
      for (final source in documents)
        source.circleProfileId:
            unchangedSectionCounts[source.circleProfileId] ??
            _recordCount(source),
    };
    final available =
        WebDavSyncLimits.maxSectionsPerManifest - reservedSections;
    if (counts.values.fold(0, (a, b) => a + b) <= available) {
      return WebDavSyncCollectionPlan(_targetBytes, counts);
    }
    final sizes = <String, List<int>>{};
    for (final source in documents) {
      sizes[source.circleProfileId] = await _measureInWorker(source);
    }
    return _fit(sizes, available);
  }

  static Future<List<int>> _measureInWorker(WebDavSyncHotDocument source) =>
      TransferIo.largeWorker.synchronized(
        () => Isolate.run(() => _sizes(source)),
      );

  static int _recordCount(WebDavSyncHotDocument source) {
    final records = source.watchState.records.keys
        .where(isCollectionRecord)
        .length;
    return records == 0 && source.watchState.orders.keys.any(isCollectionOrder)
        ? 1
        : records;
  }

  static List<int> _sizes(WebDavSyncHotDocument source) {
    final keys =
        source.watchState.records.keys.where(isCollectionRecord).toList()
          ..sort();
    if (keys.isEmpty) return _recordCount(source) == 0 ? [] : [0];
    return [
      for (final key in keys)
        _recordBytes(key, source.watchState.records[key]!),
    ];
  }

  static int _recordBytes(String key, WebDavSyncStampedValue value) {
    var bytes = 0;
    for (final fragment in canonicalJsonFragments({key: value.toJson()})) {
      bytes += utf8.encode(fragment).length;
      if (bytes > _maxRecordBytes) {
        throw const FormatException(
          'A collection exceeds its sync section limit.',
        );
      }
    }
    return bytes;
  }

  static WebDavSyncCollectionPlan _fit(
    Map<String, List<int>> sizes,
    int available,
  ) {
    var target = _targetBytes;
    while (true) {
      final counts = <String, int>{};
      for (final entry in sizes.entries) {
        var count = 0;
        var size = 0;
        for (final bytes in entry.value) {
          if (count == 0 || size + bytes > target) {
            count++;
            size = 0;
          }
          size += bytes;
        }
        counts[entry.key] = count;
      }
      if (counts.values.fold(0, (a, b) => a + b) <= available) {
        return WebDavSyncCollectionPlan(target, counts);
      }
      if (target == _maxRecordBytes) {
        throw const FormatException(
          'Collections exceed the sync manifest capacity.',
        );
      }
      target = target * 2 > _maxRecordBytes ? _maxRecordBytes : target * 2;
    }
  }

  static bool isCollectionRecord(String key) =>
      key.startsWith('homecollection/');
  static bool isCollectionOrder(String key) => key == 'homecollections/items';

  static Map<String, WebDavSyncHotDocument> split(
    WebDavSyncHotDocument source, {
    bool includeCollections = true,
    int? targetBytes,
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
    final available =
        WebDavSyncLimits.maxSectionsPerManifest -
        reservedSectionCount([source.circleProfileId]);
    final target =
        targetBytes ??
        (_recordCount(source) <= available
            ? _targetBytes
            : _fit({
                source.circleProfileId: _sizes(source),
              }, available).targetBytes);
    if (target < _targetBytes || target > _maxRecordBytes) {
      throw ArgumentError.value(target, 'targetBytes');
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
      final bytes = _recordBytes(key, value);
      if (size + bytes > target && batch.isNotEmpty) flush();
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
