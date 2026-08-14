import 'dart:io';

import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/services/profiles/profile_avatar_storage.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('profile-avatar-storage-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('avatars live beside the generations, never inside one', () {
    final directory = ProfileAvatarStorage.directoryIn(root, 'admin-v1');
    expect(
      p.split(directory.path),
      containsAllInOrder(<String>['profiles', 'admin-v1', 'avatars']),
    );

    // The regression this guards: a generation bump (restore, reset, or an
    // engine assignment) must not move or orphan the file.
    final scope = ProfileScope(
      profileId: 'admin-v1',
      dataGeneration: 7,
      sessionEpoch: 1,
    );
    expect(directory.path, isNot(contains(p.join('g', '7'))));
    expect(
      directory.path,
      isNot(startsWith(scope.generationDirectory(root).path)),
    );
  });

  test('two generations of the same profile resolve to one avatar file', () {
    final avatar = ProfileAvatar.image('avatars/a1b2.gif');
    final first = ProfileAvatarStorage.fileIn(root, 'admin-v1', avatar);
    final second = ProfileAvatarStorage.fileIn(root, 'admin-v1', avatar);
    expect(first.path, second.path);
    expect(p.basename(first.path), 'a1b2.gif');
  });

  test('different profiles never share a directory', () {
    expect(
      ProfileAvatarStorage.directoryIn(root, 'a').path,
      isNot(ProfileAvatarStorage.directoryIn(root, 'b').path),
    );
  });

  test('an unsafe profile ID cannot build a path', () {
    expect(
      () => ProfileAvatarStorage.directoryIn(root, '../escape'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('non-file avatars have no file to resolve', () {
    for (final avatar in <ProfileAvatar>[
      const ProfileAvatar.icon('person'),
      const ProfileAvatar.art('aurora'),
    ]) {
      expect(
        () => ProfileAvatarStorage.fileIn(root, 'admin-v1', avatar),
        throwsA(isA<ArgumentError>()),
        reason: '$avatar',
      );
    }
  });

  test('the resolved file stays inside the profile avatars directory', () {
    final avatar = ProfileAvatar.image('avatars/a1b2.png');
    final file = ProfileAvatarStorage.fileIn(root, 'admin-v1', avatar);
    final directory = ProfileAvatarStorage.directoryIn(root, 'admin-v1');
    expect(p.canonicalize(file.parent.path), p.canonicalize(directory.path));
  });

  // Avatars sit outside the generation on purpose, which means they rely on
  // whole-profile deletion to clean up. If `deleteAllProfileData` is ever
  // narrowed to generations, avatar files start leaking — pin the coupling.
  test('avatars sit under the tree whole-profile deletion removes', () {
    final avatars = ProfileAvatarStorage.directoryIn(root, 'admin-v1');
    final profileRoot = p.join(root.absolute.path, 'profiles', 'admin-v1');
    expect(
      p.canonicalize(avatars.path),
      startsWith(p.canonicalize(profileRoot)),
    );
  });

  group('pruneExcept', () {
    Future<File> write(String name) async {
      final directory = ProfileAvatarStorage.directoryIn(root, 'admin-v1');
      await directory.create(recursive: true);
      final file = File(p.join(directory.path, name));
      await file.writeAsBytes(<int>[1], flush: true);
      return file;
    }

    test('replacing an avatar leaves exactly one file behind', () async {
      AppStorage.debugOverride(documents: root);
      addTearDown(AppStorage.debugReset);

      final old = await write('old.png');
      final replacement = await write('new.gif');

      await ProfileAvatarStorage.pruneExcept(
        'admin-v1',
        ProfileAvatar.image('avatars/new.gif'),
      );

      expect(await old.exists(), isFalse);
      expect(await replacement.exists(), isTrue);
    });
  });
}
