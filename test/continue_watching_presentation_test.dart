import 'package:debrify/utils/continue_watching_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats episode and rounded remaining time for Spotlight', () {
    expect(
      continueWatchingCardSubtitle(episodeLabel: 'S2 · E5', minutesLeft: 24),
      'S2 · E5 · 24 min left',
    );
    expect(
      continueWatchingMinutesLeft(
        positionMs: 36 * Duration.millisecondsPerMinute,
        durationMs: 60 * Duration.millisecondsPerMinute + 1,
      ),
      25,
    );
    expect(
      continueWatchingMinutesLeftFromProgress(progress: 50, runtimeMinutes: 47),
      24,
    );
  });

  test('omits unavailable presentation facts', () {
    expect(continueWatchingCardSubtitle(), isNull);
    expect(
      continueWatchingMinutesLeft(positionMs: 0, durationMs: 3600000),
      isNull,
    );
    expect(
      continueWatchingMinutesLeftFromProgress(
        progress: 40,
        runtimeMinutes: null,
      ),
      isNull,
    );
  });

  test('selects and downsizes the requested Stremio episode still', () {
    final result = episodeThumbnailFromVideos(
      [
        {
          'season': 1,
          'number': 2,
          'thumbnail': 'https://episodes.metahub.space/tt123/1/2/w780.jpg',
        },
        {
          'season': 2,
          'number': 5,
          'thumbnail': 'https://episodes.metahub.space/tt123/2/5/w780.jpg',
        },
      ],
      season: 2,
      episode: 5,
    );

    expect(result, 'https://episodes.metahub.space/tt123/2/5/w500.jpg');
  });
}
