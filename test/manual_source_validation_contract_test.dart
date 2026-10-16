import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'features/video_player/support/vp_source_reader.dart';

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
  final nativePlaybackStart = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/TvPlaybackStartController.kt',
  ).readAsStringSync();
  final nativeSourceFetch = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/TvSourceFetchController.kt',
  ).readAsStringSync();
  final nativeSourceSwitcher = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/TvSourceSwitchController.kt',
  ).readAsStringSync();
  final nativeSourceApplier = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/TvSourceSwitchApplier.kt',
  ).readAsStringSync();
  final nativeStartupGate = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/TvStartupGateController.kt',
  ).readAsStringSync();
  final nativeProgressReporter = File(
    'android/app/src/main/kotlin/com/debrify/app/tv/TvProgressReporter.kt',
  ).readAsStringSync();
  final playerBridge = File(
    'lib/services/android_tv_player_bridge.dart',
  ).readAsStringSync();
  final boundPlaybackCode = File(
    'lib/features/sources/presentation/legacy_playback/bound_source_playback.dart',
  ).readAsStringSync();
  final recoveryResolution = File(
    'lib/features/sources/data/recovery_source_resolution.dart',
  ).readAsStringSync();
  final automaticSelection = File(
    'lib/features/sources/presentation/legacy_playback/automatic_play_selection.dart',
  ).readAsStringSync();
  final playerLaunch = File(
    'lib/features/sources/presentation/legacy_playback/source_player_launch.dart',
  ).readAsStringSync();
  final bindingActions = File(
    'lib/features/sources/presentation/legacy_playback/source_binding_actions.dart',
  ).readAsStringSync();
  final launcher = File(
    'lib/features/player_launch/presentation/legacy_launch/launch_router.dart',
  ).readAsStringSync();
  final nativeLauncher = File(
    'lib/features/player_launch/data/android_tv_native_launch.dart',
  ).readAsStringSync();

  test('both automatic tracker launch copies retain saved-source recovery', () {
    final copies = launcher
        .split('args = VideoPlayerLaunchArgs(')
        .skip(1)
        .where((copy) => copy.trimLeft().startsWith('videoUrl: args.videoUrl'))
        .toList();
    expect(copies, hasLength(2));
    for (final copy in copies) {
      final arguments = copy.split(');').first;
      expect(
        arguments,
        contains(
          'startupHasRemainingSavedSources: args.startupHasRemainingSavedSources',
        ),
      );
      expect(
        arguments,
        contains('startupResolverProvider: args.startupResolverProvider'),
      );
    }
  });

  test(
    'recovery uses automatic probes without changing manual source resolution',
    () {
      expect(
        nativeSourceSwitcher,
        contains(
          '"automaticRecovery" to (host.startupFailoverDispatching && host.startupRecoveryCandidateIndices != null)',
        ),
      );
      expect(
        playerBridge,
        contains("playlistRequest['automaticRecovery'] == true"),
      );
      expect(
        playerBridge,
        contains('_startupSourcePlaylistResolver ?? _sourcePlaylistResolver'),
      );
      expect(
        nativeLauncher,
        matches(
          RegExp(r'automaticRecovery\s*&&\s*!await recoveryPreflight\.allows'),
        ),
      );
      expect(
        nativeLauncher,
        matches(
          RegExp(r'TorrentPlaybackService\.resolveRecoverySource\(\s*torrent,'),
        ),
      );
      expect(
        nativeLauncher,
        contains(
          ': await resolveSourceToPlaylist(torrent, canContinue: active)',
        ),
      );
      final automaticProbe = _between(
        recoveryResolution,
        'static Future<List<PlaylistEntry>?> resolveRecoverySource(',
        '\n}',
      );
      expect(
        automaticProbe,
        matches(
          RegExp(r'SourceProbing\.probeCandidates\(\s*provider,\s*\[source\]'),
        ),
      );
      expect(
        automaticProbe,
        contains('tryNextOnFailure: false, maxAttempts: 1'),
      );
    },
  );

  test('saved direct recovery snapshots its effective acquisition provider', () {
    final launch = _between(
      playerLaunch,
      'static Future<void> launch(',
      'static SourcePlaylistResolve resolverFor(',
    );
    expect(launch, contains('final resolverProvider ='));
    expect(
      launch,
      contains('await SourceProviderConfig.defaultConfiguredProvider('),
    );
    expect(launch, contains('resolverFor(resolverProvider, committer)'));
    expect(launch, contains('startupResolverProvider: resolverProvider'));
    expect(
      launch,
      matches(
        RegExp(
          r'recoveryProvider\s*\?\?\s*await SourceProviderConfig\.defaultConfiguredProvider\(\s*canContinue:',
        ),
      ),
    );
    expect(
      launch,
      matches(
        RegExp(
          r'_lazySourceCommitter\(\s*meta,\s*'
          r'preferredProvider:\s*resolverProvider,\s*'
          r'sourceBindings:\s*sourceBindings,\s*\)',
        ),
      ),
    );
    expect(
      nativeStartupGate,
      contains('startupResolverProvider.equals("pikpak", ignoreCase = true)'),
    );
    expect(
      nativeStartupGate,
      contains('startupPikPakTorrentAcquisitionAttempted = true'),
    );
  });

  test(
    'native recovery reports candidate production before merging duplicates',
    () {
      expect(
        nativeLauncher,
        contains("'recoveryCandidateCount': automatic.length"),
      );
      expect(nativeSourceFetch, contains('map["recoveryCandidateCount"]'));
      expect(nativeStartupGate, contains('startupRecoveryIsConsumed('));
    },
  );

  test('saved direct fetch and resolution honor the preferred provider', () {
    final direct = _between(
      boundPlaybackCode,
      '// Addon-direct pins store provenance',
      '// Cheap skip: a bound DEBRID source',
    );
    expect(direct, contains('recoveryProvider: preferredProvider'));
    expect(
      direct,
      matches(
        RegExp(
          r'SourceSeriesFetcher\.seriesFetcherFor\(\s*meta:\s*meta,\s*provider:\s*preferredProvider,?\s*\)',
        ),
      ),
    );
    expect(
      direct,
      matches(
        RegExp(
          r'SourceMovieFetcher\.movieFetcherFor\(\s*meta:\s*meta,\s*provider:\s*preferredProvider,?\s*\)',
        ),
      ),
    );
  });

  test('failure removals and commits share the session persistence queue', () {
    final failure = _between(
      playerBridge,
      "case 'startupSourceFailed':",
      "case 'requestMoreTorrentSources':",
    );
    expect(failure, contains('failureSession.enqueue('));
    expect(failure, isNot(contains('_startupFailureDrain.then')));
    expect(
      playerBridge,
      contains('persistenceSession.enqueue(() => committer(sourceIndex))'),
    );
  });

  test(
    'Flutter explicit source picks validate only the selected candidate',
    () {
      final selection = vpSourceDeclaration(
        '_VideoPlayerScreenState._handleSourceSelected',
      );
      final directSwitch = vpSourceDeclaration(
        '_VideoPlayerScreenState._switchToStremioSource',
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
    final resume = vpSourceDeclaration('_VideoPlayerScreenState._saveResume');
    // The gate moved into _resumeSaveBlocked when saves became serialized;
    // the contract follows the indirection: every save path consults the
    // blocker, and the blocker still enforces the validation gate.
    final resumeBlocked = vpSourceDeclaration(
      '_VideoPlayerScreenState._resumeSaveBlocked',
    );
    const method = '';
    expect(resume, contains('Future<void> saveResume('));
    const fields = '_host.';
    final locked = vpSourceDeclaration(
      '_VideoPlayerScreenState._saveResumeLocked',
    );

    expect(ended, contains('if (_validationGateActive) return;'));
    expect(resume, contains('${method}resumeSaveBlocked(debounced)'));
    expect(locked, contains('${method}resumeSaveBlocked(debounced)'));
    expect(resumeBlocked, contains('${fields}validationGateActive'));
    expect(
      resumeBlocked.indexOf('${fields}validationGateActive'),
      lessThan(resumeBlocked.indexOf('${fields}isReady')),
    );
    expect(
      vpSourceDeclaration(
        '_VideoPlayerScreenState._resumeTrackingAfterValidationGate',
      ),
      contains('void _resumeTrackingAfterValidationGate()'),
    );
  });

  test('Flutter failed playlist picks restore an outgoing direct stream', () {
    final playlistSwitch = vpSourceDeclaration(
      '_VideoPlayerScreenState._switchToSourcePlaylist',
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
        nativeSourceSwitcher,
        'fun onStremioSourceSelected(',
        'private fun resolveStremioSourceViaFlutter(',
      );
      final reject = _between(
        nativeStartupGate,
        'internal fun failManualSourceCandidate(',
        'internal fun armStartupCandidate(',
      );

      expect(reject, contains('manualSourceRestoreInProgress = true'));
      expect(
        reject,
        contains('host.playItem(host.currentIndex, suppressTrakt = true)'),
      );
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
      nativePlaybackStart,
      'private fun resolveAndPlay(',
      'private fun startPlayback(',
    );
    final progress = _between(
      nativeProgressReporter,
      'fun sendProgress(',
      'private fun sendIptvProgress(',
    );

    expect(resolver, contains('reason=stale_manual_token'));
    expect(resolver, contains('failManualSourceCandidate("initial-resolve")'));
    expect(progress, contains('manualSourceSwitchSnapshot != null'));
    expect(progress, contains('manualSourceRestoreInProgress'));
  });

  test('manual series packs must contain the selected episode', () {
    expect(
      nativeSourceApplier,
      contains(
        '(requireExactStartupEpisode || host.manualSourceSwitchSnapshot != null)',
      ),
    );
    final playlistSwitch = vpSourceDeclaration(
      '_VideoPlayerScreenState._switchToSourcePlaylist',
    );
    expect(playlistSwitch, contains('containsRequestedEpisode = false'));
    expect(playlistSwitch, contains('if (containsRequestedEpisode)'));
  });

  test(
    'Flutter startup failures unpin the failed source and still recover',
    () {
      final startup = vpSourceDeclaration(
        '_VideoPlayerScreenState._openInitialVodWithFailover',
      );
      final directBinding = _between(
        boundPlaybackCode,
        '// Addon-direct pins store provenance',
        '// Cheap skip: a bound DEBRID source',
      );

      expect(startup, isNot(contains('_reportRejectedStremioSource')));
      expect(
        vpSourceDeclaration('_VideoPlayerScreenState._reportStartupFailure'),
        contains("'startupSourcesExhausted': true"),
      );
      expect(
        boundPlaybackCode,
        isNot(contains('_rejectedDirectSourceHandler')),
      );
      expect(directBinding, contains('sourceBindings.removeInvalid('));
      expect(directBinding, contains('sourceBindings.removeCachedLink('));
      expect(directBinding, isNot(contains('[source, ...remainingSources]')));
      expect(
        directBinding,
        contains(
          'startupHasRemainingSavedSources: remainingSources.isNotEmpty',
        ),
      );
      expect(boundPlaybackCode, contains('remainingSources'));
      expect(bindingActions, contains('skipBoundSources: true'));
    },
  );

  test('every saved-source launch preserves remaining-pin recovery', () {
    final boundPlayback = _between(
      boundPlaybackCode,
      'static Future<bool> playViaBound(',
      '\n  }\n',
    );
    // Direct addons, media-server pins, local files, and debrid/native-cloud packs need the
    // flag, including when native startup has only one permitted attempt.
    final launches = boundPlayback
        .split('await SourcePlayerLaunch.launch(')
        .skip(1)
        .toList();
    expect(launches, hasLength(4));
    for (final launch in launches) {
      final arguments = launch.split('onStartupSourcesExhausted:').first;
      final cleanup = _between(
        launch,
        'onStartupSourcesExhausted:',
        'await SourceBindingActions.recoverAfterBoundStartupFailure(',
      );
      expect(cleanup, contains('await FailedSavedSource.cleanup('));
      expect(
        cleanup,
        isNot(contains('await SeriesSourceService.removeSourceEntry')),
      );
      expect(
        arguments,
        contains(
          'startupHasRemainingSavedSources: remainingSources.isNotEmpty',
        ),
      );
    }
  });

  test('bound startup recovery retains the preferred provider', () {
    final selection = _between(
      automaticSelection,
      'static Future<void> playFromSelection(',
      '\n  }\n',
    );
    final boundPlayback = _between(
      boundPlaybackCode,
      'static Future<bool> playViaBound(',
      '\n  }\n',
    );
    final recovery = _between(
      bindingActions,
      'static Future<void> recoverAfterBoundStartupFailure(',
      '/// Pin [torrent] as the playback source',
    );

    expect(
      RegExp(
        r'playViaBound\([\s\S]*?preferredProvider: preferredProvider',
      ).hasMatch(selection),
      isTrue,
    );
    expect(boundPlayback, contains('String? preferredProvider'));
    expect(
      RegExp(
        r'SourceBindingActions\.recoverAfterBoundStartupFailure\([\s\S]*?preferredProvider: preferredProvider',
      ).allMatches(boundPlayback),
      hasLength(4),
    );
    expect(recovery, contains('String? preferredProvider'));
    expect(recovery, contains('preferredProvider: preferredProvider'));
    expect(recovery, contains('skipBoundSources: true'));
  });

  test('Android TV reports exhaustion without deleting failed source pins', () {
    final startupFailure = _between(
      nativeStartupGate,
      'internal fun failStartupCandidate(',
      'internal fun failStartupResolution(',
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
    expect(playerBridge, contains('class StremioSourcePersistenceSession'));
    expect(playerBridge, contains('queued.timeout(waitTimeout'));
    expect(playerBridge, contains('_tail.timeout(waitTimeout)'));
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
      contains(
        'payloadCheck.optInt("sourcePersistenceSessionId", sourcePersistenceSessionId)',
      ),
    );
    expect(
      nativeStartupGate,
      contains(
        '"sourcePersistenceSessionId" to host.sourcePersistenceSessionId',
      ),
    );
    expect(playerBridge, contains('ignoring stale playback finish'));
  });

  test('delayed startup recovery waits for the exact player route', () {
    final failure = vpSourceDeclaration(
      '_VideoPlayerScreenState._reportStartupFailure',
    );
    expect(failure, contains('final playerRoute = ModalRoute.of(context)'));
    // Mount/retirement checking moved into the local current() guard; follow
    // that indirection while still requiring this exact captured route.
    expect(
      failure,
      matches(
        RegExp(
          r'bool current\(\)\s*=>\s*mounted\s*&&\s*!_screenDisposed\s*&&\s*'
          r'\(isCurrent\?\.call\(\)\s*\?\?\s*true\)\s*;',
        ),
      ),
    );
    expect(failure, contains('current() && playerRoute?.isActive == true'));
    expect(
      failure,
      contains(
        'if (!mounted || !current() || playerRoute?.isCurrent != true) return;',
      ),
    );
  });
}
