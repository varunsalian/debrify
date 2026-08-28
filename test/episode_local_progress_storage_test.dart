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

  // Regression: "Continue Watching is stuck on Friends S7E13". Marking an
  // episode watched and then unwatching it used to leave a zeroed row that won
  // "last played" forever — and each repeat of the cycle re-stamped it fresher,
  // so the obvious user fix made it stickier.
  test('unwatching a watched episode leaves no last-played ghost', () async {
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Ghost Show',
      season: 7,
      episode: 13,
      positionMs: 600,
      durationMs: 1000,
      imdbId: 'tt-ghost-show',
    );
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Ghost Show',
      season: 7,
      episode: 13,
      imdbId: 'tt-ghost-show',
    );
    await StorageService.unmarkEpisodeAsFinished(
      seriesTitle: 'Ghost Show',
      season: 7,
      episode: 13,
      imdbId: 'tt-ghost-show',
    );

    expect(
      await StorageService.getLastPlayedEpisodeByImdbId('tt-ghost-show'),
      isNull,
    );
    expect(
      await StorageService.getLastPlayedEpisode(seriesTitle: 'Ghost Show'),
      isNull,
    );
  });

  // Self-heal for installs already carrying a ghost minted by an older build
  // (including one that arrived over a phone→TV transfer): the row is the most
  // recently updated, so until it is purged it outranks real progress.
  test('the ghost purge lets real progress win last-played again', () async {
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Legacy Ghost Show',
      season: 1,
      episode: 2,
      positionMs: 500,
      durationMs: 1000,
      imdbId: 'tt-legacy-ghost',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2));
    // Newer, but carries no offset — exactly the shape the old unwatch left.
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Legacy Ghost Show',
      season: 7,
      episode: 13,
      positionMs: 0,
      durationMs: 1000,
      imdbId: 'tt-legacy-ghost',
    );
    expect(
      (await StorageService.getLastPlayedEpisodeByImdbId(
        'tt-legacy-ghost',
      ))?['episode'],
      13,
    );

    await StorageService.purgeUnwatchedResumeGhosts();

    final byId = await StorageService.getLastPlayedEpisodeByImdbId(
      'tt-legacy-ghost',
    );
    expect(byId?['season'], 1);
    expect(byId?['episode'], 2);

    final byTitle = await StorageService.getLastPlayedEpisode(
      seriesTitle: 'Legacy Ghost Show',
    );
    expect(byTitle?['season'], 1);
    expect(byTitle?['episode'], 2);
  });

  // A mark-only watch (never played) keeps the dummy 0ms/1ms shape and MUST
  // survive the purge — it is how "watched, so advance to the next episode"
  // reaches the reconciler.
  test('the ghost purge keeps mark-only watched episodes', () async {
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Mark Only Show',
      season: 3,
      episode: 5,
      imdbId: 'tt-mark-only',
    );
    // A watched episode that WAS played: position == duration, not a ghost.
    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Mark Only Show',
      season: 3,
      episode: 6,
      positionMs: 1000,
      durationMs: 1000,
      imdbId: 'tt-mark-only',
    );
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Mark Only Show',
      season: 3,
      episode: 6,
      imdbId: 'tt-mark-only',
    );

    await StorageService.purgeUnwatchedResumeGhosts();

    final finished = await StorageService.getMergedFinishedEpisodes(
      seriesTitle: 'Mark Only Show',
      imdbId: 'tt-mark-only',
    );
    expect(finished['3'], containsAll(<int>[5, 6]));

    final last = await StorageService.getLastPlayedEpisodeByImdbId(
      'tt-mark-only',
    );
    expect(last?['season'], 3);
    expect(last?['finished'], isTrue);
  });

  // A restore applies the package key-by-key, so a key the package omits keeps
  // its destination value. A pre-purge backup carries playback state but no
  // marker; without re-arming, a destination that already purged would keep
  // generation=1 and never inspect the ghosts it just imported.
  test('imported playback re-arms the ghost purge', () async {
    final overlay = <String, Object?>{
      'playback_state_v1': '{}',
      'some_other_setting': true,
    };

    StorageService.rearmGhostPurgeForImportedPlayback(overlay);

    expect(overlay['resume_ghost_purge_generation'], 0);
  });

  test('a package carrying its own purge marker is left alone', () async {
    final overlay = <String, Object?>{
      'playback_state_v1': '{}',
      'resume_ghost_purge_generation': 1,
    };

    StorageService.rearmGhostPurgeForImportedPlayback(overlay);

    expect(overlay['resume_ghost_purge_generation'], 1);
  });

  test('an overlay without playback state does not re-arm the purge', () async {
    final overlay = <String, Object?>{'some_other_setting': true};

    StorageService.rearmGhostPurgeForImportedPlayback(overlay);

    expect(overlay.containsKey('resume_ghost_purge_generation'), isFalse);
  });

  // The purge is bounded to one pass on purpose: a zero-position row is also
  // what a freshly-opened episode writes, and permanently ignoring that shape
  // would make a pack reopen the previous, already-watched episode.
  test('the ghost purge runs once and spares later fresh opens', () async {
    await StorageService.purgeUnwatchedResumeGhosts();

    await StorageService.saveSeriesPlaybackState(
      seriesTitle: 'Fresh Open Show',
      season: 2,
      episode: 4,
      positionMs: 0,
      durationMs: 1000,
      imdbId: 'tt-fresh-open',
    );
    await StorageService.purgeUnwatchedResumeGhosts();

    final last = await StorageService.getLastPlayedEpisodeByImdbId(
      'tt-fresh-open',
    );
    expect(last?['season'], 2);
    expect(last?['episode'], 4);
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
      // A completed row is DROPPED, not zeroed. Zeroing left a "played, 0% in,
      // not finished" row carrying a fresh updatedAt, which then won
      // `getLastPlayedEpisode*` and pinned Continue Watching to the episode the
      // user had just unwatched. Same treatment as the dummy alias below.
      final completedAlias = await StorageService.getEpisodeProgress(
        seriesTitle: 'Completed Release Alias',
      );
      expect(completedAlias, isNot(contains('1_4')));

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
