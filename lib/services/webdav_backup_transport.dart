import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/profiles/profile_policy.dart';
import '../models/webdav_item.dart';
import 'profiles/portable_profile_package.dart';
import 'webdav_protocol_client.dart';
import 'webdav_service.dart';

final class WebDavBackupUploadResult {
  const WebDavBackupUploadResult({
    required this.remotePath,
    required this.fileName,
    required this.metadata,
    required this.sha256Hex,
  });

  final String remotePath;
  final String fileName;
  final WebDavResponseMetadata metadata;
  final String sha256Hex;
}

final class WebDavBackupVerificationException implements Exception {
  const WebDavBackupVerificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Manual backup transport used by the Migrate UI.
///
/// Uploads are create-only, collision retries are bounded, and success is not
/// reported until a streamed read-back has the same SHA-256 as the staged
/// local envelope. A hash mismatch deletes the remote object only when the
/// server explicitly returned 201, which proves this operation created it;
/// transient read-back failures leave the uploaded object intact.
final class WebDavBackupTransport {
  WebDavBackupTransport({
    DateTime Function()? now,
    String Function()? randomSuffix,
    this.maxCreateAttempts = 4,
  }) : _now = now ?? DateTime.now,
       _randomSuffix = randomSuffix ?? _secureRandomSuffix;

  final DateTime Function() _now;
  final String Function() _randomSuffix;
  final int maxCreateAttempts;

  Future<WebDavBackupUploadResult> uploadVerified({
    required WebDavConfig config,
    required String directoryPath,
    required File stagedFile,
    required Directory scratchDirectory,
    required String fileNamePrefix,
    Future<void> Function()? beforeSend,
  }) async {
    if (maxCreateAttempts <= 0) {
      throw const WebDavException(
        kind: WebDavErrorKind.invalidRequest,
        message: 'WebDAV backup retry limit is invalid',
      );
    }
    final length = await stagedFile.length();
    if (length > PortableProfilePackage.maxEnvelopeBytes) {
      throw const FormatException('Backup exceeds the supported size limit');
    }
    final localHash = await sha256File(stagedFile);

    WebDavException? lastCollision;
    for (var attempt = 0; attempt < maxCreateAttempts; attempt++) {
      final fileName = _buildFileName(fileNamePrefix);
      final remotePath = _joinRemotePath(directoryPath, fileName);
      late final WebDavResponseMetadata uploaded;
      try {
        uploaded = await WebDavService.uploadFile(
          config: config,
          path: remotePath,
          file: stagedFile,
          maxBytes: PortableProfilePackage.maxEnvelopeBytes,
          contentType: 'application/json',
          ifNoneMatch: '*',
          feature: ProfileFeature.backupRestore,
          beforeSend: beforeSend,
        );
      } on WebDavException catch (error) {
        if (error.kind == WebDavErrorKind.preconditionFailed) {
          lastCollision = error;
          continue;
        }
        rethrow;
      }

      final verificationFile = File(
        '${scratchDirectory.path}${Platform.pathSeparator}'
        'webdav-readback-$attempt-${_randomSuffix()}.json',
      );
      try {
        if (uploaded.statusCode != HttpStatus.created) {
          throw WebDavBackupVerificationException(
            'WebDAV did not confirm a create-only backup upload '
            '(status ${uploaded.statusCode})',
          );
        }
        late final String remoteHash;
        try {
          await WebDavService.downloadToFile(
            config: config,
            path: remotePath,
            destination: verificationFile,
            maxBytes: PortableProfilePackage.maxEnvelopeBytes,
            feature: ProfileFeature.backupRestore,
            beforeSend: beforeSend,
          );
          remoteHash = await sha256File(verificationFile);
        } catch (error) {
          throw WebDavBackupVerificationException(
            'The backup was uploaded to "$remotePath", but its read-back '
            'could not be verified. The remote file was left intact; verify '
            'or delete it manually. Details: $error',
          );
        }
        if (remoteHash != localHash) {
          await _deleteOwnedCreation(
            config: config,
            path: remotePath,
            beforeSend: beforeSend,
          );
          throw const WebDavBackupVerificationException(
            'WebDAV read-back did not match the uploaded backup',
          );
        }
        return WebDavBackupUploadResult(
          remotePath: remotePath,
          fileName: fileName,
          metadata: uploaded,
          sha256Hex: localHash,
        );
      } finally {
        if (await verificationFile.exists()) {
          await verificationFile.delete();
        }
      }
    }
    throw lastCollision ??
        const WebDavException(
          kind: WebDavErrorKind.preconditionFailed,
          message: 'Could not reserve a unique WebDAV backup name',
        );
  }

  static Future<String> sha256File(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<void> _deleteOwnedCreation({
    required WebDavConfig config,
    required String path,
    required Future<void> Function()? beforeSend,
  }) async {
    try {
      await WebDavService.delete(
        config: config,
        item: WebDavItem(
          name: path.split('/').last,
          path: path,
          isDirectory: false,
        ),
        feature: ProfileFeature.backupRestore,
        beforeSend: beforeSend,
      );
    } catch (_) {
      // Best effort. Verification still fails loudly; a failed cleanup must
      // never hide the primary integrity error.
    }
  }

  String _buildFileName(String prefix) {
    final stamp = _now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return '$prefix-$stamp-${_randomSuffix()}.json';
  }

  static String _joinRemotePath(String directory, String name) {
    final normalized = directory.trim().replaceAll(RegExp(r'^/+|/+$'), '');
    return normalized.isEmpty ? name : '$normalized/$name';
  }

  static String _secureRandomSuffix() {
    final random = Random.secure();
    final bytes = List<int>.generate(6, (_) => random.nextInt(256));
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }
}
