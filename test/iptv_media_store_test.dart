import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage_service.dart';

/// IPTV favorites / watch history / video resume on debrify_tv.db, including
/// the one-time import of the legacy SharedPreferences JSON blobs. Everything
/// is driven through the public StorageService API, which is what the app
/// actually calls.
void main() {
  const favoritesKey = 'iptv_favorite_channels_v1';
  const historyKey = 'iptv_watch_history_v1';
  const resumeKey = 'video_resume_v1';

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride =
        await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => DebrifyTvDatabase.createIptvStoreTables(db),
      ),
    );
  });

  tearDown(() async {
    await DebrifyTvDatabase.debugDatabaseOverride?.close();
    DebrifyTvDatabase.debugDatabaseOverride = null;
    IptvMediaStore.debugResetMigration();
  });

  group('legacy prefs import', () {
    test('imports all three stores once and removes the prefs keys', () async {
      SharedPreferences.setMockInitialValues({
        favoritesKey: jsonEncode({
          'http://h/live/u/p/1.ts': {
            'name': 'Спорт ᴴᴰ',
            'logoUrl': 'http://h/logo/1.png',
            'group': 'Sports',
            'playlistId': 'p1',
            'httpHeaders': {'User-Agent': 'TiviMate'},
            'addedAt': 111,
          },
        }),
        historyKey: jsonEncode({
          'http://h/movie/u/p/9.mp4': {
            'name': 'A Movie',
            'playlistId': 'p1',
            'seriesId': 's1',
            'seriesName': 'A Show',
            'season': 2,
            'episode': 5,
            'hasNext': true,
            'lastPlayedAt': 222,
          },
        }),
        resumeKey: jsonEncode({
          'http://h/movie/u/p/9.mp4': {
            'positionMs': 60000,
            'durationMs': 120000,
            'speed': 1.5,
            'aspect': 'fill',
            'updatedAt': 333,
          },
        }),
      });

      final favorites = await StorageService.getIptvFavoriteChannels();
      final meta = favorites['http://h/live/u/p/1.ts']!;
      expect(meta['name'], 'Спорт ᴴᴰ');
      expect(meta['group'], 'Sports');
      expect(meta['playlistId'], 'p1');
      expect(meta['httpHeaders'], {'User-Agent': 'TiviMate'});
      expect(meta['addedAt'], 111);

      final history = await StorageService.getIptvWatchHistory();
      final watched = history['http://h/movie/u/p/9.mp4']!;
      expect(watched['name'], 'A Movie');
      expect(watched['seriesId'], 's1');
      expect(watched['seriesName'], 'A Show');
      expect(watched['season'], 2);
      expect(watched['episode'], 5);
      expect(watched['hasNext'], true);
      expect(watched['lastPlayedAt'], 222);

      final resume =
          await StorageService.getVideoResume('http://h/movie/u/p/9.mp4');
      expect(resume, isNotNull);
      expect(resume!['positionMs'], 60000);
      expect(resume['durationMs'], 120000);
      expect(resume['speed'], 1.5);
      expect(resume['aspect'], 'fill');
      expect(resume['updatedAt'], 333);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(favoritesKey), isNull,
          reason: 'the legacy blob is deleted after a successful import');
      expect(prefs.getString(historyKey), isNull);
      expect(prefs.getString(resumeKey), isNull);
    });

    test('a corrupt legacy blob imports as empty, matching the old reader',
        () async {
      SharedPreferences.setMockInitialValues({favoritesKey: 'not json {'});

      expect(await StorageService.getIptvFavoriteChannels(), isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(favoritesKey), isNull);
    });
  });

  group('favorites', () {
    test('toggle on stores metadata, toggle off removes it', () async {
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/7.ts',
        true,
        channelName: 'News',
        logoUrl: 'http://h/logo.png',
        group: 'News',
        playlistId: 'p1',
        httpHeaders: {'Referer': 'http://h/'},
      );

      var favorites = await StorageService.getIptvFavoriteChannels();
      final meta = favorites['http://h/live/u/p/7.ts']!;
      expect(meta['name'], 'News');
      expect(meta['httpHeaders'], {'Referer': 'http://h/'});
      expect(meta['addedAt'], greaterThan(0));

      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/7.ts',
        false,
      );
      favorites = await StorageService.getIptvFavoriteChannels();
      expect(favorites, isEmpty);
    });

    test('re-starring under a different URL form replaces the old entry',
        () async {
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/7.m3u8',
        true,
        channelName: 'HLS form',
      );
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/7.ts',
        true,
        channelName: 'TS form',
      );

      final favorites = await StorageService.getIptvFavoriteChannels();
      expect(favorites.keys, ['http://h/live/u/p/7.ts'],
          reason: 'canonically-equal duplicates must collapse to one row');
    });

    test('deleting a playlist removes only its favorites', () async {
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/1.ts',
        true,
        playlistId: 'p1',
      );
      await StorageService.setIptvChannelFavorited(
        'http://h/live/u/p/2.ts',
        true,
        playlistId: 'p2',
      );

      await StorageService.removeIptvFavoritesByPlaylistId('p1');

      final favorites = await StorageService.getIptvFavoriteChannels();
      expect(favorites.keys, ['http://h/live/u/p/2.ts']);
    });
  });

  group('watch history', () {
    test('metadata round-trips, including series markers', () async {
      await StorageService.recordIptvWatch(
        'http://h/series/u/p/55.mp4',
        channelName: 'S02E05',
        playlistId: 'p1',
        httpHeaders: {'User-Agent': 'X'},
        seriesId: 's9',
        seriesName: 'A Show',
        season: 2,
        episode: 5,
        hasNextEpisode: true,
      );

      final history = await StorageService.getIptvWatchHistory();
      final meta = history['http://h/series/u/p/55.mp4']!;
      expect(meta['name'], 'S02E05');
      expect(meta['httpHeaders'], {'User-Agent': 'X'});
      expect(meta['seriesId'], 's9');
      expect(meta['hasNext'], true);
      expect(meta['lastPlayedAt'], greaterThan(0));
      expect(meta.containsKey('logoUrl'), isTrue);
    });

    test('a movie entry has no series keys at all', () async {
      await StorageService.recordIptvWatch(
        'http://h/movie/u/p/9.mp4',
        channelName: 'A Movie',
      );

      final meta =
          (await StorageService.getIptvWatchHistory())['http://h/movie/u/p/9.mp4']!;
      expect(meta.containsKey('seriesId'), isFalse);
      expect(meta.containsKey('season'), isFalse);
      expect(meta.containsKey('hasNext'), isFalse);
    });

    test('history is pruned to the 100 most recent', () async {
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      for (var i = 0; i < 100; i++) {
        await db.insert('iptv_watch_history', {
          'url': 'http://h/movie/u/p/$i.mp4',
          'name': 'Old $i',
          'last_played_at': 1000 + i,
        });
      }

      await StorageService.recordIptvWatch(
        'http://h/movie/u/p/new.mp4',
        channelName: 'Newest',
      );

      final history = await StorageService.getIptvWatchHistory();
      expect(history.length, 100);
      expect(history.keys, contains('http://h/movie/u/p/new.mp4'));
      expect(history.keys, isNot(contains('http://h/movie/u/p/0.mp4')),
          reason: 'the oldest entry makes room for the newest');
    });

    test('deleting a playlist removes its history', () async {
      await StorageService.recordIptvWatch(
        'http://h/movie/u/p/1.mp4',
        playlistId: 'p1',
      );
      await StorageService.recordIptvWatch(
        'http://h/movie/u/p/2.mp4',
        playlistId: 'p2',
      );

      await StorageService.removeIptvWatchHistoryByPlaylistId('p1');

      expect((await StorageService.getIptvWatchHistory()).keys,
          ['http://h/movie/u/p/2.mp4']);
    });
  });

  group('resume + continue watching', () {
    Future<void> watchAndResume(
      String url, {
      required int positionMs,
      required int durationMs,
      required int updatedAt,
      String? seriesId,
      bool? hasNext,
      String? playlistId,
    }) async {
      await StorageService.recordIptvWatch(
        url,
        channelName: url,
        playlistId: playlistId ?? 'p1',
        seriesId: seriesId,
        seriesName: seriesId == null ? null : 'Show $seriesId',
        hasNextEpisode: hasNext,
      );
      await StorageService.upsertVideoResume(url, {
        'positionMs': positionMs,
        'durationMs': durationMs,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': updatedAt,
      });
    }

    test('in-progress items show, barely-started and finished movies do not',
        () async {
      await watchAndResume('http://h/mid.mp4',
          positionMs: 50000, durationMs: 100000, updatedAt: 30);
      await watchAndResume('http://h/blip.mp4',
          positionMs: 500, durationMs: 100000, updatedAt: 20);
      await watchAndResume('http://h/done.mp4',
          positionMs: 99000, durationMs: 100000, updatedAt: 10);

      final shelf = await StorageService.getIptvContinueWatching();
      expect(shelf.map((e) => e['url']), ['http://h/mid.mp4']);
      expect(shelf.single['progress'], closeTo(0.5, 0.001));
      expect(shelf.single['positionMs'], 50000);
    });

    test('a finished series episode with a next episode stays on the shelf',
        () async {
      await watchAndResume('http://h/s1e1.mp4',
          positionMs: 99000,
          durationMs: 100000,
          updatedAt: 100,
          seriesId: 's1',
          hasNext: true);

      final shelf = await StorageService.getIptvContinueWatching();
      expect(shelf.map((e) => e['url']), ['http://h/s1e1.mp4'],
          reason: 'a finished middle episode keeps the series visible');
    });

    test('most recently played sorts first', () async {
      await watchAndResume('http://h/older.mp4',
          positionMs: 50000, durationMs: 100000, updatedAt: 100);
      await watchAndResume('http://h/newer.mp4',
          positionMs: 50000, durationMs: 100000, updatedAt: 200);

      final shelf = await StorageService.getIptvContinueWatching();
      expect(shelf.map((e) => e['url']),
          ['http://h/newer.mp4', 'http://h/older.mp4']);
    });

    test(
        'a resume entry without a timestamp falls back to the watch-history '
        'recency instead of sorting to 1970', () async {
      await watchAndResume('http://h/timed.mp4',
          positionMs: 50000, durationMs: 100000, updatedAt: 5);
      await StorageService.recordIptvWatch('http://h/untimed.mp4',
          channelName: 'Untimed');
      await StorageService.upsertVideoResume('http://h/untimed.mp4', {
        'positionMs': 50000,
        'durationMs': 100000,
        // no updatedAt — the shape very old legacy entries had
      });

      final shelf = await StorageService.getIptvContinueWatching();
      expect(shelf.first['url'], 'http://h/untimed.mp4',
          reason: 'recordIptvWatch stamped it now, far newer than updatedAt=5');
    });

    test('resume windows: positions only inside the resumable band', () async {
      await StorageService.upsertVideoResume('http://h/mid.mp4', {
        'positionMs': 50000,
        'durationMs': 100000,
        'updatedAt': 1,
      });
      await StorageService.upsertVideoResume('http://h/done.mp4', {
        'positionMs': 99000,
        'durationMs': 100000,
        'updatedAt': 2,
      });

      final positions = await StorageService.getIptvResumePositions(
        ['http://h/mid.mp4', 'http://h/done.mp4', 'http://h/none.mp4'],
      );
      expect(positions, {'http://h/mid.mp4': 50000},
          reason: 'a finished item restarts from the beginning');

      final progress = await StorageService.getIptvProgressForUrls(
        ['http://h/mid.mp4', 'http://h/done.mp4'],
      );
      expect(progress['http://h/mid.mp4'], closeTo(0.5, 0.001));
      expect(progress['http://h/done.mp4'], closeTo(0.99, 0.001),
          reason: 'progress bars do show full for finished items');
    });

    test('a resume lookup spanning multiple IN-chunks finds every row',
        () async {
      final urls = [for (var i = 0; i < 1200; i++) 'http://h/v$i.mp4'];
      final db = DebrifyTvDatabase.debugDatabaseOverride!;
      final batch = db.batch();
      for (final url in urls) {
        batch.insert('video_resume', {
          'resume_key': url,
          'position_ms': 5000,
          'duration_ms': 10000,
          'updated_at': 1,
        });
      }
      await batch.commit(noResult: true);

      final progress = await StorageService.getIptvProgressForUrls(urls);
      expect(progress.length, 1200);
    });

    test('clearAllPlaybackData empties the resume store', () async {
      await StorageService.upsertVideoResume('http://h/v.mp4', {
        'positionMs': 1000,
        'durationMs': 2000,
        'updatedAt': 1,
      });

      await StorageService.clearAllPlaybackData();

      expect(await StorageService.getVideoResume('http://h/v.mp4'), isNull);
    });
  });
}
