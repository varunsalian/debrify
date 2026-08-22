import 'package:debrify/services/youtube_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YoutubeResolvedStreams.muxedPlaybackFallback', () {
    test('returns a download URL known to contain audio', () {
      const streams = YoutubeResolvedStreams(
        playUrl: 'https://example.com/video-only.mp4',
        audioUrl: 'https://example.com/audio.m4a',
        downloadUrl: 'https://example.com/muxed.mp4',
        downloadHasAudio: true,
      );

      expect(streams.muxedPlaybackFallback, 'https://example.com/muxed.mp4');
    });

    test('rejects a video-only download URL as a playback fallback', () {
      const streams = YoutubeResolvedStreams(
        playUrl: 'https://example.com/video-only.mp4',
        audioUrl: 'https://example.com/audio.m4a',
        downloadUrl: 'https://example.com/video-only.mp4',
        downloadHasAudio: false,
      );

      expect(streams.muxedPlaybackFallback, isNull);
    });
  });
}
