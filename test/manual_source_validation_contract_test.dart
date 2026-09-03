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
  final playerBridge = File(
    'lib/services/android_tv_player_bridge.dart',
  ).readAsStringSync();
  final playbackService = File(
    'lib/services/torrent_playback_service.dart',
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
    // The gate moved into _resumeSaveBlocked when saves became serialized;
    // the contract follows the indirection: every save path consults the
    // blocker, and the blocker still enforces the validation gate.
    final resumeBlocked = _between(
      flutterPlayer,
      'bool _resumeSaveBlocked(',
      'Future<void> _saveResume(',
    );

    expect(ended, contains('if (_validationGateActive) return;'));
    expect(resume, contains('_resumeSaveBlocked'));
    expect(resumeBlocked, contains('_validationGateActive'));
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

  test('Flutter startup failures retain pins and still recover', () {
    final startup = _between(
      flutterPlayer,
      'Future<bool> _openInitialVodWithFailover(',
      'Future<void> _commitValidatedStremioSource(',
    );
    final directBinding = _between(
      playbackService,
      '// Addon-direct pins store provenance',
      '// Cheap skip: a bound DEBRID source',
    );

    expect(startup, isNot(contains('_reportRejectedStremioSource')));
    expect(flutterPlayer, contains("'startupSourcesExhausted': true"));
    expect(playbackService, isNot(contains('_rejectedDirectSourceHandler')));
    expect(directBinding, isNot(contains('removeSourceEntry(imdbId, source)')));
    expect(playbackService, contains('remainingSources'));
    expect(playbackService, contains('skipBoundSources: true'));
  });

  test('bound startup recovery retains the preferred provider', () {
    final selection = _between(
      playbackService,
      'static Future<void> playFromSelection(',
      'static Future<FilterLadder> loadLadder(',
    );
    final boundPlayback = _between(
      playbackService,
      'static Future<bool> _playViaBound(',
      '/// Continue after a saved source resolved successfully',
    );
    final recovery = _between(
      playbackService,
      'static Future<void> _recoverAfterBoundStartupFailure(',
      '/// Pin [torrent] as the playback source',
    );

    expect(
      RegExp(
        r'_playViaBound\([\s\S]*?preferredProvider: preferredProvider',
      ).hasMatch(selection),
      isTrue,
    );
    expect(boundPlayback, contains('String? preferredProvider'));
    expect(
      RegExp(
        r'_recoverAfterBoundStartupFailure\([\s\S]*?preferredProvider: preferredProvider',
      ).allMatches(boundPlayback),
      hasLength(3),
    );
    expect(recovery, contains('String? preferredProvider'));
    expect(recovery, contains('preferredProvider: preferredProvider'));
    expect(recovery, contains('skipBoundSources: true'));
  });

  test('Android TV reports exhaustion without deleting failed source pins', () {
    final startupFailure = _between(
      nativePlayer,
      'private fun failStartupCandidate(',
      'private fun failStartupResolution(',
    );

    expect(startupFailure, isNot(contains('reportRejectedSource')));
    expect(startupFailure, contains('startupSourcesExhausted = true'));
    expect(nativePlayer, contains('result["startupSourcesExhausted"] = true'));
    expect(playerBridge, isNot(contains("case 'rejectStremioSource':")));
    expect(
      playerBridge,
      contains("finishedArgs['startupSourcesExhausted'] == true"),
    );
  });

  test('Android TV source commits are bounded and session scoped', () {
    expect(playerBridge, contains('class _StremioSourcePersistenceSession'));
    expect(playerBridge, contains('operation().timeout(timeout)'));
    expect(playerBridge, contains('_tail.timeout(timeout)'));
    expect(
      playerBridge,
      contains("payloadWithFont['sourcePersistenceSessionId']"),
    );
    expect(
      nativePlayer,
      contains('"sourcePersistenceSessionId" to sourcePersistenceSessionId'),
    );
    expect(
      nativePlayer,
      contains('payloadCheck.optInt("sourcePersistenceSessionId", 0)'),
    );
    expect(playerBridge, contains('ignoring stale playback finish'));
  });

  test('delayed startup recovery waits for the exact player route', () {
    expect(
      flutterPlayer,
      contains('final playerRoute = ModalRoute.of(context)'),
    );
    expect(flutterPlayer, contains('mounted && playerRoute?.isActive == true'));
    expect(
      flutterPlayer,
      contains('mounted && playerRoute?.isCurrent == true'),
    );
  });
}
