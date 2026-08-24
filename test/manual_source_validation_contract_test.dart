import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _between(String source, String start, String end) {
  final from = source.indexOf(start);
  expect(from, isNonNegative, reason: 'Missing start marker: $start');
  final to = source.indexOf(end, from + start.length);
  expect(to, greaterThan(from), reason: 'Missing end marker: $end');
  return source.substring(from, to);
}

void main() {
  final flutterPlayer = File(
    'lib/screens/video_player_screen.dart',
  ).readAsStringSync();
  final nativePlayer = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt',
  ).readAsStringSync();

  test(
    'Flutter explicit source picks validate only the selected candidate',
    () {
      final selection = _between(
        flutterPlayer,
        'Future<void> _handleSourceSelected(',
        'Future<void> _switchToSourcePlaylist(',
      );
      final directSwitch = _between(
        flutterPlayer,
        'Future<void> _switchToStremioSource(',
        '// ─── Stremio TV Guide',
      );

      expect(selection, contains('validateExplicitSelection: true'));
      expect(directSwitch, contains('_tryOpenStartupVod('));
      expect(directSwitch, contains('previous source restore failed'));
      expect(directSwitch, isNot(contains('_tryStartupSourceFailover(')));
      expect(
        directSwitch,
        contains('This source is unavailable. Choose another source.'),
      );
    },
  );

  test('Flutter rejected candidates cannot complete or scrobble', () {
    final ended = _between(
      flutterPlayer,
      'Future<void> _onPlaybackEnded()',
      'void _startTransitionOverlay()',
    );
    final resume = _between(
      flutterPlayer,
      'Future<void> _saveResume(',
      'bool _tvAutoHideBlocked',
    );

    expect(ended, contains('if (_validationGateActive) return;'));
    expect(resume, contains('_validationGateActive'));
    expect(
      flutterPlayer,
      contains('void _resumeTrackingAfterValidationGate()'),
    );
  });

  test('Flutter failed playlist picks restore an outgoing direct stream', () {
    final playlistSwitch = _between(
      flutterPlayer,
      'Future<void> _switchToSourcePlaylist(',
      'Future<void> _switchToStremioSource(',
    );

    expect(playlistSwitch, contains('final outgoingDirectUrl'));
    expect(playlistSwitch, contains('_activePlaylist = null'));
    expect(playlistSwitch, contains('mk.Media(outgoingDirectUrl'));
    expect(playlistSwitch, contains('_currentStreamUrl = outgoingDirectUrl'));
  });

  test('PikPak keeps cold-storage retries but reports manual exhaustion', () {
    final playlistLoad = _between(
      flutterPlayer,
      'Future<bool> _loadPlaylistIndex(',
      'Future<String> _resolvePlaylistEntryUrl(',
    );
    final pikPakRetry = _between(
      flutterPlayer,
      'Future<bool> _playPikPakVideoWithRetry(',
      'Future<void> _preloadEpisodeInfo(',
    );

    expect(playlistLoad, contains('final pikPakLoaded'));
    expect(
      playlistLoad,
      contains('manualValidationSourceIndex != null && !pikPakLoaded'),
    );
    expect(pikPakRetry, contains('while (attempt <= maxRetries)'));
    expect(pikPakRetry, contains('return true;'));
    expect(
      pikPakRetry,
      contains('return false; // Exhausted the cold-storage retries.'),
    );
  });

  test(
    'Android TV rejects one manual candidate and restores without failover',
    () {
      final selection = _between(
        nativePlayer,
        'private fun onStremioSourceSelected(',
        'private fun resolveStremioSourceViaFlutter(',
      );
      final reject = _between(
        nativePlayer,
        'private fun failManualSourceCandidate(',
        'private fun armStartupCandidate(',
      );

      expect(reject, contains('manualSourceRestoreInProgress = true'));
      expect(reject, contains('playItem(currentIndex, suppressTrakt = true)'));
      expect(reject, contains('putAll(snapshot.perItemImdbIds)'));
      expect(
        reject,
        contains('This source is unavailable — choose another source'),
      );
      expect(reject, isNot(contains('nextIndex(')));
      expect(reject, isNot(contains('onStremioSourceSelected(')));
      expect(selection, contains('maxAttempts = 1'));
    },
  );

  test('Android TV gates progress and invalidates late manual resolution', () {
    final resolver = _between(
      nativePlayer,
      'private fun resolveAndPlay(',
      'private fun startPlayback(',
    );
    final progress = _between(
      nativePlayer,
      'private fun sendProgress(',
      'private fun commitStartupCandidate(',
    );

    expect(resolver, contains('reason=stale_manual_token'));
    expect(resolver, contains('failManualSourceCandidate("initial-resolve")'));
    expect(progress, contains('manualSourceSwitchSnapshot != null'));
    expect(progress, contains('manualSourceRestoreInProgress'));
  });

  test('manual series packs must contain the selected episode', () {
    expect(
      nativePlayer,
      contains(
        '(requireExactStartupEpisode || manualSourceSwitchSnapshot != null)',
      ),
    );
    expect(flutterPlayer, contains('containsRequestedEpisode = false'));
    expect(flutterPlayer, contains('if (containsRequestedEpisode)'));
  });
}
