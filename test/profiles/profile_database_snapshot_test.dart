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

      final export = await ProfileDatabaseSnapshot.export(sourceScope);
      expect(export.attachments.keys, contains('debrify_tv.db'));
      expect(
        await ProfileDatabaseSnapshot.restore(
          destinationScope,
          export.attachments,
        ),
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

    final export = await ProfileDatabaseSnapshot.export(sourceScope);
    expect(export.attachments.keys, contains('debrify_tv.db'));
    expect(
      await ProfileDatabaseSnapshot.restore(
        destinationScope,
        export.attachments,
      ),
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

  test('full snapshot keeps Debrify TV channels and saved hashes', () async {
    final sourceScope = ProfileScope(
      profileId: 'profile-full-tv-source',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final destinationScope = ProfileScope(
      profileId: 'profile-full-tv-destination',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final documents = await AppStorage.documents();
    final source = sourceScope.fileIn(documents, 'documents', 'debrify_tv.db');
    await source.parent.create(recursive: true);
    final database = await openDatabase(source.path, singleInstance: false);
    await database.execute(
      'CREATE TABLE tv_channels (channel_id TEXT PRIMARY KEY)',
    );
    await database.execute(
      'CREATE TABLE tv_cached_torrents '
      '(channel_id TEXT NOT NULL, infohash TEXT NOT NULL)',
    );
    await database.insert('tv_channels', <String, Object?>{
      'channel_id': 'channel-full',
    });
    await database.insert('tv_cached_torrents', <String, Object?>{
      'channel_id': 'channel-full',
      'infohash': 'hash-full',
    });
    await database.close();

    final export = await ProfileDatabaseSnapshot.export(sourceScope);
    expect(export.compacted, isEmpty);
    expect(export.debrifyTvOmission.isEmpty, isTrue);
    await ProfileDatabaseSnapshot.restore(destinationScope, export.attachments);

    final restored = await openDatabase(
      destinationScope.fileIn(documents, 'documents', 'debrify_tv.db').path,
      readOnly: true,
      singleInstance: false,
    );
    try {
      expect(
        (await restored.query('tv_channels')).single['channel_id'],
        'channel-full',
      );
      expect(
        (await restored.query('tv_cached_torrents')).single['infohash'],
        'hash-full',
      );
    } finally {
      await restored.close();
    }
  });

  test('never silently skips oversized durable database state', () async {
    ProfileDatabaseSnapshot.debugExportBudgetOverride = 1024;
    addTearDown(() => ProfileDatabaseSnapshot.debugExportBudgetOverride = null);
    final sourceScope = ProfileScope(
      profileId: 'profile-oversized',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final documents = await AppStorage.documents();
    final source = sourceScope.fileIn(documents, 'documents', 'debrify_tv.db');
    await source.parent.create(recursive: true);
    final database = await openDatabase(source.path);
    await database.execute('CREATE TABLE sample (value TEXT NOT NULL)');
    await database.insert('sample', <String, Object?>{'value': 'big'});
    await database.close();

    await expectLater(
      ProfileDatabaseSnapshot.export(sourceScope),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('Portable user library data is too large'),
        ),
      ),
    );
  });

  test(
    'compaction omits complete Debrify TV channels and keeps IPTV rows',
    () async {
      ProfileDatabaseSnapshot.debugExportBudgetOverride = 64 * 1024;
      addTearDown(
        () => ProfileDatabaseSnapshot.debugExportBudgetOverride = null,
      );
      final sourceScope = ProfileScope(
        profileId: 'profile-cache-heavy',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final destinationScope = ProfileScope(
        profileId: 'profile-cache-restored',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final documents = await AppStorage.documents();
      final source = sourceScope.fileIn(
        documents,
        'documents',
        'debrify_tv.db',
      );
      await source.parent.create(recursive: true);
      final database = await openDatabase(source.path, singleInstance: false);
      await database.execute(
        'CREATE TABLE durable_proof (value TEXT NOT NULL)',
      );
      await database.execute(
        'CREATE TABLE tv_channels (channel_id TEXT PRIMARY KEY)',
      );
      await database.execute(
        'CREATE TABLE tv_channel_keywords '
        '(channel_id TEXT NOT NULL, keyword TEXT NOT NULL)',
      );
      await database.execute(
        'CREATE TABLE tv_channel_cache_state (channel_id TEXT PRIMARY KEY)',
      );
      await database.execute(
        'CREATE TABLE tv_cached_torrents '
        '(channel_id TEXT NOT NULL, infohash TEXT NOT NULL, payload TEXT NOT NULL)',
      );
      await database.execute(
        'CREATE TABLE tv_keyword_stats '
        '(channel_id TEXT NOT NULL, keyword TEXT NOT NULL)',
      );
      await database.execute(
        'CREATE TABLE iptv_watch_history (playlist_id TEXT NOT NULL)',
      );
      await database.insert('durable_proof', <String, Object?>{
        'value': 'must-survive',
      });
      await database.insert('iptv_watch_history', <String, Object?>{
        'playlist_id': 'iptv-provider',
      });
      for (final channelId in const <String>['channel-a', 'channel-b']) {
        await database.insert('tv_channels', <String, Object?>{
          'channel_id': channelId,
        });
        await database.insert('tv_channel_keywords', <String, Object?>{
          'channel_id': channelId,
          'keyword': 'keyword-$channelId',
        });
        await database.insert('tv_channel_cache_state', <String, Object?>{
          'channel_id': channelId,
        });
        await database.insert('tv_keyword_stats', <String, Object?>{
          'channel_id': channelId,
          'keyword': 'keyword-$channelId',
        });
      }
      await database.insert('tv_cached_torrents', <String, Object?>{
        'channel_id': 'channel-a',
        'infohash': 'hash-a',
        'payload': List<String>.filled(256 * 1024, 'x').join(),
      });
      await database.insert('tv_cached_torrents', <String, Object?>{
        'channel_id': 'channel-b',
        'infohash': 'hash-b',
        'payload': 'small',
      });
      await database.close();

      final export = await ProfileDatabaseSnapshot.export(sourceScope);
      expect(export.compacted, contains('debrify_tv.db'));
      expect(export.debrifyTvOmission.channels, 2);
      expect(export.debrifyTvOmission.savedHashes, 2);
      expect(export.debrifyTvOmission.profilesAffected, 1);
      expect(export.attachments, contains('debrify_tv.db'));

      // Restore is replacement semantics. A compact backup must not preserve
      // destination channels, because a later dedicated Remote transfer owns
      // adding the complete channel and hash pool back.
      final destination = destinationScope.fileIn(
        documents,
        'documents',
        'debrify_tv.db',
      );
      await destination.parent.create(recursive: true);
      final destinationDatabase = await openDatabase(
        destination.path,
        singleInstance: false,
      );
      await destinationDatabase.execute(
        'CREATE TABLE tv_channels (channel_id TEXT PRIMARY KEY)',
      );
      await destinationDatabase.execute(
        'CREATE TABLE tv_cached_torrents '
        '(channel_id TEXT NOT NULL, infohash TEXT NOT NULL)',
      );
      await destinationDatabase.insert('tv_channels', <String, Object?>{
        'channel_id': 'destination-channel',
      });
      await destinationDatabase.insert('tv_cached_torrents', <String, Object?>{
        'channel_id': 'destination-channel',
        'infohash': 'destination-hash',
      });
      await destinationDatabase.close();

      await ProfileDatabaseSnapshot.restore(
        destinationScope,
        export.attachments,
      );

      final restored = await openDatabase(
        destinationScope.fileIn(documents, 'documents', 'debrify_tv.db').path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        expect(await restored.query('durable_proof'), <Map<String, Object?>>[
          <String, Object?>{'value': 'must-survive'},
        ]);
        expect(
          await restored.query('iptv_watch_history'),
          <Map<String, Object?>>[
            <String, Object?>{'playlist_id': 'iptv-provider'},
          ],
        );
        for (final table in const <String>[
          'tv_channels',
          'tv_channel_keywords',
          'tv_channel_cache_state',
          'tv_cached_torrents',
          'tv_keyword_stats',
        ]) {
          expect(await restored.query(table), isEmpty, reason: table);
        }
      } finally {
        await restored.close();
      }
    },
  );

  test('forced compaction reports only caches that contained rows', () async {
    final sourceScope = ProfileScope(
      profileId: 'profile-empty-cache',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    final documents = await AppStorage.documents();
    final source = sourceScope.fileIn(documents, 'documents', 'debrify_tv.db');
    await source.parent.create(recursive: true);
    final database = await openDatabase(source.path, singleInstance: false);
    await database.execute('CREATE TABLE durable_proof (value TEXT NOT NULL)');
    await database.execute(
      'CREATE TABLE tv_cached_torrents (payload TEXT NOT NULL)',
    );
    await database.insert('durable_proof', <String, Object?>{
      'value': 'still-present',
    });
    await database.close();

    final export = await ProfileDatabaseSnapshot.export(
      sourceScope,
      compact: true,
    );
    expect(export.compacted, isEmpty);
    expect(export.debrifyTvOmission.isEmpty, isTrue);
    expect(export.attachments, contains('debrify_tv.db'));
  });

  test(
    'resource IDs are remapped in every durable database reference',
    () async {
      const oldId = 'resource-old';
      const newId = 'resource-new';
      final scope = ProfileScope(
        profileId: 'profile-resource-remap',
        dataGeneration: 1,
        sessionEpoch: 1,
      );
      final documents = await AppStorage.documents();
      final media = scope.fileIn(documents, 'documents', 'debrify_tv.db');
      await media.parent.create(recursive: true);
      final mediaDb = await openDatabase(media.path, singleInstance: false);
      await mediaDb.execute(
        'CREATE TABLE iptv_list_channels (playlist_id TEXT NOT NULL)',
      );
      await mediaDb.execute(
        'CREATE TABLE iptv_watch_history (playlist_id TEXT NOT NULL)',
      );
      await mediaDb.insert('iptv_list_channels', <String, Object?>{
        'playlist_id': oldId,
      });
      await mediaDb.insert('iptv_watch_history', <String, Object?>{
        'playlist_id': oldId,
      });
      await mediaDb.close();

      final catalog = scope.fileIn(documents, 'documents', 'iptv_catalog.db');
      final catalogDb = await openDatabase(catalog.path, singleInstance: false);
      await catalogDb.execute(
        'CREATE TABLE channel_number_aliases '
        '(source_key TEXT PRIMARY KEY, namespace_id TEXT NOT NULL)',
      );
      await catalogDb.execute(
        'CREATE TABLE channel_number_namespaces '
        '(namespace_id TEXT PRIMARY KEY, active_source_key TEXT)',
      );
      await catalogDb.insert('channel_number_aliases', <String, Object?>{
        'source_key': oldId,
        'namespace_id': 'opaque-namespace',
      });
      await catalogDb.insert('channel_number_namespaces', <String, Object?>{
        'namespace_id': 'opaque-namespace',
        'active_source_key': oldId,
      });
      await catalogDb.close();

      await ProfileDatabaseSnapshot.remapResourceReferences(scope, const {
        oldId: newId,
      });

      final remappedMedia = await openDatabase(
        media.path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        expect(
          (await remappedMedia.query(
            'iptv_list_channels',
          )).single['playlist_id'],
          newId,
        );
        expect(
          (await remappedMedia.query(
            'iptv_watch_history',
          )).single['playlist_id'],
          newId,
        );
      } finally {
        await remappedMedia.close();
      }
      final remappedCatalog = await openDatabase(
        catalog.path,
        readOnly: true,
        singleInstance: false,
      );
      try {
        expect(
          (await remappedCatalog.query(
            'channel_number_aliases',
          )).single['source_key'],
          newId,
        );
        expect(
          (await remappedCatalog.query(
            'channel_number_namespaces',
          )).single['active_source_key'],
          newId,
        );
      } finally {
        await remappedCatalog.close();
      }
    },
  );

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
