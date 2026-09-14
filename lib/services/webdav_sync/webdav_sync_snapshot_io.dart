import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:synchronized/synchronized.dart';

import '../../utils/app_storage.dart';
import '../diagnostic_log.dart';
import '../profiles/local_backup/local_backup_archive.dart';
import '../transfer/streaming_encrypted_file.dart';
import '../transfer/transfer_io.dart';
import '../webdav_protocol_client.dart';
import 'webdav_sync_codec.dart';
import 'webdav_sync_snapshot_models.dart';
import 'webdav_sync_transport.dart';

/// Disk-backed shared bootstrap transfer. Completed ciphertext is retained
/// across an interrupted publication so retry can reuse its encryption and
/// content address. Downloads likewise survive a later restore interruption.
final class WebDavSyncSnapshotIo {
  const WebDavSyncSnapshotIo();
  static final Lock _largeTransfer = Lock();
  static String _context(String circleId) =>
      'debrify/sync-snapshot/v2/$circleId';

  Future<WebDavSyncSnapshotDescriptor> publish({
    required WebDavSyncTransport transport,
    required WebDavSyncCircleKey key,
    required String circleId,
    required WebDavSyncPreparedSnapshot snapshot,
  }) => _largeTransfer.synchronized(() async {
    final watch = Stopwatch()..start();
    if (transport is! WebDavSyncSharedObjectTransport) {
      throw StateError('WebDAV sync requires shared file-object transport');
    }
    final objects = transport as WebDavSyncSharedObjectTransport;
    final directory = await _cache(circleId, key);
    final encrypted = File(
      '${directory.path}/outgoing-${snapshot.semanticDigest}.enc',
    );
    final journal = File(
      '${directory.path}/outgoing-${snapshot.semanticDigest}.json',
    );
    final receipt = File('${journal.path}.verified');
    await _prune(directory, keep: {encrypted.path, journal.path, receipt.path});
    WebDavSyncSnapshotDescriptor? descriptor;
    if (await journal.exists() &&
        await encrypted.exists() &&
        await journal.length() <=
            WebDavSyncSnapshotDescriptor.maxDescriptorBytes) {
      try {
        final existing = WebDavSyncSnapshotDescriptor.fromJson(
          jsonDecode(await journal.readAsString()),
        );
        if (existing.semanticDigest == snapshot.semanticDigest &&
            existing.databaseDigest == snapshot.databaseDigest &&
            WebDavSyncCodec.canonicalJson(existing.profileMap) ==
                WebDavSyncCodec.canonicalJson(snapshot.profileMap) &&
            WebDavSyncCodec.canonicalJson(existing.resourceMap) ==
                WebDavSyncCodec.canonicalJson(snapshot.resourceMap) &&
            existing.size == await encrypted.length() &&
            existing.contentHash == await TransferIo.hashFile(encrypted)) {
          descriptor = existing;
        }
      } on FormatException {
        // An interrupted/corrupt journal cannot authorize reuse.
      }
    }
    if (descriptor == null) {
      if (await receipt.exists()) await receipt.delete();
      if (await encrypted.exists()) await encrypted.delete();
      final sealed = await StreamingEncryptedFile.encrypt(
        source: snapshot.archive,
        destination: encrypted,
        compress: true,
        context: _context(circleId),
        key: key.secretKey,
      );
      _record('sealed', elapsedMs: sealed.elapsedMs, bytes: sealed.bytes);
      descriptor = WebDavSyncSnapshotDescriptor(
        contentHash: sealed.sha256Hex,
        size: sealed.bytes,
        semanticDigest: snapshot.semanticDigest,
        databaseDigest: snapshot.databaseDigest,
        profileMap: snapshot.profileMap,
        resourceMap: snapshot.resourceMap,
      );
      final temporary = File('${journal.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(descriptor.toJson()),
        flush: true,
      );
      await temporary.rename(journal.path);
    }
    // The encrypted object is durable before its plaintext staging is freed.
    await snapshot.dispose();
    WebDavExistenceResult? remote;
    try {
      remote = await objects.probeSharedObject(descriptor.contentHash);
    } on WebDavException catch (error) {
      if (error.statusCode != 405 && error.statusCode != 501) rethrow;
    }
    final etag = remote?.metadata.etag;
    if (remote?.exists == true &&
        etag != null &&
        !etag.startsWith('W/') &&
        await receipt.exists() &&
        await receipt.length() <= 8192) {
      try {
        final verified = jsonDecode(await receipt.readAsString());
        if (verified is Map &&
            verified['hash'] == descriptor.contentHash &&
            verified['etag'] == etag) {
          _record(
            'reused',
            elapsedMs: watch.elapsedMilliseconds,
            bytes: descriptor.size,
          );
          return descriptor;
        }
      } on FormatException {
        /* A bad receipt must be re-verified. */
      }
    }
    WebDavException? writeFailure;
    StackTrace? writeStack;
    try {
      if (remote?.exists != true) {
        await objects.writeSharedObject(
          descriptor.contentHash,
          encrypted,
          maxBytes: descriptor.size,
        );
      }
    } on WebDavException catch (error, stack) {
      writeFailure = error;
      writeStack = stack;
    }
    final readBack = File(
      '${directory.path}/readback-${descriptor.contentHash}.part',
    );
    var verifiedRead = false;
    try {
      final downloaded = await objects.readSharedObject(
        descriptor.contentHash,
        readBack,
        maxBytes: descriptor.size,
      );
      if (downloaded.bytesWritten != descriptor.size ||
          (downloaded.sha256Hex ?? await TransferIo.hashFile(readBack)) !=
              descriptor.contentHash) {
        throw const FormatException(
          'WebDAV sync snapshot read-back does not match',
        );
      }
      verifiedRead = true;
      final verifiedEtag = downloaded.metadata.etag;
      if (verifiedEtag != null && !verifiedEtag.startsWith('W/')) {
        await receipt.writeAsString(
          jsonEncode({'hash': descriptor.contentHash, 'etag': verifiedEtag}),
          flush: true,
        );
      }
    } catch (_) {
      if (writeFailure != null) {
        Error.throwWithStackTrace(writeFailure, writeStack!);
      }
      rethrow;
    } finally {
      if (verifiedRead && await readBack.exists()) await readBack.delete();
    }
    _record(
      'published',
      elapsedMs: watch.elapsedMilliseconds,
      bytes: descriptor.size,
    );
    return descriptor;
  });

  Future<LocalBackupRestoreStage> read({
    required WebDavSyncTransport transport,
    required WebDavSyncCircleKey key,
    required String circleId,
    required WebDavSyncSnapshotDescriptor descriptor,
    LocalBackupCancellation? cancellation,
  }) => _largeTransfer.synchronized(() async {
    final watch = Stopwatch()..start();
    if (transport is! WebDavSyncSharedObjectTransport) {
      throw StateError('WebDAV sync requires shared file-object transport');
    }
    final objects = transport as WebDavSyncSharedObjectTransport;
    final directory = await _cache(circleId, key);
    final encrypted = File(
      '${directory.path}/incoming-${descriptor.contentHash}.enc',
    );
    await _prune(directory, keep: {encrypted.path, '${encrypted.path}.part'});
    cancellation?.throwIfCancelled();
    final cached =
        await encrypted.exists() &&
        await encrypted.length() == descriptor.size &&
        await TransferIo.hashFile(encrypted) == descriptor.contentHash;
    if (!cached) {
      final incoming = File('${encrypted.path}.part');
      {
        final downloaded = await objects.readSharedObject(
          descriptor.contentHash,
          incoming,
          maxBytes: descriptor.size,
          checkCancelled: cancellation?.throwIfCancelled,
        );
        if (downloaded.bytesWritten != descriptor.size ||
            (downloaded.sha256Hex ?? await TransferIo.hashFile(incoming)) !=
                descriptor.contentHash) {
          throw const FormatException('WebDAV sync snapshot content mismatch');
        }
        await incoming.rename(encrypted.path);
      }
    }
    final staging = await LocalBackupScratch.create('sync-restore');
    final archive = File('${staging.path}/snapshot.debrify');
    try {
      await StreamingEncryptedFile.decrypt(
        source: encrypted,
        destination: archive,
        context: _context(circleId),
        key: key.secretKey,
        cancellation: cancellation,
      );
      final inspection = await LocalBackupRestorer.inspect(archive);
      if (inspection.manifest.webDavSync != null) {
        throw const FormatException(
          'Sync snapshot contains device connection state',
        );
      }
      final restored = await LocalBackupRestorer.stage(
        archive: archive,
        staging: staging,
        inspection: inspection,
        lazyAttachments: true,
        cancellation: cancellation,
      );
      await archive.delete();
      _record(
        'staged',
        elapsedMs: watch.elapsedMilliseconds,
        bytes: descriptor.size,
      );
      return restored;
    } catch (_) {
      await LocalBackupScratch.delete(staging);
      rethrow;
    }
  });

  static void _record(
    String event, {
    required int elapsedMs,
    required int bytes,
  }) {
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_snapshot',
      event: event,
      fields: {
        'elapsedMs': elapsedMs,
        'bytes': bytes,
        'peakResidentBytes': ProcessInfo.maxRss,
      },
    );
  }

  // Retry caches are expendable. Retain at most two recent large files and
  // 512 MiB of inactive data; a single active transfer may exceed that budget.
  static Future<void> _prune(
    Directory directory, {
    required Set<String> keep,
  }) async {
    final files = <({File file, FileStat stat})>[];
    // Budget all circles together. The shared transfer lock ensures no
    // sibling circle has an active snapshot or codec scratch directory here.
    await for (final circle in directory.parent.list(followLinks: false)) {
      if (circle is! Directory) continue;
      await for (final entity in circle.list(followLinks: false)) {
        if (entity is Directory &&
            entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith('.stream-codec-')) {
          try {
            await entity.delete(recursive: true);
          } on FileSystemException {
            /* Retry later. */
          }
        } else if (entity is File && !keep.contains(entity.path)) {
          files.add((file: entity, stat: await entity.stat()));
        }
      }
    }
    files.sort((a, b) => b.stat.modified.compareTo(a.stat.modified));
    var bytes = 0;
    var largeFiles = 0;
    final oldest = DateTime.now().subtract(const Duration(days: 7));
    for (final item in files) {
      bytes += item.stat.size;
      if (item.file.path.endsWith('.enc') || item.file.path.endsWith('.part')) {
        largeFiles++;
      }
      if (bytes > 512 * 1024 * 1024 ||
          largeFiles > 2 ||
          item.stat.modified.isBefore(oldest)) {
        try {
          await item.file.delete();
        } on FileSystemException {
          /* Retry later. */
        }
      }
    }
  }

  static Future<Directory> _cache(
    String circleId,
    WebDavSyncCircleKey key,
  ) async {
    final root = await AppStorage.support();
    final keyHash = sha256.convert(await key.secretKey.extractBytes());
    final id = sha256.convert(utf8.encode('$circleId:$keyHash'));
    final directory = Directory('${root.path}/webdav-sync/object-cache/$id');
    await directory.create(recursive: true);
    return directory;
  }
}
