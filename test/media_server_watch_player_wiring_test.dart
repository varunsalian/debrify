import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
    'lib/services/video_player_launcher.dart',
  ).readAsStringSync();
  final bridge = File(
    'lib/services/android_tv_player_bridge.dart',
  ).readAsStringSync();

  test(
    'Flutter prepares before opening, arms validation after asynchronous work',
    () {
      final open = between(
        flutter,
        'Future<void> commitOpen()',
        '// Startup direct fallbacks',
      );
      expect(
        open.indexOf('_serverWatch.prepare'),
        lessThan(open.indexOf('_player.open')),
      );
      expect(
        open.indexOf('beforeOpen()'),
        greaterThan(open.indexOf('_serverWatch.prepare')),
      );
      expect(
        open.indexOf('beforeOpen()'),
        greaterThan(open.indexOf('DirectSourceAuthorization.authorize')),
      );
      expect(open, contains('watchEpoch != _watchOpenEpoch'));
      final commit = between(
        flutter,
        'Future<void> _commitValidatedStremioSource',
        'String _startupSourceFields',
      );
      expect(
        commit.indexOf('_serverWatch.commit'),
        lessThan(commit.indexOf('commit == null')),
      );
    },
  );

  test(
    'Flutter watch reports respect validation, transitions and resume hold',
    () {
      final observe = between(
        flutter,
        'void _observeServerWatch',
        'Future<void> _saveResume(',
      );
      expect(observe, contains('!_serverWatch.isActive'));
      expect(observe, contains('_validationGateActive'));
      expect(observe, contains('_isTransitioning'));
      expect(observe, contains('heldTargetIfBlocked'));
      expect(observe, contains('final currentEpisode = _traktSeasonEpisode()'));
      expect(observe, contains('season: currentEpisode.season'));
      expect(observe, contains('episode: currentEpisode.episode'));
      final dispose = between(flutter, 'void dispose()', 'final replacedPip');
      expect(dispose, contains('_serverWatch.close()'));
      final eof = between(
        flutter,
        'Future<void> _onPlaybackEnded()',
        '// LIVE IPTV:',
      );
      expect(eof, contains('_observeServerWatch(completed: true)'));
      expect(eof, isNot(contains('_serverWatch.commit(null)')));
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
