import 'dart:convert';

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

  test(
    'merged lookup spans release titles and lets newer current title win',
    () async {
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Release Pack Name',
        season: 1,
        episode: 1,
        positionMs: 2000,
        durationMs: 10000,
        imdbId: 'tt-merged-show',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Catalog Show Name',
        season: 1,
        episode: 1,
        positionMs: 6000,
        durationMs: 10000,
        imdbId: 'tt-merged-show',
      );
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Release Pack Name',
        season: 1,
        episode: 2,
        positionMs: 3000,
        durationMs: 10000,
        imdbId: 'tt-merged-show',
      );

      final progress = await StorageService.getMergedEpisodeProgress(
        seriesTitle: 'Catalog Show Name',
        imdbId: 'TT-MERGED-SHOW',
      );

      expect(progress['1_1']?['positionMs'], 6000);
      expect(progress['1_2']?['positionMs'], 3000);
    },
  );

  test(
    'merged lookup lets a newer release alias beat older current title',
    () async {
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Catalog Show Name',
        season: 1,
        episode: 1,
        positionMs: 2000,
        durationMs: 10000,
        imdbId: 'tt-newer-alias',
      );
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'New Release Pack',
        season: 1,
        episode: 1,
        positionMs: 8000,
        durationMs: 10000,
        imdbId: 'tt-newer-alias',
      );

      final progress = await StorageService.getMergedEpisodeProgress(
        seriesTitle: 'Catalog Show Name',
        imdbId: 'tt-newer-alias',
      );

      expect(progress['1_1']?['positionMs'], 8000);
    },
  );

  test(
    'equal and missing timestamps deterministically prefer current title',
    () async {
      Map<String, dynamic> episode(int position, {int? updatedAt}) => {
        'positionMs': position,
        'durationMs': 10000,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };

      Map<String, dynamic> series(
        String title,
        Map<String, dynamic> episodes,
      ) => {
        'type': 'series',
        'title': title,
        'imdbId': 'tt-equal-progress',
        'seasons': {'1': episodes},
      };

      SharedPreferences.setMockInitialValues({
        'playback_state_v1': jsonEncode({
          'series_release_alias': series('Release Alias', {
            '1': episode(7000, updatedAt: 100),
            '2': episode(6000),
          }),
          'series_catalog_show': series('Catalog Show', {
            '1': episode(3000, updatedAt: 100),
            '2': episode(2000),
          }),
        }),
      });

      final progress = await StorageService.getMergedEpisodeProgress(
        seriesTitle: 'Catalog Show',
        imdbId: 'tt-equal-progress',
      );

      expect(progress['1_1']?['positionMs'], 3000);
      expect(progress['1_2']?['positionMs'], 2000);
    },
  );

  test('merged finished lookup unions alternate release titles', () async {
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Season One Release',
      season: 1,
      episode: 4,
      imdbId: 'tt-finished-show',
    );
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Catalog Show Name',
      season: 2,
      episode: 1,
      imdbId: 'tt-finished-show',
    );

    final finished = await StorageService.getMergedFinishedEpisodes(
      seriesTitle: 'Catalog Show Name',
      imdbId: 'tt-finished-show',
    );

    expect(finished['1'], contains(4));
    expect(finished['2'], contains(1));
  });

  test(
    'IMDb-aware unmark clears every completed alias and preserves partials',
    () async {
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Completed Release Alias',
        season: 1,
        episode: 4,
        positionMs: 600,
        durationMs: 1000,
        imdbId: 'tt-alias-unmark',
      );
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Completed Release Alias',
        season: 1,
        episode: 4,
        imdbId: 'tt-alias-unmark',
      );
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Dummy Release Alias',
        season: 1,
        episode: 4,
        imdbId: 'tt-alias-unmark',
      );
      // The current catalog title can predate IMDb persistence. Stable-id
      // unmarking must still include it, but must retain its genuine partial.
      await StorageService.saveSeriesPlaybackState(
        seriesTitle: 'Current Catalog Title',
        season: 1,
        episode: 4,
        positionMs: 400,
        durationMs: 1000,
      );
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Unrelated Show',
        season: 1,
        episode: 4,
        imdbId: 'tt-unrelated-show',
      );

      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'Current Catalog Title',
          season: 1,
          episode: 4,
          imdbId: 'TT-ALIAS-UNMARK',
        ),
        isTrue,
      );

      await StorageService.unmarkEpisodeAsFinished(
        seriesTitle: 'Current Catalog Title',
        season: 1,
        episode: 4,
        imdbId: 'TT-ALIAS-UNMARK',
      );

      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'Current Catalog Title',
          season: 1,
          episode: 4,
          imdbId: 'tt-alias-unmark',
        ),
        isFalse,
      );
      final completedAlias = await StorageService.getEpisodeProgress(
        seriesTitle: 'Completed Release Alias',
      );
      expect(completedAlias['1_4']?['positionMs'], 0);
      expect(completedAlias['1_4']?['durationMs'], 1000);

      final dummyAlias = await StorageService.getEpisodeProgress(
        seriesTitle: 'Dummy Release Alias',
      );
      expect(dummyAlias, isNot(contains('1_4')));

      final currentTitle = await StorageService.getEpisodeProgress(
        seriesTitle: 'Current Catalog Title',
      );
      expect(currentTitle['1_4']?['positionMs'], 400);
      expect(
        await StorageService.isEpisodeFinished(
          seriesTitle: 'Unrelated Show',
          season: 1,
          episode: 4,
          imdbId: 'tt-unrelated-show',
        ),
        isTrue,
      );
    },
  );
}
