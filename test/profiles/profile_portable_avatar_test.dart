import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:debrify/models/profiles/profile_avatar.dart';
import 'package:debrify/services/profiles/profile_avatar_policy.dart';
import 'package:debrify/services/profiles/profile_avatar_storage.dart';
import 'package:debrify/services/profiles/profile_portable_files.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'avatar_fixtures.dart';

/// Avatars are the first binary user data a portable package carries. These
/// pin the codec, the profile-root destination, and the tvOS exclusion.
void main() {
  late Directory root;
  final scope = ProfileScope(
    profileId: 'admin-v1',
    dataGeneration: 3,
    sessionEpoch: 1,
  );

  final gifBytes = tinyGif;

  Future<File> writeAvatar(String name, List<int> bytes) async {
    final directory = ProfileAvatarStorage.directoryIn(root, scope.profileId);
    await directory.create(recursive: true);
    final file = File(p.join(directory.path, name));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> writeEngine(String name, String contents) async {
    final engines = Directory(
      p.join(scope.storageDirectory(root, 'documents').path, 'engines'),
    );
    await engines.create(recursive: true);
    final file = File(p.join(engines.path, name));
    await file.writeAsString(contents, flush: true);
    return file;
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('portable-avatar-');
    AppStorage.debugOverride(documents: root);
  });

  tearDown(() async {
    AppStorage.debugReset();
    ProfileAvatarPolicy.debugSetUserImagesSupported(null);
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('an avatar round-trips with its digest intact', () async {
    await writeAvatar('a1b2.gif', gifBytes);
    const key = 'file:avatars/a1b2.gif#4A90D9';
    final exported = await ProfilePortableFiles.exportAvatar(scope, key);

    expect(exported!['path'], 'avatars/a1b2.gif');
    expect(exported['bytes'], gifBytes.length);

    await ProfileAvatarStorage.deleteAll(scope.profileId);
    final stage = await ProfilePortableFiles.stageAvatar(
      scope: scope,
      record: exported,
      expectedAvatarKey: key,
      operationId: 'restore-1',
    );
    await stage!.install();
    await stage.finish();

    final file = await ProfileAvatarStorage.fileFor(
      scope.profileId,
      ProfileAvatar.image('avatars/a1b2.gif'),
    );
    expect(await file.readAsBytes(), gifBytes);
  });

  // The bug the old early-return hid: `if (!engines.exists()) return {}` meant
  // a profile with avatars but no engines exported nothing at all.
  test('a profile with avatars but no engines still exports them', () async {
    await writeAvatar('solo.gif', gifBytes);
    final engines = await ProfilePortableFiles.export(scope);
    final avatar = await ProfilePortableFiles.exportAvatar(
      scope,
      'file:avatars/solo.gif',
    );
    expect(engines, isEmpty);
    expect(avatar?['path'], 'avatars/solo.gif');
  });

  test('a profile with engines but no avatars still exports them', () async {
    await writeEngine('e.yaml', 'name: test');
    final exported = await ProfilePortableFiles.export(scope);
    expect(exported.keys, contains('engines/e.yaml'));
  });

  test('both trees export together', () async {
    await writeAvatar('a.gif', gifBytes);
    await writeEngine('e.json', '{}');
    final engines = await ProfilePortableFiles.export(scope);
    final avatar = await ProfilePortableFiles.exportAvatar(
      scope,
      'file:avatars/a.gif',
    );
    expect(engines.keys, contains('engines/e.json'));
    expect(
      engines.keys.any((key) => key.startsWith('avatars/')),
      isFalse,
      reason: 'old builds reject avatar paths in filesSection',
    );
    expect(avatar?['path'], 'avatars/a.gif');
  });

  test('only the referenced avatar is exported', () async {
    await writeAvatar('current.gif', gifBytes);
    await writeAvatar('removed.gif', gifBytes);
    final avatar = await ProfilePortableFiles.exportAvatar(
      scope,
      'file:avatars/current.gif',
    );
    expect(avatar?['path'], 'avatars/current.gif');
    expect(avatar.toString(), isNot(contains('removed.gif')));
  });

  test('a restored avatar lands outside the data generation', () async {
    await writeAvatar('a1b2.gif', gifBytes);
    const key = 'file:avatars/a1b2.gif#4A90D9';
    final exported = await ProfilePortableFiles.exportAvatar(scope, key);
    await ProfileAvatarStorage.deleteAll(scope.profileId);
    final stage = await ProfilePortableFiles.stageAvatar(
      scope: scope,
      record: exported,
      expectedAvatarKey: key,
      operationId: 'restore-2',
    );
    await stage!.install();
    await stage.finish();

    final file = await ProfileAvatarStorage.fileFor(
      scope.profileId,
      ProfileAvatar.image('avatars/a1b2.gif'),
    );
    expect(await file.exists(), isTrue);
    // A generation bump must not be able to strand it.
    expect(file.path, isNot(startsWith(scope.generationDirectory(root).path)));
    expect(file.path, isNot(contains(p.join('g', '3'))));
  });

  test(
    'a failed publication rolls back its installed avatar candidate',
    () async {
      await writeAvatar('candidate.gif', gifBytes);
      const key = 'file:avatars/candidate.gif';
      final exported = await ProfilePortableFiles.exportAvatar(scope, key);
      await ProfileAvatarStorage.deleteAll(scope.profileId);
      final stage = await ProfilePortableFiles.stageAvatar(
        scope: scope,
        record: exported,
        expectedAvatarKey: key,
        operationId: 'restore-rollback',
      );

      await stage!.install();
      final destination = await ProfileAvatarStorage.fileFor(
        scope.profileId,
        ProfileAvatar.image('avatars/candidate.gif'),
      );
      expect(await destination.exists(), isTrue);

      await stage.rollback();
      expect(await destination.exists(), isFalse);
    },
  );

  group('tvOS keeps no user avatar files', () {
    setUp(() => ProfileAvatarPolicy.debugSetUserImagesSupported(false));

    test('restore skips the avatar but still restores engines', () async {
      ProfileAvatarPolicy.debugSetUserImagesSupported(true);
      await writeAvatar('a1b2.gif', gifBytes);
      await writeEngine('e.yaml', 'name: test');
      const key = 'file:avatars/a1b2.gif';
      final avatarRecord = await ProfilePortableFiles.exportAvatar(scope, key);
      final engines = await ProfilePortableFiles.export(scope);

      await ProfileAvatarStorage.deleteAll(scope.profileId);
      ProfileAvatarPolicy.debugSetUserImagesSupported(false);
      final avatarStage = await ProfilePortableFiles.stageAvatar(
        scope: scope,
        record: avatarRecord,
        expectedAvatarKey: key,
        operationId: 'restore-3',
      );
      final restored = await ProfilePortableFiles.restore(scope, engines);

      expect(avatarStage, isNull);
      expect(restored, 1, reason: 'the engine, and only the engine');
      final avatar = await ProfileAvatarStorage.fileFor(
        scope.profileId,
        ProfileAvatar.image('avatars/a1b2.gif'),
      );
      expect(await avatar.exists(), isFalse);
      expect(
        await File(
          p.join(
            scope.storageDirectory(root, 'documents').path,
            'engines',
            'e.yaml',
          ),
        ).exists(),
        isTrue,
      );
    });

    test('a package containing only an avatar restores cleanly', () async {
      ProfileAvatarPolicy.debugSetUserImagesSupported(true);
      await writeAvatar('a1b2.gif', gifBytes);
      const key = 'file:avatars/a1b2.gif';
      final exported = await ProfilePortableFiles.exportAvatar(scope, key);
      await ProfileAvatarStorage.deleteAll(scope.profileId);
      ProfileAvatarPolicy.debugSetUserImagesSupported(false);
      expect(
        await ProfilePortableFiles.stageAvatar(
          scope: scope,
          record: exported,
          expectedAvatarKey: key,
          operationId: 'restore-4',
        ),
        isNull,
      );
    });
  });

  group('hostile attachments are refused', () {
    Map<String, Object?> attachment(String key) => <String, Object?>{
      'path': key,
      'encoding': 'base64',
      'bytes': 1,
      'sha256': 'x',
      'data': 'AA==',
    };

    for (final key in <String>[
      'avatars/../../escape.png',
      'avatars/nested/a.png',
      'avatars/a.exe',
      '../avatars/a.png',
    ]) {
      test('rejects $key', () async {
        await expectLater(
          ProfilePortableFiles.stageAvatar(
            scope: scope,
            record: attachment(key),
            expectedAvatarKey: 'file:$key',
            operationId: 'restore-hostile',
          ),
          throwsA(isA<FormatException>()),
        );
      });
    }

    test(
      'rejects a valid but over-dimension PNG before materializing',
      () async {
        final bytes = await paintPng(size: 1200);
        final record = <String, Object?>{
          'path': 'avatars/large.png',
          'encoding': 'base64',
          'bytes': bytes.length,
          'sha256': base64UrlEncode(
            (await Sha256().hash(bytes)).bytes,
          ).replaceAll('=', ''),
          'data': base64Encode(bytes),
        };
        await expectLater(
          ProfilePortableFiles.stageAvatar(
            scope: scope,
            record: record,
            expectedAvatarKey: 'file:avatars/large.png',
            operationId: 'restore-large',
          ),
          throwsA(isA<FormatException>()),
        );
        expect(
          await ProfileAvatarStorage.directoryFor(
            scope.profileId,
          ).then((directory) => directory.exists()),
          isFalse,
        );
      },
    );
  });
}
