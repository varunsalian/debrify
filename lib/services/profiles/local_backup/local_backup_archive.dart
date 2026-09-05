import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../../utils/app_storage.dart';
import '../../../utils/streamed_file_copy.dart';
import '../../diagnostic_log.dart';
import '../portable_profile_package.dart';
import '../profile_authorization.dart';
import '../profile_database_snapshot.dart';
import '../profile_package_service.dart';
import '../profile_scope.dart';
import 'local_backup_zip.dart';

export 'local_backup_zip.dart'
    show
        LocalBackupByteProgress,
        LocalBackupCancellation,
        LocalBackupCancelledException,
        LocalBackupFormatException,
        LocalBackupLimitException;

/// A destination or scratch volume ran out of space, or a write failed in a
/// way the user can act on (permissions, ejected media).
final class LocalBackupStorageException implements Exception {
  const LocalBackupStorageException(this.message, {this.cause});

  final String message;
  final FileSystemException? cause;

  bool get isOutOfSpace {
    final code = cause?.osError?.errorCode;
    if (code == 28 || code == 112) return true; // ENOSPC, ERROR_DISK_FULL
    final text = cause?.osError?.message.toLowerCase() ?? '';
    return text.contains('no space left') || text.contains('disk full');
  }

  @override
  String toString() => message;
}

/// Coarse progress labels reported before each stage begins.
typedef LocalBackupStageCallback = void Function(String stage);

/// The container's small metadata document. Version bumps here are
/// independent of [PortableProfilePackage.version], which the embedded
/// package keeps.
class LocalBackupManifest {
  const LocalBackupManifest({
    required this.createdAt,
    required this.mode,
    required this.package,
    required this.entries,
  });

  static const String format = 'debrify-local-backup';
  static const int version = 1;
  static const String manifestEntry = 'manifest.json';
  static const String digestEntry = 'manifest.sha256';
  static const String fileExtension = '.debrify';
  static const String mimeType = 'application/octet-stream';

  /// The manifest carries preferences and resource records, so it is bounded
  /// like the legacy JSON envelope; databases and playlist text live outside.
  static const int maxManifestBytes = PortableProfilePackage.maxEnvelopeBytes;
  static const int maxDataEntries = 2048;

  /// Disk-oriented aggregate cap on extracted content. Staging needs this
  /// much free space plus the archive itself.
  static const int maxTotalDataBytes = 16 * 1024 * 1024 * 1024;

  final DateTime createdAt;
  final String mode;
  final Map<String, dynamic> package;
  final List<LocalBackupManifestEntry> entries;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'format': format,
    'version': version,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'mode': mode,
    'entries': <Map<String, Object?>>[
      for (final entry in entries) entry.toJson(),
    ],
    'package': package,
  };

  static LocalBackupManifest fromJson(Map<String, dynamic> json) {
    if (json['format'] != format) {
      throw const LocalBackupFormatException('Not a Debrify backup archive');
    }
    final version = json['version'];
    if (version is! int || version < 1) {
      throw const LocalBackupFormatException('Backup archive version invalid');
    }
    if (version > LocalBackupManifest.version) {
      throw const LocalBackupFormatException(
        'This backup was created by a newer Debrify. Update the app to '
        'restore it.',
      );
    }
    final createdAt = json['createdAt'];
    final mode = json['mode'];
    final package = json['package'];
    final rawEntries = json['entries'];
    if (createdAt is! String ||
        mode is! String ||
        package is! Map<String, dynamic> ||
        rawEntries is! List) {
      throw const LocalBackupFormatException('Backup manifest is invalid');
    }
    if (rawEntries.length > maxDataEntries) {
      throw const LocalBackupLimitException(
        'Backup archive lists too many entries',
      );
    }
    final entries = <LocalBackupManifestEntry>[];
    final names = <String>{};
    var total = 0;
    for (final raw in rawEntries) {
      if (raw is! Map) {
        throw const LocalBackupFormatException('Backup manifest is invalid');
      }
      final entry = LocalBackupManifestEntry.fromJson(raw);
      if (!names.add(entry.name)) {
        throw LocalBackupFormatException(
          'Backup manifest repeats entry ${entry.name}',
        );
      }
      total += entry.bytes;
      if (total > maxTotalDataBytes) {
        throw const LocalBackupLimitException(
          'Backup archive content exceeds the supported size',
        );
      }
      entries.add(entry);
    }
    return LocalBackupManifest(
      createdAt: DateTime.tryParse(createdAt)?.toUtc() ?? DateTime.utc(1970),
      mode: mode,
      package: package,
      entries: List<LocalBackupManifestEntry>.unmodifiable(entries),
    );
  }
}

enum LocalBackupEntryKind { database, attachment }

class LocalBackupManifestEntry {
  const LocalBackupManifestEntry({
    required this.name,
    required this.kind,
    required this.bytes,
    required this.sha256,
  });

  final String name;
  final LocalBackupEntryKind kind;
  final int bytes;
  final String sha256;

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'kind': kind.name,
    'bytes': bytes,
    'sha256': sha256,
  };

  static LocalBackupManifestEntry fromJson(Map<Object?, Object?> json) {
    final name = json['name'];
    final kindName = json['kind'];
    final bytes = json['bytes'];
    final sha256 = json['sha256'];
    final kind = LocalBackupEntryKind.values
        .where((value) => value.name == kindName)
        .firstOrNull;
    if (name is! String ||
        !LocalBackupZip.isSafeEntryName(name) ||
        kind == null ||
        bytes is! int ||
        bytes < 0 ||
        bytes > LocalBackupZip.maxEntryBytes ||
        sha256 is! String ||
        sha256.isEmpty ||
        sha256.length > 64) {
      throw const LocalBackupFormatException('Backup manifest entry invalid');
    }
    return LocalBackupManifestEntry(
      name: name,
      kind: kind,
      bytes: bytes,
      sha256: sha256,
    );
  }
}

/// Private scratch directories for archive creation and staging. Each
/// operation owns one; abandoned ones are removed on the next app start.
class LocalBackupScratch {
  LocalBackupScratch._();

  static const String _rootName = 'local-backup';

  static Future<Directory> root() async =>
      Directory(p.join((await AppStorage.support()).path, _rootName));

  static Future<Directory> create(String purpose) async {
    final directory = Directory(
      p.join((await root()).path, '$purpose-${_token()}'),
    );
    await directory.create(recursive: true);
    return directory;
  }

  static Future<void> delete(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {
      // Best effort: the startup sweep retries.
    }
  }

  /// Removes every scratch directory. Call only at startup, before any
  /// backup operation can be running.
  static Future<void> cleanAbandoned() async {
    final directory = await root();
    if (!await directory.exists()) return;
    await for (final child in directory.list()) {
      try {
        await child.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String _token() {
    final random = Random.secure();
    final bytes = List<int>.generate(9, (_) => random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '').toLowerCase();
  }
}

/// Serializes backup operations: a second export or restore is refused
/// while one is running rather than sharing scratch space.
class LocalBackupOperationGuard {
  LocalBackupOperationGuard._();

  static bool _active = false;

  static bool get isActive => _active;

  static Future<T> run<T>(Future<T> Function() body) async {
    if (_active) {
      throw StateError('Another backup operation is still running');
    }
    _active = true;
    try {
      return await body();
    } finally {
      _active = false;
    }
  }
}

class LocalBackupExportResult {
  const LocalBackupExportResult({
    required this.archive,
    required this.fileName,
    required this.package,
    required this.archiveBytes,
    required this.entryCount,
    required this.elapsed,
  });

  final File archive;
  final String fileName;
  final PortableProfilePackage package;
  final int archiveBytes;
  final int entryCount;
  final Duration elapsed;

  bool get cachesPruned =>
      package.omissions.containsKey('rebuildableDatabaseCachesOmitted');
}

/// Builds a `.debrify` archive from a profile export without holding any
/// database or playlist in memory. Only manual local backups use this.
class LocalBackupExporter {
  LocalBackupExporter({required this.service});

  final ProfilePackageService service;

  static const String _source = 'local_backup';

  Future<LocalBackupExportResult> export({
    required ProfileAuthorizationContext context,
    required Directory staging,
    required bool allProfiles,
    ProfileScope? scope,
    LocalBackupStageCallback? onStage,
    LocalBackupByteProgress? onBytes,
    LocalBackupCancellation? cancellation,
    DateTime? now,
  }) async {
    if (!allProfiles && scope == null) {
      throw ArgumentError('Single-profile export needs a scope');
    }
    final operationId = LocalBackupScratch._token();
    final stopwatch = Stopwatch()..start();
    final createdAt = (now ?? DateTime.now()).toUtc();
    final entries = <LocalBackupManifestEntry>[];
    final files = <String, File>{};
    var totalBytes = 0;

    void stage(String label, [Map<String, Object?> fields = const {}]) {
      onStage?.call(label);
      DiagnosticLog.instance.recordEvent(
        source: _source,
        event: 'export_stage',
        fields: <String, Object?>{
          'operationId': operationId,
          'stage': label,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          ...fields,
        },
      );
    }

    void addEntry(LocalBackupManifestEntry entry, File file) {
      if (files.containsKey(entry.name)) {
        throw LocalBackupFormatException('Duplicate entry ${entry.name}');
      }
      totalBytes += entry.bytes;
      if (entries.length >= LocalBackupManifest.maxDataEntries ||
          totalBytes > LocalBackupManifest.maxTotalDataBytes) {
        throw const LocalBackupLimitException(
          'Backup content exceeds the supported archive size',
        );
      }
      entries.add(entry);
      files[entry.name] = file;
    }

    final sinks = ProfilePackageFileSinks(
      databaseFile:
          (
            profileBackupId,
            databaseName,
            snapshot, {
            required bytes,
            required sha256,
          }) async {
            cancellation?.throwIfCancelled();
            final name = 'databases/$profileBackupId/$databaseName';
            final destination = File(p.join(staging.path, name));
            await destination.parent.create(recursive: true);
            await _moveFile(snapshot, destination);
            addEntry(
              LocalBackupManifestEntry(
                name: name,
                kind: LocalBackupEntryKind.database,
                bytes: bytes,
                sha256: sha256,
              ),
              destination,
            );
            stage('Saved $databaseName', <String, Object?>{'bytes': bytes});
            return name;
          },
      resourceContent: (resourceBackupId, content) async {
        cancellation?.throwIfCancelled();
        final name = 'attachments/$resourceBackupId.m3u';
        final destination = File(p.join(staging.path, name));
        await destination.parent.create(recursive: true);
        final hasher = StreamedSha256();
        final output = await destination.open(mode: FileMode.write);
        var bytes = 0;
        try {
          const chunkChars = 64 * 1024;
          for (var start = 0; start < content.length; start += chunkChars) {
            cancellation?.throwIfCancelled();
            final end = min(content.length, start + chunkChars);
            final encoded = utf8.encode(content.substring(start, end));
            hasher.add(encoded);
            await output.writeFrom(encoded);
            bytes += encoded.length;
          }
          await output.flush();
        } finally {
          await output.close();
        }
        if (bytes > PortableProfilePackage.maxResourceContentBytes) {
          throw const LocalBackupLimitException(
            'An imported playlist is too large to back up',
          );
        }
        final sha256 = hasher.finish();
        addEntry(
          LocalBackupManifestEntry(
            name: name,
            kind: LocalBackupEntryKind.attachment,
            bytes: bytes,
            sha256: sha256,
          ),
          destination,
        );
        return <String, Object?>{
          'entry': name,
          'bytes': bytes,
          'sha256': sha256,
        };
      },
    );

    try {
      stage('Preparing backup…');
      cancellation?.throwIfCancelled();
      final package = await _mapStorageErrors(
        () => allProfiles
            ? service.exportAllProfiles(
                context: context,
                includeSecrets: true,
                fileSinks: sinks,
              )
            : service.exportProfile(
                context: context,
                scope: scope!,
                includeSecrets: true,
                sanitized: false,
                fileSinks: sinks,
              ),
      );
      if (DebrifyTvBackupOmission.fromOmissions(package.omissions) != null) {
        throw StateError('Local archives must never omit Debrify TV');
      }
      cancellation?.throwIfCancelled();

      stage('Writing manifest…');
      // Integrity stamping, JSON encoding and hashing of a manifest that can
      // reach tens of megabytes stay off the UI isolate, like the legacy
      // envelope pipeline. Only the small entry list is built here.
      final manifestEntries = List<LocalBackupManifestEntry>.unmodifiable(
        entries,
      );
      final encoded = await _encodeManifestOffMain(
        package,
        createdAt: createdAt,
        entries: manifestEntries,
      );
      final manifestBytes = encoded.bytes;
      if (manifestBytes.length > LocalBackupManifest.maxManifestBytes) {
        throw const LocalBackupLimitException(
          'Backup settings and connections exceed the manifest limit',
        );
      }
      final manifestFile = File(
        p.join(staging.path, LocalBackupManifest.manifestEntry),
      );
      final digestFile = File(
        p.join(staging.path, LocalBackupManifest.digestEntry),
      );
      await _mapStorageErrors(() async {
        await manifestFile.writeAsBytes(manifestBytes, flush: true);
        await digestFile.writeAsString(encoded.digest, flush: true);
      });

      final stamp = createdAt.toIso8601String().substring(0, 10);
      final fileName =
          '${allProfiles ? 'debrify-profiles' : 'debrify-profile'}-$stamp'
          '${LocalBackupManifest.fileExtension}';
      final archive = File(p.join(staging.path, fileName));
      stage('Packing backup…', <String, Object?>{
        'entries': entries.length,
        'dataBytes': totalBytes,
      });
      final sources = <LocalBackupZipSource>[
        for (final entry in entries)
          LocalBackupZipSource(
            name: entry.name,
            file: files[entry.name]!,
            bytes: entry.bytes,
          ),
        LocalBackupZipSource(
          name: LocalBackupManifest.manifestEntry,
          file: manifestFile,
          bytes: manifestBytes.length,
        ),
        LocalBackupZipSource(
          name: LocalBackupManifest.digestEntry,
          file: digestFile,
          bytes: await digestFile.length(),
        ),
      ];
      await _mapStorageErrors(
        () => LocalBackupZip.write(
          output: archive,
          sources: sources,
          modified: createdAt,
          onProgress: onBytes,
          cancellation: cancellation,
        ),
      );
      // Staged inputs are no longer needed; free the space before verifying.
      for (final file in files.values) {
        try {
          await file.delete();
        } catch (_) {}
      }

      stage('Checking backup…');
      await verifyArchive(
        archive,
        expectedEntries: manifestEntries,
        onBytes: onBytes,
        cancellation: cancellation,
      );
      stopwatch.stop();
      stage('Backup ready', <String, Object?>{
        'archiveBytes': await archive.length(),
      });
      return LocalBackupExportResult(
        archive: archive,
        fileName: fileName,
        package: package,
        archiveBytes: await archive.length(),
        entryCount: entries.length,
        elapsed: stopwatch.elapsed,
      );
    } catch (error, stackTrace) {
      DiagnosticLog.instance.recordError(
        source: _source,
        event: error is LocalBackupCancelledException
            ? 'export_cancelled'
            : 'export_failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Re-reads a finished archive and checks every entry against the
  /// manifest that was just written, plus the manifest against its stamp.
  static Future<void> verifyArchive(
    File archive, {
    required List<LocalBackupManifestEntry> expectedEntries,
    LocalBackupByteProgress? onBytes,
    LocalBackupCancellation? cancellation,
  }) async {
    final reader = await LocalBackupZipReader.open(archive);
    try {
      final names = reader.entries.map((entry) => entry.name).toSet();
      final expectedNames = <String>{
        for (final entry in expectedEntries) entry.name,
        LocalBackupManifest.manifestEntry,
        LocalBackupManifest.digestEntry,
      };
      if (names.length != expectedNames.length ||
          !names.containsAll(expectedNames)) {
        throw const LocalBackupFormatException(
          'Written backup does not list the expected entries',
        );
      }
      for (final entry in expectedEntries) {
        final stored = reader.find(entry.name)!;
        if (stored.bytes != entry.bytes) {
          throw LocalBackupFormatException(
            'Written entry ${entry.name} has the wrong size',
          );
        }
        final digest = await reader.digest(
          stored,
          onProgress: onBytes,
          cancellation: cancellation,
        );
        if (digest != entry.sha256) {
          throw LocalBackupFormatException(
            'Written entry ${entry.name} failed verification',
          );
        }
      }
      await _readVerifiedManifest(reader);
    } finally {
      await reader.close();
    }
  }

  /// A closure passed to [Isolate.run] captures its whole enclosing scope,
  /// so this lives in a method whose only locals are sendable arguments.
  /// Only the serialized bytes and their digest come back; the envelope map
  /// is never needed on the UI isolate.
  static Future<({List<int> bytes, String digest})> _encodeManifestOffMain(
    PortableProfilePackage package, {
    required DateTime createdAt,
    required List<LocalBackupManifestEntry> entries,
  }) {
    return Isolate.run(() async {
      final envelope = await PortableProfilePackage.withIntegrity(package);
      final manifest = LocalBackupManifest(
        createdAt: createdAt,
        mode: package.mode,
        package: envelope,
        entries: entries,
      );
      final bytes = utf8.encode(jsonEncode(manifest.toJson()));
      final hasher = StreamedSha256()..add(bytes);
      return (bytes: bytes, digest: hasher.finish());
    });
  }

  static Future<T> _mapStorageErrors<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FileSystemException catch (error) {
      final wrapped = LocalBackupStorageException(
        'Backup could not be written',
        cause: error,
      );
      throw LocalBackupStorageException(
        wrapped.isOutOfSpace
            ? 'Not enough free space to create the backup. Free some space '
                  'and try again.'
            : 'The backup could not be written to app storage '
                  '(${error.osError?.message ?? error.message}).',
        cause: error,
      );
    }
  }

  static Future<void> _moveFile(File source, File destination) async {
    try {
      await source.rename(destination.path);
    } on FileSystemException {
      // Cross-volume: fall back to a streamed copy.
      await copyFileStreamed(source, destination);
      await source.delete();
    }
  }
}

/// A verified manifest plus the digest stamp it was checked against. The
/// digest lets a later [LocalBackupRestorer.stage] prove it is unpacking the
/// same archive without reading and hashing the manifest a second time.
class LocalBackupInspection {
  const LocalBackupInspection({required this.manifest, required this.digest});

  final LocalBackupManifest manifest;
  final String digest;
}

Future<String> _readManifestStamp(LocalBackupZipReader reader) async {
  final digestEntry = reader.find(LocalBackupManifest.digestEntry);
  if (digestEntry == null) {
    throw const LocalBackupFormatException(
      'Backup archive is missing its manifest',
    );
  }
  return utf8.decode(await reader.readSmall(digestEntry, maxBytes: 128)).trim();
}

/// Reads the manifest and its digest stamp from an open archive and returns
/// the parsed, bounded manifest. Hashing and JSON parsing of a manifest that
/// can reach [LocalBackupManifest.maxManifestBytes] run off the UI isolate.
Future<LocalBackupInspection> _readVerifiedManifest(
  LocalBackupZipReader reader,
) async {
  final manifestEntry = reader.find(LocalBackupManifest.manifestEntry);
  if (manifestEntry == null) {
    throw const LocalBackupFormatException(
      'Backup archive is missing its manifest',
    );
  }
  final stamp = await _readManifestStamp(reader);
  final manifestBytes = await reader.readSmall(
    manifestEntry,
    maxBytes: LocalBackupManifest.maxManifestBytes,
  );
  final decoded = await _parseManifestOffMain(manifestBytes, stamp);
  return LocalBackupInspection(
    manifest: LocalBackupManifest.fromJson(decoded),
    digest: stamp,
  );
}

Future<Map<String, dynamic>> _parseManifestOffMain(
  List<int> manifestBytes,
  String stamp,
) => Isolate.run(() {
  final hasher = StreamedSha256()..add(manifestBytes);
  if (hasher.finish() != stamp) {
    throw const LocalBackupFormatException(
      'Backup manifest failed its integrity check',
    );
  }
  final value = jsonDecode(utf8.decode(manifestBytes));
  if (value is! Map<String, dynamic>) {
    throw const LocalBackupFormatException('Backup manifest is invalid');
  }
  return value;
});

/// A verified, extracted archive ready for the restore coordinator.
class LocalBackupRestoreStage {
  LocalBackupRestoreStage._({
    required this.package,
    required this.manifest,
    required this.staging,
    required Map<String, File> databaseFiles,
  }) : _databaseFiles = databaseFiles;

  final PortableProfilePackage package;
  final LocalBackupManifest manifest;
  final Directory staging;
  final Map<String, File> _databaseFiles;

  File? resolveDatabase(String entry) => _databaseFiles[entry];

  Future<void> dispose() => LocalBackupScratch.delete(staging);
}

/// Extracts a `.debrify` archive into private staging with every size,
/// digest, and name check applied before the package is decoded.
class LocalBackupRestorer {
  LocalBackupRestorer._();

  static const String _source = 'local_backup';

  /// Reads only the archive directory and manifest: enough to describe the
  /// backup for a confirmation dialog without extracting anything.
  static Future<LocalBackupInspection> inspect(File archive) async {
    final reader = await LocalBackupZipReader.open(archive);
    try {
      final inspection = await _readVerifiedManifest(reader);
      _checkEntriesAgainstManifest(reader, inspection.manifest);
      return inspection;
    } finally {
      await reader.close();
    }
  }

  /// [inspection] from a prior [inspect] skips the second manifest read: the
  /// archive's digest stamp must still match it, which proves the file was
  /// not swapped between the confirmation dialog and the unpack.
  static Future<LocalBackupRestoreStage> stage({
    required File archive,
    required Directory staging,
    LocalBackupInspection? inspection,
    LocalBackupStageCallback? onStage,
    LocalBackupByteProgress? onBytes,
    LocalBackupCancellation? cancellation,
  }) async {
    final operationId = LocalBackupScratch._token();
    final stopwatch = Stopwatch()..start();
    void stageLabel(String label, [Map<String, Object?> fields = const {}]) {
      onStage?.call(label);
      DiagnosticLog.instance.recordEvent(
        source: _source,
        event: 'restore_stage',
        fields: <String, Object?>{
          'operationId': operationId,
          'stage': label,
          'elapsedMs': stopwatch.elapsedMilliseconds,
          ...fields,
        },
      );
    }

    try {
      stageLabel('Reading backup…');
      final reader = await LocalBackupZipReader.open(archive);
      final databaseFiles = <String, File>{};
      final attachmentFiles = <String, File>{};
      final LocalBackupManifest manifest;
      try {
        if (inspection != null) {
          if (await _readManifestStamp(reader) != inspection.digest) {
            throw const LocalBackupFormatException(
              'Backup changed while it was being read',
            );
          }
          manifest = inspection.manifest;
        } else {
          manifest = (await _readVerifiedManifest(reader)).manifest;
        }
        _checkEntriesAgainstManifest(reader, manifest);
        for (final entry in manifest.entries) {
          cancellation?.throwIfCancelled();
          stageLabel('Extracting ${p.basename(entry.name)}…', <String, Object?>{
            'bytes': entry.bytes,
          });
          final destination = File(p.join(staging.path, entry.name));
          final digest = await _mapStorageErrors(
            () => reader.extract(
              reader.find(entry.name)!,
              destination,
              onProgress: onBytes,
              cancellation: cancellation,
            ),
          );
          if (digest != entry.sha256) {
            throw LocalBackupFormatException(
              'Backup entry ${entry.name} failed verification',
            );
          }
          switch (entry.kind) {
            case LocalBackupEntryKind.database:
              databaseFiles[entry.name] = destination;
            case LocalBackupEntryKind.attachment:
              attachmentFiles[entry.name] = destination;
          }
        }
      } finally {
        await reader.close();
      }

      stageLabel('Checking backup…');
      _checkDatabaseReferences(manifest.package, databaseFiles);
      // The integrity digest covers the package as stored, with playlist
      // text still referenced. Decode first (off the UI isolate; the decoder
      // copies what it keeps), then put the text back.
      final package = await _decodeOffMain(manifest.package);
      await _inlineAttachments(package.resources, attachmentFiles, manifest);
      stopwatch.stop();
      stageLabel('Backup verified', <String, Object?>{
        'databases': databaseFiles.length,
        'attachments': attachmentFiles.length,
      });
      return LocalBackupRestoreStage._(
        package: package,
        manifest: manifest,
        staging: staging,
        databaseFiles: databaseFiles,
      );
    } catch (error, stackTrace) {
      DiagnosticLog.instance.recordError(
        source: _source,
        event: error is LocalBackupCancelledException
            ? 'restore_stage_cancelled'
            : 'restore_stage_failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// See [LocalBackupExporter._encodeManifestOffMain] for why this is not
  /// an inline closure.
  static Future<PortableProfilePackage> _decodeOffMain(
    Map<String, dynamic> packageMap,
  ) =>
      Isolate.run(() => PortableProfilePackage.decodeFileBackedMap(packageMap));

  static void _checkEntriesAgainstManifest(
    LocalBackupZipReader reader,
    LocalBackupManifest manifest,
  ) {
    final listed = <String>{
      for (final entry in manifest.entries) entry.name,
      LocalBackupManifest.manifestEntry,
      LocalBackupManifest.digestEntry,
    };
    for (final stored in reader.entries) {
      if (!listed.contains(stored.name)) {
        throw LocalBackupFormatException(
          'Backup archive contains an unexpected entry ${stored.name}',
        );
      }
    }
    for (final entry in manifest.entries) {
      final stored = reader.find(entry.name);
      if (stored == null) {
        throw LocalBackupFormatException(
          'Backup archive is missing entry ${entry.name}',
        );
      }
      if (stored.bytes != entry.bytes) {
        throw LocalBackupFormatException(
          'Backup entry ${entry.name} has the wrong size',
        );
      }
      final prefix = switch (entry.kind) {
        LocalBackupEntryKind.database => 'databases/',
        LocalBackupEntryKind.attachment => 'attachments/',
      };
      if (!entry.name.startsWith(prefix)) {
        throw LocalBackupFormatException(
          'Backup entry ${entry.name} is filed under the wrong kind',
        );
      }
    }
  }

  /// Puts imported playlist text back where the resource service expects it.
  /// One attachment is read at a time; the bound is the largest playlist.
  static Future<void> _inlineAttachments(
    List<Map<String, dynamic>> resources,
    Map<String, File> attachmentFiles,
    LocalBackupManifest manifest,
  ) async {
    final byName = <String, LocalBackupManifestEntry>{
      for (final entry in manifest.entries) entry.name: entry,
    };
    final used = <String>{};
    for (final resource in resources) {
      final secret = resource['secretConfig'];
      if (secret is! Map) continue;
      final reference = secret[ProfilePackageFileSinks.contentAttachmentKey];
      if (reference == null) continue;
      if (reference is! Map ||
          reference['entry'] is! String ||
          reference['bytes'] is! int ||
          reference['sha256'] is! String) {
        throw const LocalBackupFormatException(
          'Backup playlist attachment reference is invalid',
        );
      }
      final name = reference['entry'] as String;
      final entry = byName[name];
      final file = attachmentFiles[name];
      if (entry == null ||
          file == null ||
          entry.kind != LocalBackupEntryKind.attachment ||
          entry.bytes != reference['bytes'] ||
          entry.sha256 != reference['sha256'] ||
          !used.add(name)) {
        throw const LocalBackupFormatException(
          'Backup playlist attachment does not match its manifest entry',
        );
      }
      if (entry.bytes > PortableProfilePackage.maxResourceContentBytes) {
        throw const LocalBackupLimitException(
          'An imported playlist in this backup is too large to restore',
        );
      }
      final content = await file.readAsString();
      final replaced = Map<String, dynamic>.from(secret)
        ..remove(ProfilePackageFileSinks.contentAttachmentKey)
        ..['content'] = content;
      resource['secretConfig'] = replaced;
    }
  }

  static void _checkDatabaseReferences(
    Map<String, dynamic> packageMap,
    Map<String, File> databaseFiles,
  ) {
    final sections = packageMap['sections'];
    if (sections is! Map) return;
    final used = <String>{};
    for (final section in sections.values) {
      if (section is! Map) continue;
      final values = section['values'];
      if (values is! Map) continue;
      for (final value in values.values) {
        if (value is! Map || value['encoding'] != 'file') continue;
        final reference = value['entry'];
        if (reference is! String ||
            !databaseFiles.containsKey(reference) ||
            !used.add(reference)) {
          throw const LocalBackupFormatException(
            'Backup database reference does not match its manifest entry',
          );
        }
      }
    }
  }

  static Future<T> _mapStorageErrors<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FileSystemException catch (error) {
      final wrapped = LocalBackupStorageException('', cause: error);
      throw LocalBackupStorageException(
        wrapped.isOutOfSpace
            ? 'Not enough free space to unpack the backup. Free some space '
                  'and try again.'
            : 'The backup could not be unpacked into app storage '
                  '(${error.osError?.message ?? error.message}).',
        cause: error,
      );
    }
  }
}
