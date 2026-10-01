import 'dart:io';

import 'package:debrify/features/home/application/home_continuation_providers.dart';
import 'package:debrify/models/iptv_cw_entry.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/profiles/profile_runtime.dart';
import 'package:debrify/services/profiles/profile_scope.dart';
import 'package:debrify/services/profiles/profile_session_memory.dart';
import 'package:debrify/services/webdav_sync/webdav_sync_library_mutation.dart';
import 'package:debrify/utils/app_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final origin = ProfileScope(
    profileId: 'origin',
    dataGeneration: 1,
    sessionEpoch: 1,
  );
  final other = ProfileScope(
    profileId: 'other',
    dataGeneration: 1,
    sessionEpoch: 2,
  );
  late Directory root;
  final store = DebrifyTvDatabase.instance;

  Future<T> within<T>(ProfileScope scope, Future<T> Function() body) =>
      ProfileRuntime.withCapturedScope(scope, body);

  Future<void> seed(ProfileScope scope) => within(
    scope,
    () => store.runScoped((db) async {
      for (final row in [
        ('movie', 'p', null),
        ('ep1', 'p', 's'),
        ('ep2', 'p', 's'),
        ('other-series', 'p', 't'),
        ('other-playlist', 'q', 's'),
      ]) {
        await db.insert('iptv_watch_history', {
          'url': row.$1,
          'playlist_id': row.$2,
          'series_id': row.$3,
        });
        await db.insert('video_resume', {
          'resume_key': row.$1,
          'source_id': row.$2,
          'position_ms': 50,
          'duration_ms': 100,
        });
      }
    }),
  );

  IptvCwEntry entry({bool series = false, Map<String, dynamic>? raw}) =>
      IptvCwEntry(
        routeKey: series ? 'xtream-series://p/s' : 'movie',
        title: 'Fixture',
        posterUrl: null,
        subtitle: null,
        isSeries: series,
        progress: 0.5,
        seLabel: null,
        raw: raw ?? (series ? {'playlistId': 'p', 'seriesId': 's'} : {}),
      );

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    root = await Directory.systemTemp.createTemp('home-iptv-removal-');
    AppStorage.debugOverride(documents: root, support: root, cache: root);
    SharedPreferences.setMockInitialValues({});
    ProfileRuntime.debugReset();
    ProfileRuntime.initializeCommitted(origin);
    await store.debugResetScopeState();
    IptvMediaStore.debugResetMigration();
    WebDavSyncLibraryMutation.debugUserMutationObserver = null;
    await seed(origin);
    await seed(other);
  });
  tearDown(() async {
    WebDavSyncLibraryMutation.debugUserMutationObserver = null;
    await store.debugResetScopeState();
    IptvMediaStore.debugResetMigration();
    ProfileRuntime.debugReset();
    AppStorage.debugReset();
    await root.delete(recursive: true);
  });

  for (final series in [false, true]) {
    for (final retire in [false, true]) {
      test(
        'scoped removal with sync records: series=$series retired=$retire',
        () async {
          final container = ProviderContainer.test();
          final removal = container.read(
            homeIptvHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
          );
          if (retire) {
            WebDavSyncLibraryMutation.debugUserMutationObserver =
                ProfileSessionMemory.clearAll;
          }
          // A foreign ambient zone must not redirect the accepted write.
          expect(
            await within(
              other,
              () =>
                  removal.remove(entry(series: series), isCurrent: () => true),
            ),
            !retire,
          );
          final removed = series ? {'ep1', 'ep2'} : {'movie'};
          await within(
            origin,
            () => store.runScoped((db) async {
              final history = await db.query('iptv_watch_history');
              final resumes = await db.query('video_resume');
              expect(
                history.map((r) => r['url']).toSet(),
                {
                  'movie',
                  'ep1',
                  'ep2',
                  'other-series',
                  'other-playlist',
                }.difference(removed),
              );
              expect(
                resumes.map((r) => r['resume_key']).toSet(),
                history.map((r) => r['url']).toSet(),
              );
              final tombstones = await db.query(
                'webdav_sync_record_state',
                where: 'deleted = 1',
              );
              expect(tombstones.length, removed.length * 2);
              expect(tombstones.map((r) => r['item_key']).toSet(), removed);
            }),
          );
          await within(
            other,
            () => store.runScoped((db) async {
              expect(await db.query('iptv_watch_history'), hasLength(5));
              expect(await db.query('video_resume'), hasLength(5));
              expect(
                await db.query(
                  'webdav_sync_record_state',
                  where: 'deleted = 1',
                ),
                isEmpty,
              );
            }),
          );
        },
      );
    }
  }
  test('movie uses explicit URL before route key', () async {
    final container = ProviderContainer.test();
    final removal = container.read(
      homeIptvHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
    );
    expect(
      await removal.remove(entry(raw: {'url': 'ep1'}), isCurrent: () => true),
      isTrue,
    );
    await within(
      origin,
      () => store.runScoped((db) async {
        final rows = await db.query('iptv_watch_history');
        expect(rows.map((r) => r['url']), contains('movie'));
        expect(rows.map((r) => r['url']), isNot(contains('ep1')));
      }),
    );
  });
  test('retired owner/view and invalid series perform no writes', () async {
    final container = ProviderContainer.test();
    final removal = container.read(
      homeIptvHistoryRemovalProvider(ProfileSessionMemory.captureOwner()),
    );
    expect(await removal.remove(entry(), isCurrent: () => false), isFalse);
    expect(
      await removal.remove(entry(series: true, raw: {}), isCurrent: () => true),
      isFalse,
    );
    ProfileSessionMemory.clearAll();
    expect(await removal.remove(entry(), isCurrent: () => true), isFalse);
    await within(
      origin,
      () => store.runScoped((db) async {
        expect(await db.query('iptv_watch_history'), hasLength(5));
        expect(await db.query('video_resume'), hasLength(5));
        expect(await db.query('webdav_sync_record_state'), isEmpty);
      }),
    );
  });
}
