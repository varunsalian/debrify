import 'package:debrify/services/debrify_tv_database.dart';
import 'package:debrify/services/iptv_media_store.dart';
import 'package:debrify/services/storage_service.dart';
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
