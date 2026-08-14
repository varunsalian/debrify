import 'dart:io';

import 'package:path/path.dart' as p;

import '../../models/profiles/profile_avatar.dart';
import '../../utils/app_storage.dart';
import 'profile_scope.dart';

/// Resolves where a profile's avatar files live.
///
/// Deliberately keyed by profile ID rather than [ProfileScope], for two
/// reasons:
///
/// 1. **Avatars sit outside the data generation.** `ProfileScope` paths are
///    `profiles/<id>/g/<n>/…`, and restore, reset and *engine assignment* all
///    publish a new generation. Since `avatar_key` lives on the profile row and
///    is not generation-scoped, an in-generation file would be orphaned by an
///    unrelated engine edit and the avatar would silently revert to an icon.
///    These paths are `profiles/<id>/avatars/…` — a sibling of `g/`, so the
///    file's lifetime matches the key that points at it.
/// 2. **The gate has IDs, not scopes.** It renders avatars for profiles nobody
///    has entered yet, so a scope-based API could not serve it.
///
/// Profile *deletion* already covers these files:
/// `ProfileDataGenerationManager.deleteAllProfileData` removes the whole
/// `profiles/<id>` tree. Generation deletion deliberately does not — that is
/// the entire point of storing them here.
class ProfileAvatarStorage {
  ProfileAvatarStorage._();

  static Directory directoryIn(Directory root, String profileId) {
    if (!ProfileScope.isValidProfileId(profileId)) {
      throw ArgumentError.value(profileId, 'profileId', 'Unsafe profile ID');
    }
    return Directory(
      p.join(root.path, 'profiles', profileId, ProfileAvatar.directory),
    );
  }

  /// The file a `file:` avatar names. Throws for any other kind — callers must
  /// branch on [ProfileAvatar.kind] first, since art and icons have no file.
  static File fileIn(Directory root, String profileId, ProfileAvatar avatar) {
    if (avatar.kind != ProfileAvatarKind.image) {
      throw ArgumentError.value(avatar, 'avatar', 'Not a file-backed avatar');
    }
    // `avatar.id` is `avatars/<name>`, already validated by ProfileAvatar; the
    // directory prefix is re-derived here rather than trusted from the key.
    final name = p.posix.basename(avatar.id);
    return File(p.join(directoryIn(root, profileId).path, name));
  }

  static Future<Directory> directoryFor(String profileId) async =>
      directoryIn(await AppStorage.documents(), profileId);

  static Future<File> fileFor(String profileId, ProfileAvatar avatar) async =>
      fileIn(await AppStorage.documents(), profileId, avatar);

  /// The readable file for [avatar], or null when there is nothing to read —
  /// a non-file kind, or a file that is simply absent. Absence is an ordinary
  /// state: a package restored on tvOS keeps its key without materialising the
  /// file, and on any platform a file can be removed underneath us. Callers
  /// fall back to the avatar's colour and the profile's initial.
  static Future<File?> resolveExisting(
    String profileId,
    ProfileAvatar? avatar,
  ) async {
    if (avatar == null || avatar.kind != ProfileAvatarKind.image) return null;
    final file = await fileFor(profileId, avatar);
    return await file.exists() ? file : null;
  }

  /// Removes every avatar a profile owns. Profile deletion does not need this
  /// (see above); it exists for targeted cleanup.
  static Future<void> deleteAll(String profileId) async {
    final directory = await directoryFor(profileId);
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }

  /// Deletes every avatar this profile owns except [keep]. Replacement has to
  /// remove the previous file, or the directory grows without bound as a user
  /// tries different pictures.
  static Future<void> pruneExcept(String profileId, ProfileAvatar keep) async {
    final directory = await directoryFor(profileId);
    if (!await directory.exists()) return;
    final survivor = p.canonicalize((await fileFor(profileId, keep)).path);
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      if (p.canonicalize(entity.path) == survivor) continue;
      await entity.delete();
    }
  }

  /// Deletes a candidate written before its profile key committed. The
  /// content-addressed candidate can equal the previous avatar, in which case
  /// deleting it would recreate the failed-save data-loss bug.
  static Future<void> deleteCandidate(
    String profileId,
    ProfileAvatar candidate, {
    ProfileAvatar? preserve,
  }) async {
    if (candidate.kind != ProfileAvatarKind.image ||
        (preserve?.kind == ProfileAvatarKind.image &&
            preserve!.id == candidate.id)) {
      return;
    }
    final file = await fileFor(profileId, candidate);
    if (await file.exists()) await file.delete();
    final directory = await directoryFor(profileId);
    if (await directory.exists() && await directory.list().isEmpty) {
      await directory.delete();
    }
  }

  /// Removes interrupted same-directory candidate writes. Final avatar names
  /// never use this suffix, so cleanup cannot remove a committed selection.
  static Future<void> cleanupTemporary(String profileId) async {
    final directory = await directoryFor(profileId);
    if (!await directory.exists()) return;
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.candidate.tmp')) {
        await entity.delete();
      }
    }
    if (await directory.exists() && await directory.list().isEmpty) {
      await directory.delete();
    }
  }
}
