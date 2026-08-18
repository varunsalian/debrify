import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
}
