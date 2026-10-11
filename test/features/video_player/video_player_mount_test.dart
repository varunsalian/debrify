import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/video_player_environment.dart';

void main() {
  final channels = [
    IptvChannel(name: 'Original channel', url: 'https://player.test/live.m3u8'),
  ];
  final screens = <String, VideoPlayerScreen>{
    'direct URL': const VideoPlayerScreen(
      videoUrl: 'https://player.test/direct.mp4',
      title: 'Original direct',
    ),
    'playlist': const VideoPlayerScreen(
      videoUrl: 'https://player.test/list.mp4',
      title: 'Original playlist',
      playlist: [
        PlaylistEntry(
          url: 'https://player.test/list.mp4',
          title: 'Plain entry.mp4',
          httpHeaders: {'X-Original': 'playlist'},
        ),
      ],
    ),
    'IPTV channel list': VideoPlayerScreen(
      videoUrl: channels.first.url,
      title: 'Original IPTV',
      iptvChannels: channels,
      iptvStartIndex: 0,
    ),
    'Stremio TV channel': const VideoPlayerScreen(
      videoUrl: 'https://player.test/stremio.mp4',
      title: 'Original Stremio TV',
      stremioTvChannels: [
        {'id': 'slot-1', 'name': 'Original catalog', 'channelNumber': 7},
      ],
      stremioTvCurrentChannelId: 'slot-1',
    ),
  };
  for (final entry in screens.entries) {
    testWidgets('original S mounts ${entry.key} and drains disposal', (
      tester,
    ) async {
      final fixture = VideoPlayerEnvironment(native: true);
      await tester.runAsync(fixture.initialize);
      try {
        await fixture.mount(tester, entry.value);
        expect(fixture.creationOrder, [
          'media-kit-init',
          'player',
          'video-controller',
        ]);
        expect(fixture.player.configuration.logLevel, mk.MPVLogLevel.error);
        expect(fixture.player.configuration.ready, isNotNull);
        final video = fixture.controllers.single;
        expect(video.player, same(fixture.player));
        expect(video.configuration.vo, isNull);
        expect(video.configuration.hwdec, isNull);
        expect(video.configuration.scale, 1);
        expect(video.configuration.enableHardwareAcceleration, isTrue);
        expect(video.firstFrame.isCompleted, isTrue);
        final open =
            fixture.player.calls.singleWhere((call) => call.$1 == 'open').$2
                as (mk.Playable, bool);
        expect((open.$1 as mk.Media).uri, entry.value.videoUrl);
        expect(open.$2, isTrue);
        if (entry.key == 'playlist') {
          expect((open.$1 as mk.Media).httpHeaders, {'X-Original': 'playlist'});
        }
        expect(fixture.wake.writes.first, isTrue);
        expect(
          fixture.channels.map((entry) => entry.$2.method),
          contains('SystemChrome.setPreferredOrientations'),
        );
        await fixture.key(tester, LogicalKeyboardKey.space);
      } finally {
        await fixture.close(tester);
      }
      expect(fixture.wake.writes.last, isFalse);
      expect(fixture.player.calls.last.$1, 'dispose');
    });
  }
}
