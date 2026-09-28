import 'dart:async';
import 'package:debrify/models/debrify_tv_cache.dart';
import 'package:debrify/models/debrify_tv_channel_action.dart';
import 'package:debrify/services/debrify_tv_channel_actions.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/debrify_tv_cache_service.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../features/sources/data/automatic_source_binding_owner_test.dart'
    show source;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database db;
  late DebrifyTvChannelActions actions;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeLegacy();
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await DebrifyTvDatabase.createTvStoreTables(db);
          await DebrifyTvDatabase.createIptvStoreTables(db);
        },
      ),
    );
    DebrifyTvDatabase.debugDatabaseOverride = db;
    actions = DebrifyTvChannelActions(
      owner: ProfileSessionMemory.captureOwner(),
      canContinue: () => true,
    );
  });
  tearDown(() async {
    DebrifyTvDatabase.debugDatabaseOverride = null;
    await db.close();
    ProfileRuntime.debugReset();
  });

  test(
    'create and add preserve keyword merge, ordering and duplicate counts',
    () async {
      final selected = await actions.createChannel('Channel', 'Existing');
      expect(selected.isNewChannel, isTrue);
      expect((await actions.loadChannels()).single.channelNumber, 1);
      expect(
        (await DebrifyTvCacheService.getEntry(selected.channelId))!.status,
        DebrifyTvCacheStatus.warming,
      );
      await actions.add(
        selected,
        DebrifyTvChannelActions.prepare([source(' OLD ')]),
        'Existing',
      );
      final result = await actions.add(
        selected,
        DebrifyTvChannelActions.prepare([
          source('NEW'),
          source('old'),
          source('new'),
        ]),
        'New keyword',
      );
      expect(result.totalCount, 3);
      expect(result.addedCount, 1);
      expect(result.updatedCount, 1);
      final cached = (await DebrifyTvCacheService.getEntry(
        selected.channelId,
      ))!;
      expect(cached.status, DebrifyTvCacheStatus.ready);
      expect(cached.torrents.map((e) => e.infohash), ['old', 'new']);
      expect(
        cached.torrents.first.keywords,
        containsAll(['existing', 'new keyword']),
      );
      expect((await actions.loadChannels()).single.keywords, [
        'Existing',
        'New keyword',
      ]);
    },
  );
  test('unsupported streams are filtered and empty selection rejected', () {
    final filtered = DebrifyTvChannelActions.prepare([
      source(' HASH '),
      source('direct', direct: true),
    ]);
    expect(filtered.single.infohash, 'hash');
    expect(
      () => DebrifyTvChannelActions.prepare([source('direct', direct: true)]),
      throwsA(isA<DebrifyTvChannelAddException>()),
    );
  });
  test(
    'failure during cache creation rolls back channel and sync state',
    () async {
      await db.execute(
        "CREATE TRIGGER reject_cache BEFORE INSERT ON tv_cached_torrents BEGIN SELECT RAISE(ABORT, 'blocked'); END",
      );
      final selected = await actions.createChannel('Channel', 'Original');
      final before = await db.query('webdav_sync_record_state');
      await expectLater(
        actions.add(
          selected,
          DebrifyTvChannelActions.prepare([source('new')]),
          'New keyword',
        ),
        throwsA(anything),
      );
      expect((await actions.loadChannels()).single.keywords, ['Original']);
      expect(
        (await DebrifyTvCacheService.getEntry(selected.channelId))!.torrents,
        isEmpty,
      );
      expect(await db.query('webdav_sync_record_state'), before);
    },
  );
  for (final picker in [false, true]) {
    test(
      '${picker ? 'picker disposal' : 'profile retirement'} while transaction waits prevents creation',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        final blocker = db.transaction((txn) async {
          entered.complete();
          await release.future;
        });
        await entered.future;
        var live = true;
        final pending = actions.createChannel(
          'Retired',
          'Keyword',
          canContinue: () => live,
        );
        final assertion = expectLater(pending, throwsStateError);
        await Future<void>.delayed(Duration.zero);
        if (picker) {
          live = false;
        } else {
          ProfileSessionMemory.clearAll();
        }
        release.complete();
        await blocker;
        await assertion;
        expect(await db.query('tv_channels'), isEmpty);
        expect(await db.query('webdav_sync_record_state'), isEmpty);
      },
    );
  }
  test('retirement after acceptance keeps durable channel', () async {
    final selected = await actions.createChannel('Accepted', 'Keyword');
    ProfileSessionMemory.clearAll();
    expect(
      (await db.query('tv_channels')).single['channel_id'],
      selected.channelId,
    );
    await expectLater(actions.loadChannels(), throwsStateError);
  });
}
