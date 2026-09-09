import 'dart:io';

import '../transfer/transfer_io.dart';

/// The small authored bootstrap section points to an immutable encrypted
/// archive stored outside every device directory. Its own identity maps stay
/// attached to the snapshot even when the publishing device's registry grows.
final class WebDavSyncSnapshotDescriptor {
  const WebDavSyncSnapshotDescriptor({
    required this.contentHash,
    required this.size,
    required this.semanticDigest,
    required this.databaseDigest,
    required this.profileMap,
    required this.resourceMap,
  });

  static const int schemaVersion = 2;
  static const int maxDescriptorBytes = 256 * 1024;
  final String contentHash;
  final int size;
  final String semanticDigest;
  final String databaseDigest;
  final Map<String, String> profileMap;
  final Map<String, String> resourceMap;

  Map<String, Object?> toJson() => {
    'format': 'debrify-sync-snapshot',
    'version': schemaVersion,
    'contentHash': contentHash,
    'size': size,
    'semanticDigest': semanticDigest,
    'databaseDigest': databaseDigest,
    'profileMap': profileMap,
    'resourceMap': resourceMap,
  };

  factory WebDavSyncSnapshotDescriptor.fromJson(Object? value) {
    if (value is! Map ||
        value['format'] != 'debrify-sync-snapshot' ||
        value['version'] != schemaVersion ||
        value.length != 8) {
      throw const FormatException('Invalid WebDAV sync snapshot descriptor');
    }
    String hash(String field) {
      final result = value[field];
      if (result is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(result)) {
        throw const FormatException('Invalid WebDAV sync snapshot digest');
      }
      return result;
    }

    Map<String, String> identities(String field, int maxEntries) {
      final raw = value[field];
      if (raw is! Map || raw.length > maxEntries) {
        throw const FormatException('Invalid WebDAV sync snapshot identities');
      }
      final ids = <String, String>{};
      final seen = <String>{};
      final pattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
      for (final entry in raw.entries) {
        if (entry.key is! String ||
            entry.value is! String ||
            !pattern.hasMatch(entry.key as String) ||
            !pattern.hasMatch(entry.value as String) ||
            !seen.add(entry.value as String)) {
          throw const FormatException('Invalid WebDAV sync snapshot identity');
        }
        ids[entry.key as String] = entry.value as String;
      }
      return Map.unmodifiable(ids);
    }

    final size = value['size'];
    if (size is! int || size < 125 || size > TransferIo.maxFileBytes) {
      throw const FormatException('Invalid WebDAV sync snapshot size');
    }
    final profiles = identities('profileMap', 64);
    final resources = identities('resourceMap', 4096);
    if (profiles.isEmpty ||
        profiles.values
            .toSet()
            .intersection(resources.values.toSet())
            .isNotEmpty) {
      throw const FormatException(
        'Conflicting WebDAV sync snapshot identities',
      );
    }
    return WebDavSyncSnapshotDescriptor(
      contentHash: hash('contentHash'),
      size: size,
      semanticDigest: hash('semanticDigest'),
      databaseDigest: hash('databaseDigest'),
      profileMap: profiles,
      resourceMap: resources,
    );
  }
}

/// File ownership travels explicitly with a prepared bootstrap. Only this
/// metadata is held while encryption and network I/O are running.
final class WebDavSyncPreparedSnapshot {
  const WebDavSyncPreparedSnapshot({
    required this.archive,
    required this.staging,
    required this.semanticDigest,
    required this.databaseDigest,
    required this.profileMap,
    required this.resourceMap,
  });
  final File archive;
  final Directory staging;
  final String semanticDigest;
  final String databaseDigest;
  final Map<String, String> profileMap;
  final Map<String, String> resourceMap;

  Future<void> dispose() async {
    if (await staging.exists()) await staging.delete(recursive: true);
  }
}
