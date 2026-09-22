import 'package:debrify/services/local_playback_resume_resolver.dart';
import 'package:debrify/services/storage_service.dart';
import 'package:debrify/services/tracking_source_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'server episode progress never merges same-title catalog or other servers',
    () async {
      for (final entry in {
        'tt123': 10000,
        'medialibrary:one:show': 20000,
        'medialibrary:two:show': 30000,
      }.entries) {
        await StorageService.saveSeriesPlaybackState(
          seriesTitle: 'Show',
          season: 1,
          episode: 1,
          positionMs: entry.value,
          durationMs: 100000,
          imdbId: entry.key,
        );
      }
      for (final entry in {
        'tt123': 10000,
        'medialibrary:one:show': 20000,
        'medialibrary:two:show': 30000,
      }.entries) {
        final state = await LocalPlaybackResumeResolver.episode(
          seriesTitle: 'Show',
          season: 1,
          episode: 1,
          imdbId: entry.key,
          policy: PlaybackResumePolicy.catalogCanonical,
        );
        expect(state?['positionMs'], entry.value);
      }
      expect(
        await LocalPlaybackResumeResolver.episode(
          seriesTitle: 'Show',
          season: 1,
          episode: 1,
          imdbId: 'medialibrary:three:show',
          policy: PlaybackResumePolicy.catalogCanonical,
        ),
        isNull,
      );
      await StorageService.markEpisodeAsFinished(
        seriesTitle: 'Show',
        season: 1,
        episode: 1,
        imdbId: 'tt123',
      );
      expect(
        await StorageService.getMergedFinishedEpisodes(
          seriesTitle: 'Show',
          imdbId: 'medialibrary:one:show',
        ),
        isEmpty,
      );
    },
  );
  test(
    'same-title recordings retain independent bookmarks and leave catalog history alone',
    () async {
      for (final id in [
        'tt123',
        'medialibrary:one:recording',
        'medialibrary:two:recording',
      ]) {
        await StorageService.saveVideoPlaybackState(
          videoTitle: 'Recording',
          videoUrl: 'https://server/video',
          positionMs: id == 'tt123'
              ? 10000
              : id.contains(':one:')
              ? 20000
              : 30000,
          durationMs: 100000,
          imdbId: id,
        );
      }
      for (final entry in {
        'tt123': 10000,
        'medialibrary:one:recording': 20000,
        'medialibrary:two:recording': 30000,
      }.entries) {
        final state = await LocalPlaybackResumeResolver.movie(
          resumeId: 'Recording',
          imdbId: entry.key,
          policy: PlaybackResumePolicy.catalogCanonical,
        );
        expect(state?['positionMs'], entry.value);
      }
      expect(
        await LocalPlaybackResumeResolver.movie(
          resumeId: 'Recording',
          imdbId: 'medialibrary:three:recording',
          policy: PlaybackResumePolicy.catalogCanonical,
        ),
        isNull,
      );
      await StorageService.saveContinueWatchingItem(
        imdbId: 'medialibrary:one:recording',
        title: 'Recording',
        contentType: 'movie',
      );
      expect(await StorageService.getContinueWatchingItems(), isEmpty);
      await StorageService.saveContinueWatchingItem(
        imdbId: 'tt123',
        title: 'Movie',
        contentType: 'movie',
      );
      expect(
        (await StorageService.getContinueWatchingItems()).single['imdbId'],
        'tt123',
      );
    },
  );
  test(
    'server identities use local progress regardless of catalog tracker preference',
    () {
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.trakt},
        progressSource: WatchProgressSource.trakt,
        homeTickSources: {TrackingSource.trakt},
      );
      final server = policy.forContent('medialibrary:server:item');
      expect(server.progressFrom(TrackingSource.local), true);
      expect(server.scrobbles(TrackingSource.trakt), false);
      expect(policy.forContent('tt123'), same(policy));
    },
  );
  test('both servers are accepted as saved Discover defaults', () async {
    for (final value in ['jellyfin', 'emby']) {
      await StorageService.setDiscoverLastSource(value);
      expect(await StorageService.getDiscoverLastSource(), value);
    }
  });
}
