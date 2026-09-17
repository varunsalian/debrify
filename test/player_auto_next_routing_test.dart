import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File(
    'lib/screens/video_player_screen.dart',
  ).readAsStringSync();
  String section(String start, String end) {
    final from = source.indexOf(start);
    final to = source.indexOf(end, from + start.length);
    expect(from, isNonNegative);
    expect(to, greaterThan(from));
    return source.substring(from, to);
  }

  test(
    'EOF tries in-player next before Quick Play, after sleep and channel handling',
    () {
      final body = section(
        'Future<void> _onPlaybackEnded()',
        'void _startTransitionOverlay()',
      );
      final fetch = body.indexOf(
        '_fetchNextEpisodeInPlayer(autoAdvance: true)',
      );
      expect(
        fetch,
        greaterThan(
          body.indexOf('_sleepTimerMode == SleepTimerMode.endOfItem'),
        ),
      );
      expect(fetch, greaterThan(body.indexOf('if (_hasStremioTvNext)')));
      expect(
        fetch,
        greaterThan(body.indexOf('await _loadPlaylistIndex(nextIndex')),
      );
      expect(fetch, lessThan(body.indexOf('await _handleSeriesNextEpisode()')));
    },
  );

  test('manual next and EOF share the episode-fetch route', () {
    final body = section(
      'Future<void> _goToNextEpisode()',
      'Future<bool> _fetchNextEpisodeInPlayer(',
    );
    expect(body, contains('if (await _fetchNextEpisodeInPlayer()) return;'));
    final fetch = section(
      'Future<bool> _fetchNextEpisodeInPlayer(',
      'Future<bool> _handleSeriesNextEpisode()',
    );
    expect(fetch, contains('navigation != _episodeNavigationGeneration'));
    expect(fetch, contains('(autoAdvance && _sleepStopLatched)'));
    expect(fetch, contains('autoAdvance: autoAdvance'));
    expect(fetch, isNot(contains('Navigator.of(context).pop')));
  });

  test(
    'auto-fetched candidates suppress resume and respect sleep cancellation',
    () {
      final fetch = section(
        'Future<EpisodePlaybackOutcome> _fetchAndPlayEpisode(',
        'Future<EpisodePlaybackOutcome> _tryEpisodeCandidate(',
      );
      expect(fetch, contains('(!autoAdvance || !_sleepStopLatched)'));
      final candidate = section(
        'Future<EpisodePlaybackOutcome> _tryEpisodeCandidate(',
        'Future<void> _showPlaylistSheet(',
      );
      expect(candidate, contains('_isAutoAdvancing = autoAdvance;'));
      expect(
        candidate,
        contains('suppressResume: autoAdvance || shuffleGeneration != null'),
      );
    },
  );
}
