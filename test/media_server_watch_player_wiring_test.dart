import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/lib_source.dart';

const _vp = 'lib/features/video_player/presentation/legacy_video_player';

String between(String source, String start, String end) {
  final first = source.indexOf(start);
  expect(first, isNonNegative);
  final last = source.indexOf(end, first + start.length);
  expect(last, greaterThan(first));
  return source.substring(first, last);
}

void main() {
  final flutter = File(
    'lib/screens/video_player_screen.dart',
  ).readAsStringSync();
  final native = File(
    'lib/features/player_launch/data/android_tv_native_launch.dart',
  ).readAsStringSync();
  final bridge = File(
    'lib/services/android_tv_player_bridge.dart',
  ).readAsStringSync();

  test(
    'Flutter prepares before opening, arms validation after asynchronous work',
    () {
      // `_openMedia` lives in VpMediaOpen; State members are reached through
      // its Host.
      const host = '_host.';
      final open = between(
        libMember('$_vp/vp_media_open.dart', 'openMedia', owner: 'VpMediaOpen'),
        'Future<void> commitOpen()',
        '// Startup direct fallbacks',
      );
      final prepare = open.indexOf('${host}serverWatch.prepare');
      final playerOpen = open.indexOf('${host}player.open');
      final authorize = open.indexOf('DirectSourceAuthorization.authorize');
      expect(prepare, isNonNegative);
      expect(playerOpen, isNonNegative);
      expect(authorize, isNonNegative);
      expect(prepare, lessThan(playerOpen));
      expect(open.indexOf('beforeOpen()'), greaterThan(prepare));
      expect(open.indexOf('beforeOpen()'), greaterThan(authorize));
      expect(open, contains('watchEpoch != ${host}watchOpenEpoch'));
      final commit = libMember(
        '$_vp/vp_startup_candidates.dart',
        'commitValidatedStremioSource',
        owner: 'VpStartupCandidates',
      );
      // P16 moved the commit into VpStartupCandidates; the State-owned watch
      // controller is reached through its facade Host.
      final watchCommit = commit.indexOf('_host.serverWatch.commit');
      final optionalCallback = commit.indexOf('commit == null');
      expect(watchCommit, isNonNegative);
      expect(optionalCallback, greaterThan(watchCommit));
    },
  );

  test(
    'Flutter watch reports respect validation, transitions and resume hold',
    () {
      final observe = libMember(
        '$_vp/vp_resume_save.dart',
        'observeServerWatch',
        owner: 'VpResumeSave',
      );
      const fields = '_host.';
      expect(observe, contains('void observeServerWatch('));
      expect(observe, contains('!${fields}serverWatch.isActive'));
      expect(observe, contains('${fields}validationGateActive'));
      expect(observe, contains('${fields}isTransitioning'));
      expect(observe, contains('heldTargetIfBlocked'));
      expect(
        observe,
        contains('final currentEpisode = ${fields}traktSeasonEpisode()'),
      );
      expect(observe, contains('season: currentEpisode.season'));
      expect(observe, contains('episode: currentEpisode.episode'));
      final dispose = between(flutter, 'void dispose()', 'final replacedPip');
      expect(dispose, contains('_serverWatch.close()'));
      final observation = dispose.indexOf('observeServerWatch(');
      final closing = dispose.indexOf('_serverWatch.close()');
      expect(observation, isNonNegative);
      expect(closing, greaterThan(observation));
      final eof = libMember(
        '$_vp/vp_playback_ended.dart',
        'onPlaybackEnded',
        owner: 'VpPlaybackEnded',
      );
      final live = eof.indexOf('// LIVE IPTV:');
      final watch = eof.indexOf('_host.observeServerWatch(completed: true)');
      expect(live, isNonNegative);
      expect(watch, isNonNegative);
      expect(watch, lessThan(live));
      expect(eof, isNot(contains('_serverWatch.commit(null)')));
      expect(eof, isNot(contains('serverWatch.commit(null)')));
      expect(eof, isNot(contains('commitServerWatch(null)')));
    },
  );

  test(
    'native imports before payload resume lookup and commits independently of pins',
    () {
      final launch = between(
        native,
        'final serverWatch = MediaServerWatchController()',
        '// Async TVMaze metadata fetch',
      );
      expect(
        launch.indexOf('serverWatch.prepare'),
        lessThan(launch.indexOf('builder.build()')),
      );
      final commit = between(
        launch,
        'final sourceCommitterForTv',
        '// "Load more sources"',
      );
      expect(commit, isNot(contains('serverWatch.commit')));
      final progressCommit = between(
        launch,
        'onCommitPlaybackProgressSource:',
        'onStartupSourcesExhausted:',
      );
      expect(
        progressCommit,
        contains('serverWatch.commit(currentStremioSources[sourceIndex])'),
      );
      final dispatch = between(
        bridge,
        "case 'commitStremioSource':",
        "case 'startupSourceFailed':",
      );
      expect(
        dispatch.indexOf('enqueueSourceCommit('),
        lessThan(dispatch.indexOf('await persistenceSession.enqueue')),
      );
      expect(
        bridge,
        contains('onSourceCommitted: onCommitPlaybackProgressSource'),
      );
      final progress = between(
        launch,
        'onProgress: (progress)',
        'onRequestStream:',
      );
      expect(progress, contains("progress['sourceIndex']"));
      expect(progress, contains('serverWatch.observe('));
      expect(progress, contains('serverWatch.close()'));
      expect(progress, contains('season: season'));
      expect(progress, contains('episode: episode'));
    },
  );
}
