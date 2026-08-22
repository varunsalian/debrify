import 'package:debrify/services/video_player_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
