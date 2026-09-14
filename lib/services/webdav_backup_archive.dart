import 'dart:io';

import 'diagnostic_log.dart';
import 'profiles/local_backup/local_backup_archive.dart';
import 'profiles/profile_authorization.dart';
import 'transfer/streaming_encrypted_file.dart';
import 'webdav_sync/webdav_sync_backup.dart';

final class WebDavArchiveExport {
  const WebDavArchiveExport({
    required this.file,
    required this.transfer,
    required this.cachesPruned,
  });
  final File file;
  final StreamingFileResult transfer;
  final bool cachesPruned;
}

/// WebDAV uses the same file-backed snapshot and restore format as local
/// backups, wrapped in bounded authenticated encryption for remote storage.
final class WebDavBackupArchive {
  const WebDavBackupArchive(this.exporter);
  final LocalBackupExporter exporter;
  static const String encryptionContext = 'debrify/manual-backup/v2';

  Future<WebDavArchiveExport> export({
    required ProfileAuthorizationContext context,
    required Directory staging,
    required String passphrase,
    LocalBackupStageCallback? onStage,
    LocalBackupByteProgress? onBytes,
    LocalBackupCancellation? cancellation,
    Future<WebDavSyncBackup?> Function(
      Map<String, String>,
      Map<String, String>,
    )?
    captureSync,
  }) async {
    final snapshotWatch = Stopwatch()..start();
    final snapshot = await _snapshot(
      context: context,
      staging: staging,
      onStage: onStage,
      onBytes: onBytes,
      cancellation: cancellation,
      captureSync: captureSync,
    );
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_backup',
      event: 'snapshot_prepared',
      fields: {
        'elapsedMs': snapshotWatch.elapsedMilliseconds,
        'archiveBytes': await snapshot.file.length(),
        'peakResidentBytes': ProcessInfo.maxRss,
      },
    );
    final encrypted = File('${snapshot.file.path}.enc');
    onStage?.call('Encrypting backup…');
    final transfer = await StreamingEncryptedFile.encrypt(
      source: snapshot.file,
      destination: encrypted,
      compress: true,
      context: encryptionContext,
      passphrase: passphrase,
      cancellation: cancellation,
      onProgress: (done, total) => onBytes?.call('backup', done, total),
    );
    // The encrypted file is now complete. Release the plaintext archive's
    // disk space before the network transfer and verification download.
    await snapshot.file.delete();
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_backup',
      event: 'sealed',
      fields: {
        'bytes': transfer.bytes,
        'elapsedMs': transfer.elapsedMs,
        'peakResidentBytes': transfer.peakResidentBytes,
      },
    );
    return WebDavArchiveExport(
      file: encrypted,
      transfer: transfer,
      cachesPruned: snapshot.cachesPruned,
    );
  }

  /// Return file metadata only so the exported profile graph can be collected
  /// before encryption starts.
  Future<({File file, bool cachesPruned})> _snapshot({
    required ProfileAuthorizationContext context,
    required Directory staging,
    required LocalBackupStageCallback? onStage,
    required LocalBackupByteProgress? onBytes,
    required LocalBackupCancellation? cancellation,
    required Future<WebDavSyncBackup?> Function(
      Map<String, String>,
      Map<String, String>,
    )?
    captureSync,
  }) async {
    final exported = await exporter.export(
      context: context,
      staging: staging,
      allProfiles: true,
      separateMetadata: true,
      onStage: onStage,
      onBytes: onBytes,
      cancellation: cancellation,
      captureSync: captureSync,
    );
    return (file: exported.archive, cachesPruned: exported.cachesPruned);
  }

  static Future<StreamingFileResult> decrypt({
    required File source,
    required File destination,
    required String passphrase,
    LocalBackupCancellation? cancellation,
    LocalBackupByteProgress? onBytes,
  }) async {
    final transfer = await StreamingEncryptedFile.decrypt(
      source: source,
      destination: destination,
      context: encryptionContext,
      passphrase: passphrase,
      cancellation: cancellation,
      onProgress: (done, total) => onBytes?.call('backup', done, total),
    );
    DiagnosticLog.instance.recordEvent(
      source: 'webdav_backup',
      event: 'opened',
      fields: {
        'bytes': transfer.bytes,
        'elapsedMs': transfer.elapsedMs,
        'peakResidentBytes': transfer.peakResidentBytes,
      },
    );
    return transfer;
  }
}
