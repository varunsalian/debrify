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

    test('native tracking retains preferences and existing CW ownership', () {
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.trakt, TrackingSource.mdblist},
        progressSource: WatchProgressSource.smart,
        homeTickSources: {TrackingSource.trakt},
      );
      for (final id in ['tmdb:237243', 'simkl:2274121', 'tmdb:movie:237243']) {
        final native = policy.forContent(id);
        final flags = VideoPlayerLauncher.normalizeScrobbleFlags(
          VideoPlayerLaunchArgs(
            videoUrl: 'https://example.test/video',
            title: 'Big Brother',
            contentImdbId: id,
            traktScrobble: true,
            mdblistScrobble: true,
          ),
          native,
        );
        expect(flags.traktScrobble, isTrue);
        expect(flags.mdblistScrobble, isTrue);
        expect(native.progressFrom(TrackingSource.trakt), isTrue);
        expect(native.progressFrom(TrackingSource.mdblist), isTrue);
        expect(
          native.usesLocalCompletionTracking(
            traktScrobble: true,
            simklScrobble: false,
            mdblistScrobble: true,
          ),
          isTrue,
        );
        expect(
          native.usesLocalCompletionTracking(
            traktScrobble: true,
            simklScrobble: true,
            mdblistScrobble: true,
          ),
          isFalse,
        );
      }
      expect(
        policy
            .forContent('tt1234567')
            .usesLocalCompletionTracking(
              traktScrobble: true,
              simklScrobble: false,
              mdblistScrobble: true,
            ),
        isFalse,
      );
      final custom = policy.forContent('medialibrary:123');
      expect(custom.scrobbles(TrackingSource.trakt), isFalse);
      expect(custom.scrobbles(TrackingSource.mdblist), isFalse);
      expect(custom.progressFrom(TrackingSource.trakt), isFalse);
    });

    test(
      'native dedicated tracker modes retain local resume without disabling writes',
      () {
        for (final mode in [
          WatchProgressSource.trakt,
          WatchProgressSource.mdblist,
        ]) {
          final policy = TrackingSourcePolicy(
            scrobbleTargets: {TrackingSource.trakt, TrackingSource.mdblist},
            progressSource: mode,
            homeTickSources: {TrackingSource.trakt, TrackingSource.mdblist},
          );
          for (final id in [
            'tmdb:237243',
            'simkl:2274121',
            'tmdb:movie:237243',
          ]) {
            final native = policy.forContent(id);
            expect(native.progressFrom(TrackingSource.local), isTrue);
            expect(native.guideProgressFrom(TrackingSource.local, 42), 42);
            expect(native.scrobbles(TrackingSource.trakt), isTrue);
            expect(native.scrobbles(TrackingSource.mdblist), isTrue);
          }
          expect(policy.forContent('tt1234567').progressSource, mode);
          expect(
            policy.forContent('tt1234567').progressFrom(TrackingSource.local),
            isFalse,
          );
        }
      },
    );

    test('guide mask drops everything foreign — ticks included', () {
      // 2026-08-27 decision: episode-list ticks follow the Progress source
      // exactly like partial bars (supersedes ticks-always-merged).
      const policy = TrackingSourcePolicy(
        scrobbleTargets: {TrackingSource.local},
        progressSource: WatchProgressSource.trakt,
        homeTickSources: {TrackingSource.local},
      );

      expect(policy.guideProgressFrom(TrackingSource.simkl, 42), isNull);
      expect(policy.guideProgressFrom(TrackingSource.simkl, 100), isNull);
      expect(policy.guideProgressFrom(TrackingSource.trakt, 42), 42);
      expect(policy.guideProgressFrom(TrackingSource.trakt, 100), 100);
    });
  });
}
