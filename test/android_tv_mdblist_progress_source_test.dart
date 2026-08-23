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
  final source = File(
    'lib/services/video_player_launcher.dart',
  ).readAsStringSync();

  test('Android TV source switch carries MDBList episode resume progress', () {
    final resolver = _between(
      source,
      'sourcePlaylistResolverForTv = (int sourceIndex) async {',
      '// "Load more sources" for the series source tabs',
    );

    expect(resolver, contains('getEpisodeMdblistProgress'));
    expect(resolver, contains('sourceMdblistProgress[episodeKey]'));
    expect(resolver, contains('getMergedFinishedEpisodes'));
    expect(resolver, contains('resolveEpisodeLocalWatchState'));
    expect(resolver, contains("'watched': resolvedLocal.watched"));
    expect(resolver, contains('effectiveContentImdbId()'));
  });

  test(
    'Android TV fetched singleton carries MDBList episode resume progress',
    () {
      final fetcher = _between(
        source,
        'episodeFetchProviderForTv = (int season, int episode) async {',
        'Future<Map<String, dynamic>?> tryRange(',
      );

      expect(fetcher, contains('getEpisodeMdblistProgress'));
      expect(fetcher, contains('trackerMaps[2][episodeKey]'));
      expect(fetcher, contains('getMergedFinishedEpisodes'));
      expect(fetcher, contains("row['watched']"));
      expect(fetcher, contains('effectiveContentImdbId()'));
    },
  );

  test(
    'Android TV full guide serializes merged tracker and local progress',
    () {
      final guideBuilder = _between(
        source,
        'Future<\n          ({',
        'Future<bool> pushUpdates',
      );

      expect(guideBuilder, contains('getMergedEpisodeProgress'));
      expect(guideBuilder, contains('getMergedFinishedEpisodes'));
      expect(guideBuilder, contains('getEpisodeTraktProgress'));
      expect(guideBuilder, contains('getEpisodeSimklProgress'));
      expect(guideBuilder, contains('getEpisodeMdblistProgress'));
      expect(
        guideBuilder,
        contains("'resumePositionMs': localState.positionMs"),
      );
      expect(guideBuilder, contains("'durationMs': durationMs"));
      expect(guideBuilder, contains("'watched': localState.watched"));
      expect(
        guideBuilder,
        contains('for (var i = 0; i < payload.items.length'),
      );
      expect(guideBuilder, contains("'season': item.season"));
    },
  );

  test(
    'MDBList launch seed is lightweight and full history follows cached push',
    () {
      final seed = _between(
        source,
        'static Future<void> _seedMdblistEpisodeProgress(String imdbId)',
        '/// [onPlayerHandoff]',
      );

      expect(seed, contains('seedMdblistPlayback(imdbId)'));
      expect(seed, isNot(contains('refreshMdblistHistory')));

      final cachedPush = source.indexOf("pushUpdates(phase: 'cached')");
      final historyRefresh = source.indexOf(
        'EpisodeTrackerSnapshotService.refreshMdblistHistory',
        cachedPush,
      );
      expect(cachedPush, isNonNegative);
      expect(historyRefresh, greaterThan(cachedPush));

      final launchSeeds = _between(
        source,
        '// Real packs retain the existing Trakt/Simkl launch-time snapshots',
        "AnalyticsService.trackInBackground('playback_started'",
      );
      expect(launchSeeds, contains('unawaited(_seedMdblistEpisodeProgress'));
      expect(launchSeeds, isNot(contains('await _seedMdblistEpisodeProgress')));
    },
  );

  test('Flutter player guide allows MDBList-only episode resume', () {
    final playlistSheet = File(
      'lib/screens/video_player/widgets/playlist_sheet.dart',
    ).readAsStringSync();

    expect(playlistSheet, contains('getEpisodeMdblistProgress'));
    expect(playlistSheet, contains('getMergedEpisodeProgress'));
    expect(playlistSheet, contains('hasLocalResume || hasTrackerResume'));
  });

  test('legacy Trakt history is never written into local completion again', () {
    final refresh = _between(
      source,
      'static Future<void> _refreshTraktEpisodeProgress(String imdbId)',
      'static Future<void> _seedSimklEpisodeProgress',
    );

    expect(refresh, contains('refreshTrakt(imdbId)'));
    expect(refresh, isNot(contains('markEpisodeAsFinished')));
    expect(refresh, isNot(contains('saveVideoPlaybackState')));
    expect(source, contains('resolveEpisodeLocalWatchState'));
  });

  test('Flutter player retains and consumes a TVMaze-discovered identity', () {
    final player = File(
      'lib/screens/video_player_screen.dart',
    ).readAsStringSync();
    final sourceSwitch = _between(
      player,
      'Future<void> _switchToSourcePlaylist(',
      '// Resume the SAME episode from the new source',
    );
    final resumeGetters = _between(
      player,
      'void _bindEpisodeTrackerProgressIdentity',
      '/// Load an external audio track',
    );

    expect(sourceSwitch, contains('final carriedImdbId'));
    expect(sourceSwitch, contains('rebuilt.imdbId ??= carriedImdbId'));
    expect(resumeGetters, contains('final imdbId = _currentSeriesImdbId'));
    expect(player, contains('metadataReady: _episodeMetadataReady'));

    final resume = _between(
      player,
      'Future<void> _maybeRestoreResume(',
      '/// Get enhanced playback state for current content',
    );
    expect(resume, contains('hasActiveTraktEpisodeRewatch'));
    expect(resume, contains('localMs = 0'));
  });

  test('native TVMaze placeholders render the serialized watch state', () {
    final native = File(
      'android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt',
    ).readAsStringSync();
    final placeholder = _between(
      native,
      'val synthetic = PlaybackItem(',
      '(holder as EpisodeViewHolder).bindMissing(synthetic)',
    );

    expect(placeholder, contains('resumePositionMs = g.resumePositionMs'));
    expect(placeholder, contains('durationMs = g.durationMs'));
    expect(
      placeholder,
      contains('traktProgressPercent = g.trackerProgressPercent'),
    );
    expect(placeholder, contains('watched = g.watched'));
  });

  test('native actual rows adopt refreshed guide watch state', () {
    final native = File(
      'android/app/src/main/kotlin/com/debrify/app/tv/AndroidTvTorrentPlayerActivity.kt',
    ).readAsStringSync();
    final handler = _between(
      native,
      '// Handle episode metadata updates',
      'private fun requestMetadataFromFlutter()',
    );

    expect(handler, contains('hasWatchedUpdate'));
    expect(handler, contains('model.items.indexOfFirst'));
    expect(handler, contains('it.season == updateSeason'));
    expect(handler, contains('mergeLateMetadataResumePosition'));
    expect(handler, contains('mergeLateMetadataDuration'));
    expect(handler, contains('traktProgressPercent = newTrackerProgress'));
    expect(native, contains('if (watched) return 100'));
  });

  test('TVMaze-discovered IMDb id feeds later native resolver callbacks', () {
    expect(source, contains('String? effectiveContentImdbId()'));
    expect(source, contains('payload.imdbId = discoveredImdbId'));
    expect(source, contains('String? imdbId;'));
  });

  test('initial native playlist carries explicit local completion', () {
    final builder = _between(
      source,
      'class _AndroidTvPlaybackPayloadBuilder',
      '/// Fetch movie IMDB ID from Cinemeta',
    );

    expect(builder, contains('getMergedFinishedEpisodes'));
    expect(builder, contains('watched:'));
    expect(source, contains("'watched': watched"));
  });
}
