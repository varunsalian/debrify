import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

import '../../models/profiles/profile_avatar.dart';
import '../../utils/app_storage.dart';
import 'profile_avatar_ingest.dart';
import 'profile_avatar_policy.dart';
import 'profile_avatar_storage.dart';
import 'profile_scope.dart';

/// Allowlisted portable files. Device assets, caches, executable paths, OS
/// grants, downloads, and recordings deliberately never enter this codec.
class ProfilePortableFiles {
  ProfilePortableFiles._();

  static const int maxFileBytes = 4 * 1024 * 1024;
  static const int maxTotalBytes = 64 * 1024 * 1024;

  /// Exports only the legacy-compatible engine tree.
  ///
  /// Avatar bytes deliberately live in the profile record's optional
  /// `avatarFile` attachment (see [exportAvatar]). Previous builds validate
  /// every `filesSection` key against the `engines/` grammar and abort the
  /// whole import on an avatar path; they safely ignore an unknown profile
  /// field, so separating the attachment is the compatibility boundary.
  static Future<Map<String, Object?>> export(ProfileScope scope) async {
    final root = await AppStorage.documents();
    final documents = scope.storageDirectory(root, 'documents');
    final engines = Directory(p.join(documents.path, 'engines'));
    if (!await engines.exists()) return const <String, Object?>{};
    final result = <String, Object?>{};
    var total = 0;
    await for (final entity in engines.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is Link) throw StateError('Portable files contain a symlink');
      if (entity is! File) continue;
      final relative = p
          .relative(entity.path, from: documents.path)
          .replaceAll(r'\', '/');
      if (!_allowedEngine(relative)) continue;
      final length = await entity.length();
      total += length;
      if (length > maxFileBytes || total > maxTotalBytes) {
        throw StateError('Portable profile files exceed the backup limit');
      }
      final bytes = await entity.readAsBytes();
      result[relative] = await _attachment(bytes);
    }
    return result;
  }

  /// Exports exactly the file referenced by [avatarKey], never a directory
  /// sweep. Stale photos therefore neither leak into backups nor consume the
  /// package budget.
  static Future<Map<String, Object?>?> exportAvatar(
    ProfileScope scope,
    String? avatarKey,
  ) async {
    if (!ProfileAvatarPolicy.userImagesSupported) return null;
    final avatar = ProfileAvatar.tryParse(avatarKey);
    if (avatar?.kind != ProfileAvatarKind.image) return null;
    final file = await ProfileAvatarStorage.resolveExisting(
      scope.profileId,
      avatar,
    );
    if (file == null) return null;
    final length = await file.length();
    if (length > ProfileAvatarIngest.maxBytes) {
      throw StateError('Portable avatar exceeds the backup limit');
    }
    final bytes = await file.readAsBytes();
    await ProfileAvatarIngest.validateStored(
      relativePath: avatar!.id,
      bytes: bytes,
    );
    return <String, Object?>{'path': avatar.id, ...await _attachment(bytes)};
  }

  static Future<int> restore(
    ProfileScope scope,
    Map<Object?, Object?> attachments,
  ) async {
    final root = await AppStorage.documents();
    var total = 0;
    var restored = 0;
    for (final entry in attachments.entries) {
      final relative = entry.key;
      final record = entry.value;
      if (relative is! String || !_allowedEngine(relative) || record is! Map) {
        throw const FormatException('Invalid portable profile file');
      }
      final bytes = await _decodeAttachment(record, maxBytes: maxFileBytes);
      total += bytes.length;
      if (total > maxTotalBytes) {
        throw const FormatException('Portable profile file size mismatch');
      }
      final destination = scope.fileIn(
        root,
        'documents',
        p.joinAll(relative.split('/')),
      );
      await destination.parent.create(recursive: true);
      final temp = File('${destination.path}.restore.tmp');
      if (await temp.exists()) await temp.delete();
      try {
        await temp.writeAsBytes(bytes, flush: true);
        if (await destination.exists()) await destination.delete();
        await temp.rename(destination.path);
        restored++;
      } finally {
        if (await temp.exists()) await temp.delete();
      }
    }
    return restored;
  }

  /// Validates an optional profile-record avatar and writes it only to the
  /// staged generation. [ProfilePortableAvatarStage.install] is the explicit
  /// pre-publication commit; rollback can therefore remove every live write.
  static Future<ProfilePortableAvatarStage?> stageAvatar({
    required ProfileScope scope,
    required Object? record,
    required String? expectedAvatarKey,
    required String operationId,
  }) async {
    if (record == null) return null;
    final expected = ProfileAvatar.tryParse(expectedAvatarKey);
    if (expected?.kind != ProfileAvatarKind.image ||
        record is! Map ||
        record['path'] != expected!.id ||
        !ProfileScope.isValidProfileId(operationId)) {
      throw const FormatException('Invalid portable avatar attachment');
    }
    final bytes = await _decodeAttachment(
      record,
      maxBytes: ProfileAvatarIngest.maxBytes,
    );
    await ProfileAvatarIngest.validateStored(
      relativePath: expected.id,
      bytes: bytes,
    );
    if (!ProfileAvatarPolicy.userImagesSupported) return null;

    final root = await AppStorage.documents();
    final stagingDirectory = Directory(
      p.join(
        scope.storageDirectory(root, 'documents').path,
        '.avatar-restore',
        operationId,
      ),
    );
    final stagedFile = File(
      p.join(stagingDirectory.path, p.posix.basename(expected.id)),
    );
    await stagedFile.parent.create(recursive: true);
    await stagedFile.writeAsBytes(bytes, flush: true);
    return ProfilePortableAvatarStage._(
      profileId: scope.profileId,
      avatar: expected,
      stagedFile: stagedFile,
      stagingDirectory: stagingDirectory,
    );
  }

  static bool _allowedEngine(String relative) {
    final normalized = p.posix.normalize(relative);
    if (p.posix.isAbsolute(normalized) ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized) ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        !normalized.startsWith('engines/')) {
      return false;
    }
    final extension = p.posix.extension(normalized).toLowerCase();
    return extension == '.yaml' || extension == '.yml' || extension == '.json';
  }

  static Future<Map<String, Object?>> _attachment(List<int> bytes) async =>
      <String, Object?>{
        'encoding': 'base64',
        'bytes': bytes.length,
        'sha256': await _hash(bytes),
        'data': base64Encode(bytes),
      };

  static Future<Uint8List> _decodeAttachment(
    Map record, {
    required int maxBytes,
  }) async {
    if (record['encoding'] != 'base64' ||
        record['bytes'] is! num ||
        record['sha256'] is! String ||
        record['data'] is! String) {
      throw const FormatException('Invalid portable file attachment');
    }
    final claimed = (record['bytes'] as num).toInt();
    if (claimed < 0 || claimed > maxBytes) {
      throw const FormatException('Portable profile file exceeds limit');
    }
    final encoded = record['data'] as String;
    if (encoded.length > ((maxBytes + 2) ~/ 3) * 4) {
      throw const FormatException('Encoded portable file exceeds limit');
    }
    late final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      throw const FormatException('Portable file is not valid base64');
    }
    if (bytes.length != claimed || await _hash(bytes) != record['sha256']) {
      throw const FormatException('Portable profile file digest mismatch');
    }
    return bytes;
  }

  static Future<String> _hash(List<int> bytes) async =>
      base64UrlEncode((await Sha256().hash(bytes)).bytes).replaceAll('=', '');
}

/// One validated avatar staged for a restore operation.
class ProfilePortableAvatarStage {
  final String profileId;
  final ProfileAvatar avatar;
  final File stagedFile;
  final Directory stagingDirectory;
  bool _installedNewFile = false;

  ProfilePortableAvatarStage._({
    required this.profileId,
    required this.avatar,
    required this.stagedFile,
    required this.stagingDirectory,
  });

  /// Materializes the candidate immediately before registry publication. A
  /// pre-existing content-addressed destination is left untouched.
  Future<void> install() async {
    final destination = await ProfileAvatarStorage.fileFor(profileId, avatar);
    if (await destination.exists()) return;
    await destination.parent.create(recursive: true);
    final temp = File('${destination.path}.restore.tmp');
    if (await temp.exists()) await temp.delete();
    try {
      await stagedFile.copy(temp.path);
      final handle = await temp.open(mode: FileMode.append);
      try {
        await handle.flush();
      } finally {
        await handle.close();
      }
      await temp.rename(destination.path);
      _installedNewFile = true;
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  /// Removes live bytes created by [install] when publication fails.
  Future<void> rollback() async {
    if (_installedNewFile) {
      final destination = await ProfileAvatarStorage.fileFor(profileId, avatar);
      if (await destination.exists()) await destination.delete();
      _installedNewFile = false;
    }
    await _deleteStaging();
  }

  /// Completes a published restore and prunes every unreferenced old photo.
  Future<void> finish() async {
    await ProfileAvatarIngest.commit(
      profileId: profileId,
      avatarKey: avatar.format(),
    );
    await _deleteStaging();
  }

  Future<void> _deleteStaging() async {
    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }
  }
}
