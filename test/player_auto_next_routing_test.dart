import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'features/video_player/support/vp_source_reader.dart';

/// Phase 18 moved the EOF ladder, manual Next and adjacency into collaborators
/// that reach State members through their Host.
bool _p18Applied() =>
    (jsonDecode(File('dev/tool/dart_moves/vplayer_p18.json').readAsStringSync())
        as Map)['status'] ==
    'applied';

void main() {
  test(
    'EOF tries in-player next before Quick Play, after sleep and channel handling',
    () {
      final moved = _p18Applied();
      String o(String name) => moved ? '_host.$name' : '_$name';
      final body = vpSourceDeclaration(
        '_VideoPlayerScreenState._onPlaybackEnded',
      );
      final fetch = body.indexOf(
        '${o('fetchNextEpisodeInPlayer')}(autoAdvance: true)',
      );
      final sleep = body.indexOf(
        '${moved ? '_host.' : '_sleep.'}sleepTimerMode == SleepTimerMode.endOfItem',
      );
      final channel = body.indexOf('if (${o('hasStremioTvNext')})');
      final playlist = body.indexOf(
        'await ${o('loadPlaylistIndex')}(nextIndex',
      );
      final handoff = body.indexOf('await ${o('handleSeriesNextEpisode')}()');
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
    final moved = _p18Applied();
    String o(String name) => moved ? '_host.$name' : '_$name';
    final body = vpSourceDeclaration(
      '_VideoPlayerScreenState._goToNextEpisode',
    );
    expect(
      body,
      contains('if (await ${o('fetchNextEpisodeInPlayer')}()) return;'),
    );
    final fetch = vpSourceDeclaration(
      '_VideoPlayerScreenState._fetchNextEpisodeInPlayer',
    );
    expect(
      fetch,
      contains('navigation != ${o('episodeNavigationGeneration')}'),
    );
    expect(fetch, contains('(autoAdvance && ${o('sleepStopLatched')})'));
    expect(fetch, contains('autoAdvance: autoAdvance'));
    expect(fetch, isNot(contains('Navigator.of(context).pop')));
    expect(fetch, isNot(contains('Navigator.of(_host.context).pop')));
    expect(fetch, isNot(contains('.pop(')));
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
