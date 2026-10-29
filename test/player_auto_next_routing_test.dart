import 'package:flutter_test/flutter_test.dart';

import 'support/lib_source.dart';

const _vp = 'lib/features/video_player/presentation/legacy_video_player';

/// The EOF ladder, manual Next and adjacency live in collaborators that reach
/// State members through their Host.
String _o(String name) => '_host.$name';

void main() {
  test(
    'EOF tries in-player next before Quick Play, after sleep and channel handling',
    () {
      final body = libMember(
        '$_vp/vp_playback_ended.dart',
        'onPlaybackEnded',
        owner: 'VpPlaybackEnded',
      );
      final fetch = body.indexOf(
        '${_o('fetchNextEpisodeInPlayer')}(autoAdvance: true)',
      );
      final sleep = body.indexOf(
        '_host.sleepTimerMode == SleepTimerMode.endOfItem',
      );
      final channel = body.indexOf('if (${_o('hasStremioTvNext')})');
      final playlist = body.indexOf(
        'await ${_o('loadPlaylistIndex')}(nextIndex',
      );
      final handoff = body.indexOf('await ${_o('handleSeriesNextEpisode')}()');
      expect(sleep, isNonNegative);
      expect(fetch, isNonNegative);
      expect(channel, isNonNegative);
      expect(playlist, isNonNegative);
      expect(handoff, isNonNegative);
      expect(fetch, greaterThan(sleep));
      expect(fetch, greaterThan(channel));
      expect(fetch, greaterThan(playlist));
      expect(fetch, lessThan(handoff));
    },
  );

  test('manual next and EOF share the episode-fetch route', () {
    final body = libMember(
      '$_vp/vp_episode_next.dart',
      'goToNextEpisode',
      owner: 'VpEpisodeNext',
    );
    expect(
      body,
      contains('if (await ${_o('fetchNextEpisodeInPlayer')}()) return;'),
    );
    final fetch = libMember(
      '$_vp/vp_episode_adjacent.dart',
      'fetchNextEpisodeInPlayer',
      owner: 'VpEpisodeAdjacent',
    );
    expect(
      fetch,
      contains('navigation != ${_o('episodeNavigationGeneration')}'),
    );
    expect(fetch, contains('(autoAdvance && ${_o('sleepStopLatched')})'));
    expect(fetch, contains('autoAdvance: autoAdvance'));
    expect(fetch, isNot(contains('Navigator.of(context).pop')));
    expect(fetch, isNot(contains('Navigator.of(_host.context).pop')));
    expect(fetch, isNot(contains('.pop(')));
  });

  test(
    'auto-fetched candidates suppress resume and respect sleep cancellation',
    () {
      final fetch = libMember(
        '$_vp/vp_episode_fetch.dart',
        'fetchAndPlayEpisode',
        owner: 'VpEpisodeFetch',
      );
      const owner = '_host.';
      expect(fetch, contains('(!autoAdvance || !${owner}sleepStopLatched)'));
      final candidate = libMember(
        '$_vp/vp_episode_fetch.dart',
        'tryEpisodeCandidate',
        owner: 'VpEpisodeFetch',
      );
      expect(candidate, contains('${owner}isAutoAdvancing = autoAdvance;'));
      expect(
        candidate,
        contains('suppressResume: autoAdvance || shuffleGeneration != null'),
      );
    },
  );
}
