import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tracker launch argument compatibility', () {
    test('legacy suppression alias preserves its original behavior', () {
      const args = VideoPlayerLaunchArgs(
        videoUrl: 'video',
        title: 'Title',
        suppressTraktAutoSync: true,
      );
      expect(args.suppressTraktAutoSync, isTrue);
      expect(args.suppressTrackerAutoSync, isTrue);
    });

    test('copyWith preserves Trakt and Simkl while enabling MDBList', () {
      const original = VideoPlayerLaunchArgs(
        videoUrl: 'video',
        title: 'Title',
        traktScrobble: true,
        traktProgressPercent: 21,
        simklScrobble: true,
        simklProgressPercent: 34,
        suppressTraktAutoSync: true,
      );
      final copy = original.copyWith(
        mdblistScrobble: true,
        mdblistProgressPercent: 55,
      );
      expect(copy.traktScrobble, isTrue);
      expect(copy.traktProgressPercent, 21);
      expect(copy.simklScrobble, isTrue);
      expect(copy.simklProgressPercent, 34);
      expect(copy.mdblistScrobble, isTrue);
      expect(copy.mdblistProgressPercent, 55);
      expect(copy.suppressTraktAutoSync, isTrue);

      final downgraded = copy.copyWith(mdblistScrobble: false);
      expect(downgraded.mdblistScrobble, isFalse);
      expect(downgraded.traktScrobble, isTrue);
      expect(downgraded.simklScrobble, isTrue);
    });

    test('MDBList tracking requires both sync and authentication', () {
      bool enabled({
        bool requested = true,
        bool autoEligible = false,
        bool featureEnabled = true,
        bool identityAvailable = true,
        bool syncEnabled = true,
        bool authenticated = true,
      }) => VideoPlayerLauncher.shouldEnableMdblistTracking(
        requested: requested,
        autoEligible: autoEligible,
        featureEnabled: featureEnabled,
        identityAvailable: identityAvailable,
        syncEnabled: syncEnabled,
        authenticated: authenticated,
      );

      expect(enabled(), isTrue);
      expect(enabled(syncEnabled: false), isFalse);
      expect(enabled(authenticated: false), isFalse);
      expect(enabled(featureEnabled: false), isFalse);
      expect(enabled(identityAvailable: false), isFalse);
      expect(enabled(requested: false, autoEligible: true), isTrue);
      expect(enabled(requested: false, autoEligible: false), isFalse);
    });
  });

  group('external playback URL selection', () {
    VideoPlayerLaunchArgs args({String? audioUrl, String? fallbackUrl}) {
      return VideoPlayerLaunchArgs(
        videoUrl: 'https://example.com/video-only.mp4',
        audioUrl: audioUrl,
        fallbackUrl: fallbackUrl,
        title: 'Video',
      );
    }

    test('uses muxed fallback when the primary stream has separate audio', () {
      final launchArgs = args(
        audioUrl: 'https://example.com/audio.m4a',
        fallbackUrl: 'https://example.com/muxed.mp4',
      );

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(launchArgs),
        'https://example.com/muxed.mp4',
      );
    });

    test('keeps primary URL for an already-muxed stream', () {
      final launchArgs = args(fallbackUrl: 'https://example.com/fallback.mp4');

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(launchArgs),
        'https://example.com/video-only.mp4',
      );
    });

    test('keeps primary URL when no muxed fallback is available', () {
      final launchArgs = args(audioUrl: 'https://example.com/audio.m4a');

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(launchArgs),
        'https://example.com/video-only.mp4',
      );
    });

    test('ignores empty audio and fallback URLs', () {
      final launchArgs = args(audioUrl: '', fallbackUrl: '');

      expect(
        VideoPlayerLauncher.externalPlaybackUrlFor(launchArgs),
        'https://example.com/video-only.mp4',
      );
    });
  });
}
