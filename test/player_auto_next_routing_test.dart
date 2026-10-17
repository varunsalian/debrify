import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'features/video_player/support/vp_source_reader.dart';

void main() {
  test(
    'EOF tries in-player next before Quick Play, after sleep and channel handling',
    () {
      final body = vpSourceDeclaration(
        '_VideoPlayerScreenState._onPlaybackEnded',
      );
      final fetch = body.indexOf(
        '_fetchNextEpisodeInPlayer(autoAdvance: true)',
      );
      final sleep = body.indexOf(
        '_sleep.sleepTimerMode == SleepTimerMode.endOfItem',
      );
      expect(sleep, isNonNegative);
      expect(fetch, isNonNegative);
      expect(fetch, greaterThan(sleep));
      expect(fetch, greaterThan(body.indexOf('if (_hasStremioTvNext)')));
      expect(
        fetch,
        greaterThan(body.indexOf('await _loadPlaylistIndex(nextIndex')),
      );
      expect(fetch, lessThan(body.indexOf('await _handleSeriesNextEpisode()')));
    },
  );

  test('manual next and EOF share the episode-fetch route', () {
    final body = vpSourceDeclaration(
      '_VideoPlayerScreenState._goToNextEpisode',
    );
    expect(body, contains('if (await _fetchNextEpisodeInPlayer()) return;'));
    final fetch = vpSourceDeclaration(
      '_VideoPlayerScreenState._fetchNextEpisodeInPlayer',
    );
    expect(fetch, contains('navigation != _episodeNavigationGeneration'));
    expect(fetch, contains('(autoAdvance && _sleepStopLatched)'));
    expect(fetch, contains('autoAdvance: autoAdvance'));
    expect(fetch, isNot(contains('Navigator.of(context).pop')));
  });

  test(
    'auto-fetched candidates suppress resume and respect sleep cancellation',
    () {
      final fetch = vpSourceDeclaration(
        '_VideoPlayerScreenState._fetchAndPlayEpisode',
      );
      final applied =
          (jsonDecode(
                File('dev/tool/dart_moves/vplayer_p17.json').readAsStringSync(),
              )
              as Map)['status'] ==
          'applied';
      final owner = applied ? '_host.' : '_';
      expect(fetch, contains('(!autoAdvance || !${owner}sleepStopLatched)'));
      final candidate = vpSourceDeclaration(
        '_VideoPlayerScreenState._tryEpisodeCandidate',
      );
      expect(candidate, contains('${owner}isAutoAdvancing = autoAdvance;'));
      expect(
        candidate,
        contains('suppressResume: autoAdvance || shuffleGeneration != null'),
      );
    },
  );
}
