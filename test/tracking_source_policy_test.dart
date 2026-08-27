import 'package:flutter_test/flutter_test.dart';

import 'package:debrify/services/tracking_source_policy.dart';
import 'package:debrify/services/video_player_launcher.dart';

void main() {
  group('TrackingSourcePolicy', () {
    test('Smart admits every progress input', () {
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.local},
        progressSource: WatchProgressSource.smart,
        homeTickSources: {TrackingSource.local},
      );

      for (final source in TrackingSource.values) {
        expect(policy.progressFrom(source), isTrue);
      }
      expect(policy.forcesLocalCompletion, isFalse);
    });

    test('dedicated progress admits exactly one source', () {
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.local, TrackingSource.simkl},
        progressSource: WatchProgressSource.local,
        homeTickSources: {TrackingSource.local, TrackingSource.trakt},
      );

      expect(policy.progressFrom(TrackingSource.local), isTrue);
      expect(policy.progressFrom(TrackingSource.trakt), isFalse);
      expect(policy.progressFrom(TrackingSource.simkl), isFalse);
      expect(policy.progressFrom(TrackingSource.mdblist), isFalse);
      expect(policy.forcesLocalCompletion, isTrue);
      expect(policy.scrobbles(TrackingSource.local), isTrue);
      expect(policy.scrobbles(TrackingSource.simkl), isTrue);
      expect(policy.homeTicksFrom(TrackingSource.trakt), isTrue);
      expect(policy.homeTicksFrom(TrackingSource.simkl), isFalse);
    });

    test('launcher normalization masks pre-enabled tracker-row flags', () {
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.local, TrackingSource.simkl},
        progressSource: WatchProgressSource.smart,
        homeTickSources: {
          TrackingSource.local,
          TrackingSource.trakt,
          TrackingSource.simkl,
          TrackingSource.mdblist,
        },
      );
      const args = VideoPlayerLaunchArgs(
        videoUrl: 'https://example.test/video',
        title: 'Example',
        traktScrobble: true,
        simklScrobble: true,
        mdblistScrobble: true,
      );

      final normalized = VideoPlayerLauncher.normalizeScrobbleFlags(
        args,
        policy,
      );

      expect(normalized.traktScrobble, isFalse);
      expect(normalized.simklScrobble, isTrue);
      expect(normalized.mdblistScrobble, isFalse);
    });

    test('guide mask keeps foreign completion but drops foreign partials', () {
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.local},
        progressSource: WatchProgressSource.trakt,
        homeTickSources: {TrackingSource.local},
      );

      expect(policy.guideProgressFrom(TrackingSource.simkl, 42), isNull);
      expect(policy.guideProgressFrom(TrackingSource.simkl, 100), 100);
      expect(policy.guideProgressFrom(TrackingSource.trakt, 42), 42);
    });
  });
}
