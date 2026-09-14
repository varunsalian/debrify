import 'dart:convert';
import 'package:debrify/services/local_series_completion_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
import 'package:debrify/services/watched_action_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  TraktSeason season(List<TraktEpisode> episodes) =>
      TraktSeason(number: 1, episodeCount: episodes.length, episodes: episodes);

  TraktEpisode episode(int number, DateTime released) => TraktEpisode(
    season: 1,
    number: number,
    title: 'Episode $number',
    firstAired: released.toUtc().toIso8601String(),
  );

  test(
    'reopening unchanged inventory keeps timestamp and emits no revision',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final episodes = [episode(1, DateTime.utc(2025))];
      await LocalSeriesCompletionService.instance.recordEpisodeInventory(
        imdbId: 'tt-noop',
        seriesTitle: 'Unchanged',
        seasons: [season(episodes)],
      );
      final state = jsonDecode(
        prefs.getString(StorageService.localSeriesCompletionStateKey)!,
      );
      state['tt-noop']['validatedAt'] = 123;
      state['tt-noop']['continueWatching'] = {
        'title': 'Unchanged',
        'posterUrl': 'poster',
      };
      final before = jsonEncode(state);
      await prefs.setString(
        StorageService.localSeriesCompletionStateKey,
        before,
      );
      final revision = StorageService.localCompletionRevision.value;
      await LocalSeriesCompletionService.instance.recordEpisodeInventory(
        imdbId: 'tt-noop',
        seriesTitle: 'Unchanged',
        seasons: [season(episodes)],
      );
      expect(
        prefs.getString(StorageService.localSeriesCompletionStateKey),
        before,
      );
      expect(StorageService.localCompletionRevision.value, revision);

      await LocalSeriesCompletionService.instance.recordEpisodeInventory(
        imdbId: 'tt-noop',
        seriesTitle: 'Renamed',
        seasons: [season(episodes)],
      );
      final changed = jsonDecode(
        prefs.getString(StorageService.localSeriesCompletionStateKey)!,
      )['tt-noop'];
      expect(changed['title'], 'Renamed');
      expect(changed['validatedAt'], isNot(123));
      expect(changed['continueWatching']['posterUrl'], 'poster');
      expect(
        StorageService.localCompletionRevision.value,
        greaterThan(revision),
      );
    },
  );

  test(
    'inventory comparison ignores ordering but persists release corrections',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final first = episode(1, DateTime.utc(2025));
      final second = episode(2, DateTime.utc(2025, 2));
      Future<void> record(List<TraktEpisode> episodes) =>
          LocalSeriesCompletionService.instance.recordEpisodeInventory(
            imdbId: 'tt-order',
            seriesTitle: 'Order',
            seasons: [season(episodes)],
          );
      await record([first, second]);
      final before = prefs.getString(
        StorageService.localSeriesCompletionStateKey,
      );
      final revision = StorageService.localCompletionRevision.value;
      await record([second, first]);
      expect(
        prefs.getString(StorageService.localSeriesCompletionStateKey),
        before,
      );
      expect(StorageService.localCompletionRevision.value, revision);
      await record([first, episode(2, DateTime.utc(2025, 3))]);
      final state = jsonDecode(
        prefs.getString(StorageService.localSeriesCompletionStateKey)!,
      );
      expect(
        state['tt-order']['episodes']['1-2'],
        DateTime.utc(2025, 3).millisecondsSinceEpoch,
      );
      expect(
        StorageService.localCompletionRevision.value,
        greaterThan(revision),
      );
    },
  );

  test(
    'series is caught up when every aired regular episode is finished',
    () async {
      final now = DateTime.now();
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt-local-show',
        title: 'Local Show',
        contentType: 'series',
        posterUrl: 'https://example.com/poster.jpg',
      );
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Local Show',
        season: 1,
        episode: 1,
        imdbId: 'tt-local-show',
      );

      await LocalSeriesCompletionService.instance.recordEpisodeInventory(
        imdbId: 'tt-local-show',
        seriesTitle: 'Local Show',
        seasons: [
          season([
            episode(1, now.subtract(const Duration(days: 7))),
            episode(2, now.add(const Duration(days: 7))),
          ]),
        ],
      );

      expect(
        await LocalSeriesCompletionService.instance.caughtUpIds(),
        contains('tt-local-show'),
      );
      expect(await StorageService.getContinueWatchingItems(), isEmpty);

      await StorageService.unmarkEpisodeAsFinished(
        seriesTitle: 'Local Show',
        season: 1,
        episode: 1,
      );
      expect(
        await LocalSeriesCompletionService.instance.caughtUpIds(),
        isNot(contains('tt-local-show')),
      );
      expect(
        await StorageService.getContinueWatchingItems(),
        contains(
          predicate<Map<String, dynamic>>((item) {
            return item['imdbId'] == 'tt-local-show' &&
                item['posterUrl'] == 'https://example.com/poster.jpg';
          }),
        ),
      );
    },
  );

  test('newly aired unwatched episode clears local caught-up status', () async {
    final now = DateTime.now();
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Returning Show',
      season: 1,
      episode: 1,
      imdbId: 'tt-returning-show',
    );

    await LocalSeriesCompletionService.instance.recordEpisodeInventory(
      imdbId: 'tt-returning-show',
      seriesTitle: 'Returning Show',
      seasons: [
        season([
          episode(1, now.subtract(const Duration(days: 14))),
          episode(2, now.subtract(const Duration(hours: 1))),
        ]),
      ],
    );

    expect(
      await LocalSeriesCompletionService.instance.caughtUpIds(),
      isNot(contains('tt-returning-show')),
    );
  });

  test('series-level unwatch clears derived local completion', () async {
    final now = DateTime.now();
    await StorageService.setTrackingScrobbleTargets(<TrackingSource>{
      TrackingSource.local,
    });
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Unwatched Show',
      season: 1,
      episode: 1,
    );
    await LocalSeriesCompletionService.instance.recordEpisodeInventory(
      imdbId: 'tt-unwatched-show',
      seriesTitle: 'Unwatched Show',
      seasons: [
        season([episode(1, now.subtract(const Duration(days: 1)))]),
      ],
    );
    await StorageService.setSeriesExplicitlyWatched(
      'tt-unwatched-show',
      watched: true,
    );
    expect(
      await LocalSeriesCompletionService.instance.caughtUpIds(),
      contains('tt-unwatched-show'),
    );
    expect(
      await StorageService.getFinishedEpisodes(seriesTitle: 'Unwatched Show'),
      isNotEmpty,
    );

    final result = await WatchedActionCoordinator.setTitleWatched(
      imdbId: 'tt-unwatched-show',
      contentType: 'series',
      watched: false,
    );

    expect(result.success, isTrue);
    expect(
      await StorageService.getExplicitlyWatchedSeriesIds(),
      isNot(contains('tt-unwatched-show')),
    );
    expect(
      await StorageService.getFinishedEpisodes(seriesTitle: 'Unwatched Show'),
      isEmpty,
    );
    expect(
      await LocalSeriesCompletionService.instance.caughtUpIds(),
      isNot(contains('tt-unwatched-show')),
    );
  });

  test(
    'Simkl calendar keeps future episode pending then clears at air time',
    () async {
      final now = DateTime.now();
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Calendar Show',
        season: 1,
        episode: 1,
        imdbId: 'tt-calendar-show',
      );
      await LocalSeriesCompletionService.instance.recordEpisodeInventory(
        imdbId: 'tt-calendar-show',
        seriesTitle: 'Calendar Show',
        seasons: [
          season([episode(1, now.subtract(const Duration(days: 2)))]),
        ],
      );

      List<dynamic> calendar(DateTime date) => [
        {
          'date': date.toUtc().toIso8601String(),
          'ids': {'imdb': 'tt-calendar-show'},
          'episode': {'season': 1, 'episode': 2},
        },
      ];

      expect(
        await LocalSeriesCompletionService.instance.debugMergeCalendarItems(
          calendar(now.add(const Duration(days: 2))),
        ),
        contains('tt-calendar-show'),
      );
      final revisionBefore = StorageService.localCompletionRevision.value;
      expect(
        await LocalSeriesCompletionService.instance.debugMergeCalendarItems(
          calendar(now.subtract(const Duration(minutes: 1))),
        ),
        isNot(contains('tt-calendar-show')),
      );
      expect(
        StorageService.localCompletionRevision.value,
        greaterThan(revisionBefore),
      );
    },
  );

  test('specials do not block local series completion', () async {
    final now = DateTime.now();
    await StorageService.markEpisodeAsFinished(
      seriesTitle: 'Special Show',
      season: 1,
      episode: 1,
      imdbId: 'tt-special-show',
    );
    final special = TraktSeason(
      number: 0,
      episodeCount: 1,
      episodes: [episode(1, now.subtract(const Duration(days: 1)))],
    );

    await LocalSeriesCompletionService.instance.recordEpisodeInventory(
      imdbId: 'tt-special-show',
      seriesTitle: 'Special Show',
      seasons: [
        special,
        season([episode(1, now.subtract(const Duration(days: 2)))]),
      ],
    );

    expect(
      await LocalSeriesCompletionService.instance.caughtUpIds(),
      contains('tt-special-show'),
    );
  });

  test('calendar catch-up includes every elapsed recent month', () {
    final urls = LocalSeriesCompletionService.instance.debugCalendarFeedUrls(
      checkedAt: DateTime.utc(2026, 6, 29).millisecondsSinceEpoch,
      now: DateTime.utc(2026, 8, 18).millisecondsSinceEpoch,
    );

    expect(urls, contains('https://data.simkl.in/calendar/2026/6/tv.json'));
    expect(urls, contains('https://data.simkl.in/calendar/2026/7/anime.json'));
    expect(urls, contains('https://data.simkl.in/calendar/2026/8/tv.json'));
  });
}
