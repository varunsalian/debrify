import 'dart:async';
import 'dart:io';

import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late Directory documents;
  late ProfileScope profileA;
  late ProfileScope profileB;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    root = await Directory.systemTemp.createTemp('profile-debrify-tv-db-');
    documents = await Directory(
      p.join(root.path, 'documents'),
    ).create(recursive: true);
    final support = await Directory(
      p.join(root.path, 'support'),
    ).create(recursive: true);
    final cache = await Directory(
      p.join(root.path, 'cache'),
    ).create(recursive: true);
    AppStorage.debugOverride(
      documents: documents,
      support: support,
      cache: cache,
    );
    profileA = ProfileScope(
      profileId: 'profile-a',
      dataGeneration: 1,
      sessionEpoch: 1,
    );
    profileB = ProfileScope(
      profileId: 'profile-b',
      dataGeneration: 1,
      sessionEpoch: 2,
    );
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(profileA);
    await DebrifyTvDatabase.instance.debugResetScopeState();
  });

  tearDown(() async {
    await DebrifyTvDatabase.instance.debugResetScopeState();
    ProfileRuntime.debugReset();
    AppStorage.debugReset();
    await root.delete(recursive: true);
  });

  test(
    'an A open completing after deactivation cannot become B singleton',
    () async {
      final reachedPublish = Completer<void>();
      final releasePublish = Completer<void>();
      DebrifyTvDatabase.debugBeforeOpenPublish = (_) async {
        reachedPublish.complete();
        await releasePublish.future;
      };

      final openingA = DebrifyTvDatabase.instance.database;
      await reachedPublish.future;
      final closingA = DebrifyTvDatabase.instance.closeScope(profileA);
      releasePublish.complete();

      await expectLater(openingA, throwsStateError);
      await closingA;

      DebrifyTvDatabase.debugBeforeOpenPublish = null;
      ProfileRuntime.publish(profileB);
      DebrifyTvDatabase.instance.activateScope(profileB);
      final dbB = await DebrifyTvDatabase.instance.database;
      await dbB.insert('tv_channels', <String, Object>{
        'channel_id': 'b-channel',
        'name': 'Profile B',
        'avoid_nsfw': 1,
        'channel_number': 1,
        'created_at': 1,
        'updated_at': 1,
      });

      final bRows = await dbB.query('tv_channels');
      expect(bRows.single['channel_id'], 'b-channel');

      final aPath = profileA
          .fileIn(documents, 'documents', 'debrify_tv.db')
          .path;
      final dbA = await databaseFactoryFfi.openDatabase(aPath);
      addTearDown(dbA.close);
      expect(await dbA.query('tv_channels'), isEmpty);
    },
  );

  test(
    'deactivated scope stays closed until rollback reactivates it',
    () async {
      await DebrifyTvDatabase.instance.database;
      await DebrifyTvDatabase.instance.closeScope(profileA);

      await expectLater(DebrifyTvDatabase.instance.database, throwsStateError);

      DebrifyTvDatabase.instance.activateScope(profileA);
      expect(await DebrifyTvDatabase.instance.database, isNotNull);
    },
  );

  test(
    'concurrent opens publish one handle for the authoritative scope',
    () async {
      final handles = await Future.wait(<Future<Database>>[
        DebrifyTvDatabase.instance.database,
        DebrifyTvDatabase.instance.database,
        DebrifyTvDatabase.instance.database,
      ]);

      expect(identical(handles[0], handles[1]), isTrue);
      expect(identical(handles[1], handles[2]), isTrue);
    },
  );

  test('portable export recovers pooled rows without cache state', () async {
    final db = await DebrifyTvDatabase.instance.database;
    await db.insert('tv_channels', <String, Object>{
      'channel_id': 'portable-channel',
      'name': 'Portable channel',
      'avoid_nsfw': 1,
      'channel_number': 1,
      'created_at': 1,
      'updated_at': 1,
    });
    await db.insert('tv_channel_keywords', <String, Object>{
      'channel_id': 'portable-channel',
      'position': 0,
      'keyword': 'science fiction',
    });
    await db.insert('tv_cached_torrents', <String, Object>{
      'channel_id': 'portable-channel',
      'infohash': 'preserved-hash',
      'name': 'Preserved title',
      'size_bytes': 1000,
      'created_unix': 10,
      'seeders': 20,
      'leechers': 2,
      'completed': 30,
      'scraped_date': 40,
      'keywords_json': '["science fiction"]',
      'sources_json': '["custom-source"]',
      'added_at': 50,
    });

    expect(await DebrifyTvCacheService.getEntry('portable-channel'), isNull);
    final portable = await DebrifyTvCacheService.getEntryForPortableExport(
      'portable-channel',
    );

    expect(portable, isNotNull);
    expect(portable!.status, 'ready');
    expect(portable.normalizedKeywords, <String>['science fiction']);
    expect(portable.torrents.single.infohash, 'preserved-hash');
    expect(portable.torrents.single.sources, <String>['custom-source']);
  });

  test('profile close waits for an admitted write transaction', () async {
    final transactionStarted = Completer<void>();
    final releaseTransaction = Completer<void>();
    final transaction = DebrifyTvDatabase.instance.runTxn((txn) async {
      transactionStarted.complete();
      await releaseTransaction.future;
      await txn.insert('tv_channels', <String, Object>{
        'channel_id': 'a-channel',
        'name': 'Profile A',
        'avoid_nsfw': 1,
        'channel_number': 1,
        'created_at': 1,
        'updated_at': 1,
      });
    });
    await transactionStarted.future;

    var closeCompleted = false;
    final closing = DebrifyTvDatabase.instance
        .closeScope(profileA)
        .whenComplete(() => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);

    releaseTransaction.complete();
    await transaction;
    await closing;

    ProfileRuntime.publish(profileB);
    DebrifyTvDatabase.instance.activateScope(profileB);
    final dbB = await DebrifyTvDatabase.instance.database;
    expect(await dbB.query('tv_channels'), isEmpty);
  });

  test('profile close waits for an admitted read operation', () async {
    final readStarted = Completer<void>();
    final releaseRead = Completer<void>();
    final read = DebrifyTvDatabase.instance.runScoped((db) async {
      readStarted.complete();
      await releaseRead.future;
      return db.query('tv_channels');
    });
    await readStarted.future;

    var closeCompleted = false;
    final closing = DebrifyTvDatabase.instance
        .closeScope(profileA)
        .whenComplete(() => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);

    releaseRead.complete();
    expect(await read, isEmpty);
    await closing;
  });

  test('read then nested transaction remains on its admitted scope', () async {
    await DebrifyTvDatabase.instance.runTxn((txn) async {
      await txn.insert('tv_channels', <String, Object>{
        'channel_id': 'source-a',
        'name': 'Profile A',
        'avoid_nsfw': 1,
        'channel_number': 1,
        'created_at': 1,
        'updated_at': 1,
      });
    });

    final readCompleted = Completer<void>();
    final releaseWrite = Completer<void>();
    final operation = DebrifyTvDatabase.instance.runScoped((db) async {
      final sourceRows = await db.query(
        'tv_channels',
        where: 'channel_id = ?',
        whereArgs: ['source-a'],
      );
      readCompleted.complete();
      await releaseWrite.future;
      await DebrifyTvDatabase.instance.runTxn((txn) async {
        await txn.insert('tv_channels', <String, Object>{
          'channel_id': 'derived-a',
          'name': '${sourceRows.single['name']} derived',
          'avoid_nsfw': 1,
          'channel_number': 2,
          'created_at': 2,
          'updated_at': 2,
        });
      });
    });
    await readCompleted.future;

    var closeCompleted = false;
    final closing = DebrifyTvDatabase.instance
        .closeScope(profileA)
        .whenComplete(() => closeCompleted = true);
    await Future<void>.delayed(Duration.zero);
    expect(closeCompleted, isFalse);

    releaseWrite.complete();
    await operation;
    await closing;

    final aPath = profileA.fileIn(documents, 'documents', 'debrify_tv.db').path;
    final dbA = await databaseFactoryFfi.openDatabase(aPath);
    addTearDown(dbA.close);
    expect(
      await dbA.query(
        'tv_channels',
        columns: ['channel_id'],
        orderBy: 'channel_number ASC',
      ),
      hasLength(2),
    );

    ProfileRuntime.publish(profileB);
    DebrifyTvDatabase.instance.activateScope(profileB);
    final bRows = await DebrifyTvDatabase.instance.runScoped(
      (db) => db.query('tv_channels'),
    );
    expect(bRows, isEmpty);
  });
}
