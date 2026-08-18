import 'package:debrify/services/local_series_completion_service.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/trakt/trakt_episode_model.dart';
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
