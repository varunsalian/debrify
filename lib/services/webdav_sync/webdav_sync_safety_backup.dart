import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../utils/app_storage.dart';
import '../profiles/portable_profile_package.dart';
import '../profiles/profile_authorization.dart';
import '../profiles/profile_package_service.dart';
import 'webdav_sync_graph_omissions.dart';

final class WebDavSyncSafetyBackup {
  const WebDavSyncSafetyBackup({required this.path, required this.sha256Hex});

  final String path;
  final String sha256Hex;
}

abstract interface class WebDavSyncSafetyBackupSource {
  Future<PortableProfilePackage> export(
    ProfileAuthorizationContext authorization,
  );

  Future<void> revalidate(ProfileAuthorizationContext authorization);
}

final class DefaultWebDavSyncSafetyBackupSource
    implements WebDavSyncSafetyBackupSource {
  const DefaultWebDavSyncSafetyBackupSource(this.packageService);

  final ProfilePackageService packageService;

  @override
  Future<PortableProfilePackage> export(
    ProfileAuthorizationContext authorization,
  ) => packageService.exportAllProfiles(
    context: authorization,
    includeSecrets: true,
    compactDatabaseSnapshots: false,
    includeDatabases: true,
    includePreferences: true,
  );

  @override
  Future<void> revalidate(ProfileAuthorizationContext authorization) async {
    await authorization.validate(packageService.registry);
  }
}

typedef WebDavSyncBackupDirectoryProvider = Future<Directory> Function();
typedef WebDavSyncBackupEncoder =
    Future<Uint8List> Function(
      PortableProfilePackage package,
      String passphrase,
    );
typedef WebDavSyncBackupDecoder =
    Future<PortableProfilePackage> Function(String path, String passphrase);

abstract interface class WebDavSyncSafetyBackupStore {
  Future<WebDavSyncSafetyBackup> createVerified({
    required String adoptionId,
    required String passphrase,
    required ProfileAuthorizationContext authorization,
  });

  Future<bool> verifyRetained(WebDavSyncSafetyBackup backup);
}

/// Writes a retained, encrypted local recovery point before CircleAdoption
/// mutates a profile. The final file is atomically published and then read and
/// decrypted again; a merely successful write is never considered verified.
/// Oversized databases may use the same explicitly bounded cache/TV omission
/// policy as a sync bootstrap, while every unknown omission remains fatal.
final class LocalWebDavSyncSafetyBackupStore
    implements WebDavSyncSafetyBackupStore {
  LocalWebDavSyncSafetyBackupStore({
    required WebDavSyncSafetyBackupSource source,
    WebDavSyncBackupDirectoryProvider? directoryProvider,
    WebDavSyncBackupEncoder? encoder,
    WebDavSyncBackupDecoder? decoder,
  }) : _source = source,
       _directoryProvider = directoryProvider ?? AppStorage.support,
       _encoder = encoder ?? PortableProfilePackage.encodeEncryptedBytes,
       _decoder = decoder ?? PortableProfilePackage.decryptFile;

  final WebDavSyncSafetyBackupSource _source;
  final WebDavSyncBackupDirectoryProvider _directoryProvider;
  final WebDavSyncBackupEncoder _encoder;
  final WebDavSyncBackupDecoder _decoder;

  @override
  Future<WebDavSyncSafetyBackup> createVerified({
    required String adoptionId,
    required String passphrase,
    required ProfileAuthorizationContext authorization,
  }) async {
    if (!_safeId.hasMatch(adoptionId)) {
      throw ArgumentError.value(adoptionId, 'adoptionId');
    }
    final base = await _directoryProvider();
    final directory = Directory(
      p.join(base.path, 'webdav-sync', 'pre-join-backups'),
    );
    await directory.create(recursive: true);
    final destination = File(p.join(directory.path, '$adoptionId.json'));
    if (await destination.exists()) {
      final verified = await _verifyExisting(destination, passphrase);
      await _pruneHistoricalBackups(directory, keepPath: destination.path);
      return verified;
    }

    final temporary = File(p.join(directory.path, '.$adoptionId.tmp'));
    var published = false;
    try {
      final package = await _source.export(authorization);
      _requireRecoverableGraph(package);
      final encoded = await _encoder(package, passphrase);
      await temporary.writeAsBytes(encoded, flush: true);
      await _source.revalidate(authorization);
      await temporary.rename(destination.path);
      published = true;
      final verified = await _verifyExisting(destination, passphrase);
      await _pruneHistoricalBackups(directory, keepPath: destination.path);
      return verified;
    } catch (_) {
      // A published but unverifiable recovery point is retained as evidence;
      // adoption will fail and a later attempt can inspect or replace it under
      // a fresh adoption ID. Only unpublished scratch belongs to this call.
      if (!published) {
        try {
          if (await temporary.exists()) await temporary.delete();
        } catch (_) {
          // Preserve the export/write/authorization failure. The encrypted
          // scratch is never treated as a verified recovery point and a later
          // attempt removes it before writing.
        }
      }
      rethrow;
    }
  }

  Future<WebDavSyncSafetyBackup> _verifyExisting(
    File file,
    String passphrase,
  ) async {
    final decoded = await _decoder(file.path, passphrase);
    _requireRecoverableGraph(decoded);
    final digest = await sha256.bind(file.openRead()).first;
    return WebDavSyncSafetyBackup(
      path: file.path,
      sha256Hex: digest.toString(),
    );
  }

  @override
  Future<bool> verifyRetained(WebDavSyncSafetyBackup backup) async {
    try {
      final file = File(backup.path);
      if (!await file.exists()) return false;
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == backup.sha256Hex;
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _pruneHistoricalBackups(
    Directory directory, {
    required String keepPath,
  }) async {
    const retainedCount = 3;
    try {
      final candidates = <({File file, DateTime modified})>[];
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is! File ||
            !entity.path.endsWith('.json') ||
            entity.path == keepPath) {
          continue;
        }
        candidates.add((file: entity, modified: await entity.lastModified()));
      }
      candidates.sort((left, right) => right.modified.compareTo(left.modified));
      for (final candidate in candidates.skip(retainedCount - 1)) {
        await candidate.file.delete();
      }
    } on FileSystemException {
      // Retention cleanup is best effort; never invalidate a newly verified
      // recovery point because an older file could not be inspected/deleted.
    }
  }

  static void _requireRecoverableGraph(PortableProfilePackage package) {
    if (package.mode != 'deviceGraph' ||
        package.profiles.isEmpty ||
        package.profiles.any(
          (profile) =>
              profile['preferencesSection'] is! String ||
              !package.sections.containsKey(profile['preferencesSection']),
        )) {
      throw const FormatException(
        'WebDAV sync safety backup is not a recoverable device graph',
      );
    }
    WebDavSyncGraphOmissionPolicy.requireSupported(package);
  }
}

final RegExp _safeId = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$');
