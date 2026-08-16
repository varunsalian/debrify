import 'dart:io';

import 'package:debrify/services/profiles/profile_database_snapshot.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _SnapshotPathProvider extends PathProviderPlatform {
  _SnapshotPathProvider(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationDocumentsPath() async =>
      (await Directory('${root.path}/documents').create(recursive: true)).path;

  @override
  Future<String?> getApplicationSupportPath() async =>
      (await Directory('${root.path}/support').create(recursive: true)).path;
}

void main() {
  late Directory root;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = await Directory.systemTemp.createTemp('profile-db-snapshot-');
    PathProviderPlatform.instance = _SnapshotPathProvider(root);
  });

  tearDownAll(() async {
    await root.delete(recursive: true);
  });

  test(
    'exports a consistent SQLite image into an invisible generation',
    () async {
      final sourceScope = ProfileScope(
        profileId: 'profile-source',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final destinationScope = ProfileScope(
        profileId: 'profile-destination',
        dataGeneration: 2,
        sessionEpoch: 1,
      );
      final documents = await AppStorage.documents();
      final source = sourceScope.fileIn(
        documents,
        'documents',
        'debrify_tv.db',
      );
      await source.parent.create(recursive: true);
      final database = await openDatabase(source.path);
      await database.execute('CREATE TABLE sample (value TEXT NOT NULL)');
      await database.insert('sample', <String, Object?>{'value': 'isolated'});
      await database.close();

      final attachments = await ProfileDatabaseSnapshot.export(sourceScope);
      expect(attachments.keys, contains('debrify_tv.db'));
      expect(
        await ProfileDatabaseSnapshot.restore(destinationScope, attachments),
        1,
      );

      final restored = await openDatabase(
        destinationScope.fileIn(documents, 'documents', 'debrify_tv.db').path,
        readOnly: true,
      );
      try {
        expect(await restored.query('sample'), <Map<String, Object?>>[
          <String, Object?>{'value': 'isolated'},
        ]);
      } finally {
        await restored.close();
      }
    },
  );

  test('checkpoint-copy fallback round-trips like VACUUM INTO', () async {
    // The path Android 7-9 devices actually take: their OS SQLite predates
    // VACUUM INTO (3.27), and the test rig's bundled library can't reproduce
    // that — so the seam forces the fallback here.
    ProfileDatabaseSnapshot.debugForceCheckpointCopy = true;
    addTearDown(() => ProfileDatabaseSnapshot.debugForceCheckpointCopy = false);
    final sourceScope = ProfileScope(
      profileId: 'profile-legacy-sqlite',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final destinationScope = ProfileScope(
      profileId: 'profile-legacy-restore',
      dataGeneration: 2,
      sessionEpoch: 1,
    );
    final documents = await AppStorage.documents();
    final source = sourceScope.fileIn(documents, 'documents', 'debrify_tv.db');
    await source.parent.create(recursive: true);
    final database = await openDatabase(source.path);
    await database.execute('CREATE TABLE sample (value TEXT NOT NULL)');
    await database.insert('sample', <String, Object?>{'value': 'legacy'});
    await database.close();

    final attachments = await ProfileDatabaseSnapshot.export(sourceScope);
    expect(attachments.keys, contains('debrify_tv.db'));
    expect(
      await ProfileDatabaseSnapshot.restore(destinationScope, attachments),
      1,
    );
    final restored = await openDatabase(
      destinationScope.fileIn(documents, 'documents', 'debrify_tv.db').path,
      readOnly: true,
    );
    try {
      expect(await restored.query('sample'), <Map<String, Object?>>[
        <String, Object?>{'value': 'legacy'},
      ]);
    } finally {
      await restored.close();
    }
  });

  test('rejects attachment digest tampering before publication', () async {
    final destinationScope = ProfileScope(
      profileId: 'profile-tampered',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final attachments = <Object?, Object?>{
      'debrify_tv.db': <String, Object?>{
        'encoding': 'base64',
        'bytes': 2,
        'sha256': 'not-the-real-digest',
        'data': 'e30=',
      },
    };

    await expectLater(
      ProfileDatabaseSnapshot.restore(destinationScope, attachments),
      throwsA(isA<FormatException>()),
    );
  });
}
