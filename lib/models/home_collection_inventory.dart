import 'dart:convert';
import 'dart:isolate';

import 'package:archive/archive.dart';

import 'home_collection.dart';

/// Atomic local inventory. Null records are pending per-collection deletions;
/// sync journals them in its retained tombstone tier before removing them here.
/// Legacy list preferences are accepted and upgraded on the next mutation.
class HomeCollectionInventory {
  static const String syncDeferredKey = 'remote_home_collections_sync_deferred';
  bool syncDeferred = false;
  static const String legacyPrefsKey = 'home_collections_v1';
  // Old clients exclude remote_* preferences from recurring sync. A separate
  // key preserves the richer inventory when they edit their legacy snapshot.
  static const String prefsKey = 'remote_home_collections_v2';
  static const int maxStoredBytes = 8 * 1024 * 1024;
  // Each compressed chunk is bounded independently. Merged inventories use
  // multiple chunks instead of sharing the hot-state payload limit.
  static const int maxEnvelopeBytes = 32 * 1024 * 1024;
  // Allow gzip framing and base64 expansion even for incompressible JSON.
  // Decompressed and legacy JSON are still bounded by maxEnvelopeBytes.
  static const int maxEncodedBytes = 44 * 1024 * 1024;
  static const int maxRecords = 1024;
  static const int maxChunkedEncodedBytes = 256 * 1024 * 1024;
  // Sixty-four peers can each contribute an 8 MiB inventory; leave room for
  // envelope metadata while retaining a hard bound for untrusted backups.
  static const int maxMaterializedBytes = 520 * 1024 * 1024;

  final Map<String, HomeCollection?> records;
  final List<String> order;
  bool hadCorruption = false;

  HomeCollectionInventory({
    Map<String, HomeCollection?>? records,
    List<String>? order,
  }) : records = records ?? {},
       order = order ?? [];

  factory HomeCollectionInventory.decode(Object? encoded) {
    if (encoded == null || encoded == '') return HomeCollectionInventory();
    final raw = _unpack(encoded);
    final out = HomeCollectionInventory();
    if (raw is List) {
      for (final item in raw) {
        final c = HomeCollection.fromJson(_migrateVisuals(item));
        if (c == null) throw const FormatException('Invalid saved collection.');
        out.put(c);
      }
      return out;
    }
    if (raw is! Map ||
        raw['version'] != 2 ||
        raw['records'] is! Map ||
        raw['order'] is! List) {
      throw const FormatException(
        'Invalid saved collections. Restore a backup or remove them before importing.',
      );
    }
    out.hadCorruption = raw['recoveredCorruption'] == true;
    for (final entry in (raw['records'] as Map).entries) {
      if (entry.key is! String || (entry.key as String).isEmpty) {
        throw const FormatException('Invalid collection identity.');
      }
      final value = entry.value;
      final c = value == null
          ? null
          : HomeCollection.fromJson(_migrateVisuals(value));
      if (value != null && (c == null || c.id != entry.key)) {
        throw const FormatException('Invalid saved collection.');
      }
      out.records[entry.key as String] = c;
    }
    for (final id in raw['order'] as List) {
      if (id is! String) {
        throw const FormatException('Invalid collection order.');
      }
      if (out.records.containsKey(id) && !out.order.contains(id)) {
        out.order.add(id);
      }
    }
    for (final id in out.records.keys) {
      if (!out.order.contains(id)) out.order.add(id);
    }
    return out;
  }

  /// Read usable records without allowing one damaged entry to disable Home,
  /// backup or the rest of a sync circle. Strict decoding remains available
  /// for writes until the user explicitly resets or restores damaged data.
  factory HomeCollectionInventory.recover(Object? encoded) {
    final out = HomeCollectionInventory();
    if (encoded == null || encoded == '') return out;
    Object? raw;
    try {
      raw = _unpack(encoded);
    } catch (_) {
      out.hadCorruption = true;
      return out;
    }
    void read(Object? value, {String? id}) {
      try {
        if (value == null && id != null) {
          final single = HomeCollectionInventory(
            records: {id: null},
            order: [id],
          );
          single.validate();
          out.records[id] = null;
          out.order.add(id);
          return;
        }
        final c = HomeCollection.fromJson(_migrateVisuals(value));
        if (c == null || (id != null && c.id != id)) {
          throw const FormatException('Invalid saved collection.');
        }
        HomeCollectionInventory(records: {c.id: c}, order: [c.id]).validate();
        out.put(c);
      } catch (_) {
        out.hadCorruption = true;
      }
    }

    if (raw is List) {
      for (final value in raw) {
        read(value);
      }
      return out;
    }
    if (raw is! Map || raw['version'] != 2 || raw['records'] is! Map) {
      out.hadCorruption = true;
      return out;
    }
    out.hadCorruption = raw['recoveredCorruption'] == true;
    for (final e in (raw['records'] as Map).entries) {
      if (e.key is! String) {
        out.hadCorruption = true;
        continue;
      }
      read(e.value, id: e.key as String);
    }
    final preferred = raw['order'];
    if (preferred is List) {
      final ordered = <String>[];
      for (final id in preferred) {
        if (id is! String) {
          out.hadCorruption = true;
          continue;
        }
        if (out.records.containsKey(id) && !ordered.contains(id)) {
          ordered.add(id);
        }
      }
      for (final id in out.order) {
        if (!ordered.contains(id)) ordered.add(id);
      }
      out.order
        ..clear()
        ..addAll(ordered);
    } else {
      out.hadCorruption = true;
    }
    return out;
  }

  /// Compare stored records after the same migration used by local reads.
  /// Format markers describe storage, not a user's collection edit.
  static Object? comparableRecord(Object? value) {
    if (value == null) return null;
    try {
      final parsed = HomeCollection.fromJson(_migrateVisuals(value));
      if (parsed == null) return value;
      return parsed.toJson()
        ..remove('debrifyCollectionVersion')
        ..remove('debrifyVisualVersion');
    } catch (_) {
      return value;
    }
  }

  // Releases before native collections played every stored focus GIF, even
  // though they serialized a default false flag. Only migrate persisted data;
  // the public import parser continues to honor an author's explicit false.
  static Object? _migrateVisuals(Object? value) {
    if (value is! Map) return value;
    final folders = value['folders'];
    final hasModernFields =
        value['viewMode'] != null ||
        (folders is List &&
            folders.any(
              (folder) =>
                  folder is Map &&
                  (folder['heroVideoUrl'] != null ||
                      (folder['sources'] is List &&
                          (folder['sources'] as List).any(
                            (source) =>
                                source is Map &&
                                source['provider'] != null &&
                                source['provider'] != 'addon',
                          ))),
            ));
    final migrateGif =
        !hasModernFields &&
        value['debrifyCollectionVersion'] != 2 &&
        value['debrifyVisualVersion'] != 2;
    return {
      ...value,
      'debrifyCollectionVersion':
          value['debrifyCollectionVersion'] ?? (hasModernFields ? 2 : 1),
      if (value['folders'] is List)
        'folders': [
          for (final folder in value['folders'] as List)
            if (folder is Map)
              {
                ...folder,
                if (migrateGif &&
                    folder['focusGifUrl'] is String &&
                    (folder['focusGifUrl'] as String).trim().isNotEmpty)
                  'focusGifEnabled': true,
              }
            else
              folder,
        ],
    };
  }

  /// Import capacity concerns live definitions, not pending sync deletions.
  int get liveCount => records.values.where((c) => c != null).length;
  int get definitionBytes => utf8
      .encode(
        jsonEncode([
          for (final c in collections) c.copyWith(enabled: true).toJson(),
        ]),
      )
      .length;

  List<HomeCollection> get collections => [
    for (final id in order)
      if (records[id] case final c?) c,
  ];

  void put(HomeCollection c) {
    records[c.id] = c;
    if (!order.contains(c.id)) order.add(c.id);
  }

  void remove(String id) {
    if (records.containsKey(id)) records[id] = null;
  }

  Map<String, Object?> toJson() => {
    'version': 2,
    if (hadCorruption) 'recoveredCorruption': true,
    'records': {for (final e in records.entries) e.key: e.value?.toJson()},
    'order': order,
  };

  /// IDs become WebDAV record keys and Home row identities. Reject oversized
  /// identities before they can create an inventory that cannot be synced.
  void validate() {
    void bounded(String value, int limit, String label) {
      if (value.contains('\u0000')) {
        throw FormatException('$label contains an invalid character.');
      }
      if (utf8.encode(value).length > limit) {
        throw FormatException(
          '$label is too long. Import a smaller collection file.',
        );
      }
    }

    for (final entry in records.entries) {
      if (entry.key.isEmpty) {
        throw const FormatException('Collection ID must not be empty.');
      }
      bounded(entry.key, 256, 'Collection ID');
      final c = entry.value;
      if (c == null) continue;
      // These are the same structural bounds used by synced JSON values.
      // Check before saving so no accepted local definition is unsyncable.
      void jsonBounds(Object? value, int depth) {
        if (depth > 32) {
          throw const FormatException('Collection data is nested too deeply.');
        }
        if (value is List) {
          if (value.length > 20000) {
            throw const FormatException(
              'A collection can have at most 20,000 folders or sources per list.',
            );
          }
          for (final item in value) {
            jsonBounds(item, depth + 1);
          }
        } else if (value is Map) {
          if (value.length > 4096) {
            throw const FormatException(
              'Collection source has too many fields.',
            );
          }
          for (final e in value.entries) {
            if (e.key is! String || (e.key as String).isEmpty) {
              throw const FormatException('Invalid collection field name.');
            }
            bounded(e.key as String, 1024, 'Collection field name');
            jsonBounds(e.value, depth + 1);
          }
        } else if (value is num && !value.isFinite) {
          throw const FormatException('Invalid collection number.');
        }
      }

      jsonBounds(c.toJson(), 0);
      for (final f in c.folders) {
        bounded(f.id, 256, 'Folder ID');
        for (final source in f.sources) {
          bounded(source.addonId, 256, 'Addon ID');
          bounded(source.catalogId, 256, 'Catalog ID');
          bounded(source.type, 64, 'Catalog type');
          bounded(source.genre ?? '', 256, 'Genre');
        }
      }
    }
  }

  /// Heavy JSON/gzip work is performed before the preference commit barrier.
  static Future<({HomeCollectionInventory inventory, int size, int count})>
  readAsync(Object? encoded, {bool recover = false}) {
    ({HomeCollectionInventory inventory, int size, int count}) read() {
      final inventory = recover
          ? HomeCollectionInventory.recover(encoded)
          : HomeCollectionInventory.decode(encoded);
      return (
        inventory: inventory,
        size: inventory.definitionBytes,
        count: inventory.liveCount,
      );
    }

    if (encoded is String &&
        (encoded.length > 32768 ||
            encoded.startsWith('{"version":3') ||
            encoded.startsWith('{"version":4'))) {
      return Isolate.run(read);
    }
    return Future.value(read());
  }

  Future<({String encoded, int size, int count})> prepareAsync() {
    int estimate(Object? value) {
      if (value is String) return value.length;
      if (value is Map) {
        var n = 0;
        for (final e in value.entries) {
          n += '${e.key}'.length + estimate(e.value);
          if (n > 32768) break;
        }
        return n;
      }
      if (value is List) {
        var n = 0;
        for (final item in value) {
          n += estimate(item);
          if (n > 32768) break;
        }
        return n;
      }
      return 8;
    }

    ({String encoded, int size, int count}) prepare() {
      validate();
      return _encode();
    }

    return estimate(toJson()) > 32768
        ? Isolate.run(prepare)
        : Future.value(prepare());
  }

  String encode() => _encode().encoded;

  /// Serialize each record once, then reuse the JSON for either one envelope
  /// or independent chunks. Definition size comes from those same bytes.
  ({String encoded, int size, int count}) _encode() {
    final entries = <({String id, String json, int bytes})>[];
    final liveOrder = order.toSet();
    var definitionSize = 2;
    var definitions = 0;
    for (final entry in records.entries) {
      final value = jsonEncode(entry.value?.toJson());
      final valueBytes = utf8.encode(value).length;
      if (entry.value != null && liveOrder.contains(entry.key)) {
        definitionSize +=
            valueBytes -
            (entry.value!.enabled ? 0 : 1) +
            (definitions++ == 0 ? 0 : 1);
      }
      final encodedKey = jsonEncode(entry.key);
      entries.add((
        id: entry.key,
        json: '$encodedKey:$value',
        bytes: utf8.encode(encodedKey).length + 1 + valueBytes,
      ));
    }
    String envelope(
      List<({String id, String json, int bytes})> batch,
      List<String> ids,
    ) =>
        '{"version":2,${hadCorruption ? '"recoveredCorruption":true,' : ''}"records":{${batch.map((e) => e.json).join(',')}},"order":${jsonEncode(ids)}}';
    String compress(String raw) {
      final bytes = utf8.encode(raw);
      if (bytes.length > maxEnvelopeBytes) {
        throw const FormatException('Collection chunk exceeds 32 MiB.');
      }
      if (bytes.length <= 64 * 1024) return raw;
      return jsonEncode({
        'version': 3,
        'encoding': 'gzip-base64',
        'data': base64Encode(GZipEncoder().encode(bytes)),
      });
    }

    final overhead = utf8.encode(envelope([], order)).length;
    final bytes =
        entries.fold<int>(overhead, (n, e) => n + e.bytes) +
        (entries.isEmpty ? 0 : entries.length - 1);
    if (bytes > maxMaterializedBytes) {
      throw const FormatException(
        'Collection inventory exceeds its safe storage limit.',
      );
    }
    if (bytes <= maxEnvelopeBytes) {
      return (
        encoded: compress(envelope(entries, order)),
        size: definitionSize,
        count: liveCount,
      );
    }
    final chunks = <String>[];
    var start = 0;
    var size = 0;
    void flush(int end) {
      final batch = entries.sublist(start, end);
      chunks.add(compress(envelope(batch, batch.map((e) => e.id).toList())));
      start = end;
      size = 0;
    }

    for (var i = 0; i < entries.length; i++) {
      if (entries[i].bytes > maxEnvelopeBytes - 4096) {
        throw const FormatException(
          'A single collection exceeds its storage limit.',
        );
      }
      if (size + entries[i].bytes > 8 * 1024 * 1024 && i > start) flush(i);
      size += entries[i].bytes;
    }
    if (start < entries.length) flush(entries.length);
    final encoded = jsonEncode({
      'version': 4,
      if (hadCorruption) 'recoveredCorruption': true,
      'chunks': chunks,
      'order': order,
    });
    if (utf8.encode(encoded).length > maxChunkedEncodedBytes) {
      throw const FormatException(
        'Compressed collections exceed the device storage limit.',
      );
    }
    return (encoded: encoded, size: definitionSize, count: liveCount);
  }

  static Object? _unpack(Object? encoded) {
    final bytes = encoded is String ? utf8.encode(encoded).length : 0;
    if (bytes > maxMaterializedBytes) {
      throw const FormatException(
        'Encoded collection inventory exceeds its safe storage limit.',
      );
    }
    return _unpackParsed(
      encoded is String ? jsonDecode(encoded) : encoded,
      bytes,
    ).value;
  }

  static ({Object? value, int bytes}) _unpackParsed(
    Object? raw,
    int encodedBytes,
  ) {
    if (raw is Map &&
        (raw['version'] == 3 || raw['version'] == 4) &&
        encodedBytes > maxChunkedEncodedBytes) {
      throw const FormatException(
        'Encoded collection inventory exceeds 256 MiB.',
      );
    }
    if (raw is Map && raw['version'] == 4) {
      final chunks = raw['chunks'];
      if (chunks is! List || chunks.length > 1024 || raw['order'] is! List) {
        throw const FormatException('Invalid collection storage chunks.');
      }
      final records = <String, Object?>{};
      var expanded = 0;
      for (final chunk in chunks) {
        if (chunk is! String) {
          throw const FormatException('Invalid collection storage chunk.');
        }
        final bytes = utf8.encode(chunk).length;
        if (bytes > maxEncodedBytes) {
          throw const FormatException('Invalid collection storage chunk.');
        }
        final header = jsonDecode(chunk);
        if (header is! Map ||
            (header['version'] != 2 && header['version'] != 3) ||
            (header['version'] == 2 && bytes > maxEnvelopeBytes)) {
          throw const FormatException('Invalid collection storage chunk.');
        }
        final decoded = _unpackParsed(header, bytes);
        final part = decoded.value;
        if (part is! Map || part['records'] is! Map) {
          throw const FormatException('Invalid collection storage chunk.');
        }
        expanded += decoded.bytes;
        if (expanded > maxMaterializedBytes) {
          throw const FormatException(
            'Expanded collection chunks exceed their safe storage limit.',
          );
        }
        for (final e in (part['records'] as Map).entries) {
          if (e.key is! String || records.containsKey(e.key)) {
            throw const FormatException('Duplicate collection storage record.');
          }
          records[e.key as String] = e.value;
        }
      }
      return (
        value: {
          'version': 2,
          'records': records,
          'order': raw['order'],
          if (raw['recoveredCorruption'] == true) 'recoveredCorruption': true,
        },
        bytes: expanded,
      );
    }
    if (raw is! Map || raw['version'] != 3) {
      return (value: raw, bytes: encodedBytes);
    }
    if (raw['encoding'] != 'gzip-base64' ||
        raw['data'] is! String ||
        (raw['data'] as String).length > maxEncodedBytes) {
      throw const FormatException('Invalid compressed collection inventory.');
    }
    final output = _BoundedCollectionOutput(maxEnvelopeBytes);
    final valid = GZipDecoder().decodeStream(
      InputMemoryStream(base64Decode(raw['data'] as String)),
      output,
      verify: true,
    );
    if (!valid) {
      throw const FormatException('Invalid compressed collection inventory.');
    }
    final decoded = jsonDecode(utf8.decode(output.getBytes()));
    if (decoded is! Map || decoded['version'] != 2) {
      throw const FormatException('Invalid compressed collection inventory.');
    }
    return (value: decoded, bytes: output.length);
  }
}

/// Bound decompression as bytes arrive, before allocating the complete JSON.
class _BoundedCollectionOutput extends OutputMemoryStream {
  _BoundedCollectionOutput(this.limit);
  final int limit;
  void _check(int count) {
    if (length + count > limit) {
      throw const FormatException('Collection inventory exceeds 32 MiB.');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    super.writeBytes(bytes, length: length);
  }
}
