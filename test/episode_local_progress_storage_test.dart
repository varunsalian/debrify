import 'package:debrify/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('IMDb lookup merges every legacy series-title record', () async {
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Show Release Title A',
      season: 1,
      episode: 1,
      positionMs: 1000,
      durationMs: 10000,
      imdbId: 'tt-legacy-show',
    );
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Alternate Show Title B',
      season: 1,
      episode: 2,
      positionMs: 2000,
      durationMs: 10000,
      imdbId: 'tt-legacy-show',
    );

    final progress = await StorageService.getEpisodeProgressByImdbId(
      'tt-legacy-show',
    );

    expect(progress.keys, containsAll(<String>['1_1', '1_2']));
    expect(progress['1_1']?['positionMs'], 1000);
    expect(progress['1_2']?['positionMs'], 2000);
  });

  test('IMDb lookup keeps the newest duplicate episode state', () async {
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Old Release Title',
      season: 2,
      episode: 3,
      positionMs: 3000,
      durationMs: 10000,
      imdbId: 'tt-duplicate-show',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'New Release Title',
      season: 2,
      episode: 3,
      positionMs: 7000,
      durationMs: 10000,
      imdbId: 'tt-duplicate-show',
    );

    final progress = await StorageService.getEpisodeProgressByImdbId(
      'tt-duplicate-show',
    );

    expect(progress['2_3']?['positionMs'], 7000);
  });
}
