import 'dart:convert';
import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/models/stremio_addon.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/series_progress_reset_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    IptvMediaStore.debugResetMigration();
    DebrifyTvDatabase.debugDatabaseOverride = await databaseFactoryFfiNoIsolate
        .openDatabase(
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

  test('movie and episode completion thresholds are independent', () async {
    expect(
      await StorageService.getMovieCompletionThreshold(),
      StorageService.defaultLocalCompletionThreshold,
    );
    expect(
      await StorageService.getEpisodeCompletionThreshold(),
      StorageService.defaultLocalCompletionThreshold,
    );

    await StorageService.setMovieCompletionThreshold(90);
    await StorageService.setEpisodeCompletionThreshold(75);

    expect(await StorageService.getMovieCompletionThreshold(), 90);
    expect(await StorageService.getEpisodeCompletionThreshold(), 75);
  });

  test('100 percent persists independently for movies and episodes', () async {
    expect(StorageService.localCompletionThresholdOptions, contains(100));
    await StorageService.setMovieCompletionThreshold(100);
    await StorageService.setEpisodeCompletionThreshold(95);
    expect(await StorageService.getMovieCompletionThreshold(), 100);
    expect(await StorageService.getEpisodeCompletionThreshold(), 95);
    await StorageService.setEpisodeCompletionThreshold(100);
    expect(await StorageService.getEpisodeCompletionThreshold(), 100);
  });

  test('finishing a local movie clears resume and continue watching', () async {
    await StorageService.saveContinueWatchingItem(
      imdbId: 'TT001',
      title: 'Example Movie',
      contentType: 'movie',
    );
    await StorageService.saveVideoPlaybackState(
      videoTitle: 'Example Movie',
      videoUrl: 'https://example.com/movie.m3u8',
      positionMs: 64000,
      durationMs: 120000,
      imdbId: 'TT001',
    );

    await StorageService.markMovieAsFinished('TT001');

    // Simulate a final autosave racing with the completion cleanup. The local
    // completed marker remains authoritative until a deliberate rewatch.
    await StorageService.saveVideoPlaybackState(
      videoTitle: 'Example Movie',
      videoUrl: 'https://example.com/movie.m3u8',
      positionMs: 96000,
      durationMs: 120000,
      imdbId: 'TT001',
    );

    expect(await StorageService.isMovieFinished('tt001'), isTrue);
    expect(
      await StorageService.getVideoPlaybackState(videoTitle: 'Example Movie'),
      isNull,
    );
    expect(await StorageService.getVideoPlaybackStateByImdbId('tt001'), isNull);
    expect(await StorageService.getContinueWatchingItems(), isEmpty);

    await StorageService.unmarkMovieAsFinished('tt001');
    expect(await StorageService.isMovieFinished('tt001'), isFalse);
  });

  test('clearing playlist progress invalidates local completion', () async {
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Example Series',
      season: 1,
      episode: 1,
      positionMs: 1000,
      durationMs: 1000,
      imdbId: 'tt-series',
    );
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Example Series',
      season: 1,
      episode: 1,
      imdbId: 'tt-series',
    );
    final revisionBefore = StorageService.localCompletionRevision.value;

    await StorageService.clearPlaylistProgress(title: 'Example Series');

    expect(
      await StorageService.isEpisodeFinished(
        seriesTitle: 'Example Series',
        season: 1,
        episode: 1,
      ),
      isFalse,
    );
    expect(StorageService.localCompletionRevision.value, revisionBefore + 1);
  });

  test(
    'reset reports a failed tracker and still clears local and other trackers',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trakt_access_token', 'test-token');
      await prefs.setString('simkl_access_token', 'test-token');
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Show',
        season: 1,
        episode: 1,
        positionMs: 500,
        durationMs: 1000,
        imdbId: 'tt001',
      );
      final requests = <Uri>[];
      await http.runWithClient(
        () async {
          final failures = await SeriesProgressResetService.clear(
            'tt001',
            'Show',
          );
          expect(failures, ['Trakt']);
          expect(
            await StorageService.getEpisodeProgressByImdbId('tt001'),
            isEmpty,
          );
        },
        () => MockClient((request) async {
          requests.add(request.url);
          if (request.url.host.contains('trakt'))
            return http.Response('{}', 503);
          return http.Response('[]', 200);
        }),
      );
      expect(requests.where((uri) => uri.host.contains('simkl')), isNotEmpty);
    },
  );

  test(
    'expired Trakt token with failed refresh reports Trakt failure',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('trakt_access_token', 'expired-token');
      await prefs.setString('trakt_refresh_token', 'refresh-token');
      await prefs.setInt('trakt_token_expiry', 1);
      final requests = <Uri>[];
      await http.runWithClient(
        () async {
          expect(await SeriesProgressResetService.clear('tt001', 'Show'), [
            'Trakt',
          ]);
        },
        () => MockClient((request) async {
          requests.add(request.url);
          return http.Response('{}', 503);
        }),
      );
      expect(requests, isNotEmpty);
      expect(requests.every((uri) => uri.path == '/oauth/token'), isTrue);
    },
  );

  test(
    'completion rederivation preserves another IMDb series with the same title',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Shared Title',
        season: 1,
        episode: 1,
        imdbId: 'tt002',
      );
      final before = prefs.getString('playback_state_v1');
      // The reset title's inventory uses the same display name as a distinct show.
      await prefs.setString(
        StorageService.localSeriesCompletionStateKey,
        jsonEncode({
          'tt001': {
            'title': 'Shared Title',
            'episodes': {'1-1': 0},
            'caughtUp': false,
          },
        }),
      );
      expect(
        await SeriesProgressResetService.clear('tt001', 'Shared Title'),
        isEmpty,
      );
      expect(prefs.getString('playback_state_v1'), before);
      final completion = jsonDecode(
        prefs.getString(StorageService.localSeriesCompletionStateKey)!,
      );
      expect(completion['tt001']['caughtUp'], isFalse);
      expect(
        await StorageService.getFinishedEpisodesByImdbId(
          imdbId: 'tt001',
          seriesTitle: 'Shared Title',
        ),
        isEmpty,
      );
      expect(
        await StorageService.getFinishedEpisodesByImdbId(imdbId: 'tt002'),
        {
          '1': {1},
        },
      );
    },
  );

  test(
    'completion title fallback still supports ID-less legacy records',
    () async {
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Legacy Show',
        season: 1,
        episode: 2,
      );
      final index = await StorageService.getFinishedSeriesEpisodeIndex();
      expect(index['title:legacy show'], {
        '1': {2},
      });
      expect(
        await StorageService.getFinishedEpisodesByImdbId(
          imdbId: 'tt-legacy',
          seriesTitle: 'Legacy Show',
        ),
        {
          '1': {2},
        },
      );
    },
  );

  test('reset skips Trakt only when credentials are absent', () async {
    var requests = 0;
    await http.runWithClient(
      () async {
        expect(
          await SeriesProgressResetService.clear('tt001', 'Show'),
          isEmpty,
        );
      },
      () => MockClient((request) async {
        requests++;
        return http.Response('{}', 503);
      }),
    );
    expect(requests, 0);
  });

  test(
    'global movie reset clears watched and resume state only for that movie',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('series_source_tt001', 'keep');
      for (final id in ['tt001', 'tt002']) {
        await StorageService.markMovieAsFinished(id);
        await StorageService.saveVideoPlaybackState(
          videoTitle: id,
          videoUrl: 'https://test/$id',
          positionMs: 500,
          durationMs: 1000,
          imdbId: id,
        );
        await StorageService.saveContinueWatchingItem(
          imdbId: id,
          title: id,
          contentType: 'movie',
        );
      }
      expect(
        await SeriesProgressResetService.clear('tt001', 'Movie', isMovie: true),
        isEmpty,
      );
      expect(await StorageService.isMovieFinished('tt001'), isFalse);
      expect(
        await StorageService.getVideoPlaybackState(videoTitle: 'tt001'),
        isNull,
      );
      expect(await StorageService.isMovieFinished('tt002'), isTrue);
      expect(
        await StorageService.getVideoPlaybackState(
          videoTitle: 'tt002',
          includeFinished: true,
        ),
        isNotNull,
      );
      expect(
        (await StorageService.getContinueWatchingItems()).any(
          (e) => e['imdbId'] == 'tt001',
        ),
        isFalse,
      );
      expect(prefs.getString('series_source_tt001'), 'keep');
    },
  );

  test(
    'series reset clears all seasons and tracker snapshots but preserves other titles and bindings',
    () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('series_source_tt001', 'keep source binding');
      for (final id in ['tt001', 'tt002']) {
        for (final season in [0, 1, 2]) {
          await StorageService.saveSeriesPlaybackState(
            seriesTitle: id,
            season: season,
            episode: 1,
            positionMs: 500,
            durationMs: 1000,
            imdbId: id,
          );
          await StorageService.markEpisodeAsFinished(
            seriesTitle: id,
            season: season,
            episode: 2,
            imdbId: id,
          );
        }
        await StorageService.saveEpisodeTraktProgress(
          imdbId: id,
          percents: {'1_1': 50},
        );
        await StorageService.saveEpisodeSimklProgress(
          imdbId: id,
          percents: {'1_1': 50},
        );
        await StorageService.saveEpisodeMdblistProgress(
          imdbId: id,
          percents: {'1_1': 50},
        );
      }
      await StorageService.clearSeriesWatchProgress('tt001', 'tt001');
      expect(await StorageService.getEpisodeProgressByImdbId('tt001'), isEmpty);
      expect(
        await StorageService.getFinishedEpisodesByImdbId(
          imdbId: 'tt001',
          seriesTitle: 'tt001',
        ),
        isEmpty,
      );
      expect(
        await StorageService.getEpisodeTraktProgress(imdbId: 'tt001'),
        isEmpty,
      );
      expect(
        await StorageService.getEpisodeSimklProgress(imdbId: 'tt001'),
        isEmpty,
      );
      expect(
        await StorageService.getEpisodeMdblistProgress(imdbId: 'tt001'),
        isEmpty,
      );
      expect(
        await StorageService.getEpisodeProgressByImdbId('tt002'),
        isNotEmpty,
      );
      expect(
        await StorageService.getEpisodeSimklProgress(imdbId: 'tt002'),
        isNotEmpty,
      );
      expect(prefs.getString('series_source_tt001'), 'keep source binding');
    },
  );

  test('clearing playback by IMDb invalidates local completion', () async {
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'IMDb Clear Show',
      season: 1,
      episode: 1,
      imdbId: 'tt-imdb-clear',
    );
    final revisionBefore = StorageService.localCompletionRevision.value;

    await StorageService.clearPlaybackStateByImdbId('TT-IMDB-CLEAR');

    expect(
      await StorageService.isEpisodeFinished(
        seriesTitle: 'IMDb Clear Show',
        season: 1,
        episode: 1,
      ),
      isFalse,
    );
    expect(StorageService.localCompletionRevision.value, revisionBefore + 1);
  });

  test('finished episode index unions duplicate IMDb records', () async {
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Original Title',
      season: 1,
      episode: 1,
      imdbId: 'tt-duplicate',
    );
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Localized Title',
      season: 1,
      episode: 2,
      imdbId: 'tt-duplicate',
    );

    final index = await StorageService.getFinishedSeriesEpisodeIndex();
    expect(index['tt-duplicate']?['1'], {1, 2});
    expect(
      await StorageService.getFinishedEpisodesByImdbId(imdbId: 'tt-duplicate'),
      {
        '1': {1, 2},
      },
    );
  });

  test('playback removes the matching local watchlist title', () async {
    final item = StremioMeta(
      id: 'tt-watchlist-play',
      imdbId: 'tt-watchlist-play',
      type: 'movie',
      name: 'Watchlist Movie',
    );
    await StorageService.setMyWatchlistItem(item, true);

    expect(
      await StorageService.removeMyWatchlistItemForPlayback(
        imdbId: 'TT-WATCHLIST-PLAY',
        contentType: 'movie',
        title: 'Different presentation title',
      ),
      isTrue,
    );
    expect(await StorageService.getMyWatchlistItems(), isEmpty);
  });

  test(
    'existing playback is migrated once using separate thresholds',
    () async {
      await StorageService.setMovieCompletionThreshold(90);
      await StorageService.setEpisodeCompletionThreshold(75);

      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt-movie-done',
        title: 'Done Movie',
        contentType: 'movie',
      );
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt-movie-partial',
        title: 'Partial Movie',
        contentType: 'movie',
      );
      await StorageService.saveVideoPlaybackState(
        videoTitle: 'Done Movie',
        videoUrl: 'https://example.com/done.m3u8',
        positionMs: 900,
        durationMs: 1000,
        imdbId: 'tt-movie-done',
      );
      await StorageService.upsertVideoResume('Done Movie', {
        'positionMs': 900,
        'durationMs': 1000,
        'speed': 1.0,
        'aspect': 'contain',
        'updatedAt': 1,
      });
      await StorageService.saveVideoPlaybackState(
        videoTitle: 'Partial Movie',
        videoUrl: 'https://example.com/partial.m3u8',
        positionMs: 850,
        durationMs: 1000,
        imdbId: 'tt-movie-partial',
      );
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Example Series',
        season: 1,
        episode: 1,
        positionMs: 750,
        durationMs: 1000,
        imdbId: 'tt-series',
      );
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Example Series',
        season: 1,
        episode: 2,
        positionMs: 740,
        durationMs: 1000,
        imdbId: 'tt-series',
      );

      await StorageService.migrateExistingPlaybackCompletionThresholds();

      expect(await StorageService.isMovieFinished('tt-movie-done'), isTrue);
      expect(await StorageService.isMovieFinished('tt-movie-partial'), isFalse);
      expect(
        await StorageService.getVideoPlaybackState(videoTitle: 'Done Movie'),
        isNull,
      );
      expect(await StorageService.getVideoResume('Done Movie'), isNull);
      expect(
        await StorageService.getVideoPlaybackState(videoTitle: 'Partial Movie'),
        isNotNull,
      );
      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'Example Series',
          season: 1,
          episode: 1,
        ),
        isTrue,
      );
      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'Example Series',
          season: 1,
          episode: 2,
        ),
        isFalse,
      );
      expect(
        (await StorageService.getContinueWatchingItems())
            .map((item) => item['imdbId'])
            .toList(),
        ['tt-movie-partial'],
      );

      // The generation marker makes this a one-time adoption: changing the
      // threshold later must not retroactively migrate more old entries.
      await StorageService.setMovieCompletionThreshold(80);
      await StorageService.migrateExistingPlaybackCompletionThresholds();
      expect(await StorageService.isMovieFinished('tt-movie-partial'), isFalse);
    },
  );
}
