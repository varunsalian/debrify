import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/iptv_channel_sheet.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/player_actions.dart';

const _failure = 'synthetic MediaCodec video output failure';

final _live = IptvChannel(
  name: 'P20 ready live',
  url: 'https://ready.test/live.ts',
  contentType: 'live',
  group: 'News',
);
final _liveScreen = VideoPlayerScreen(
  videoUrl: _live.url,
  title: _live.name,
  iptvChannels: [_live],
  iptvStartIndex: 0,
);

void main() {
  tearDown(() {
    VpS2Hooks.install(null);
    PlatformUtil.debugSetAndroidTvCached(false);
  });

  testWidgets(
    'P20 a renderer rebuild of a live launch does not raise the zap banner a second time',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      int raises() =>
          d.timers.where((v) => v.stack.contains('raiseIptvZapBanner')).length;
      try {
        await d.f.finish<void>(
          t,
          PlayerSettingsStorage.setAndroidVideoRendererMode(
            AndroidVideoRendererMode.directSurface,
          ),
        );
        await d.mount(screen: _liveScreen);
        expect(raises(), 1);
        d.observe(() => d.player.emit('error', _failure));
        await d.f.until(t, () => d.f.players.length == 2);
        // Delivered inside the observed zone, so a second raise is recorded.
        d.observe(d.player.deliverReady);
        await d.f.advance(t, const Duration(seconds: 2));
        expect(raises(), 1);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 the launch ready edge points the guide at the live channel group',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final channel = IptvChannel(
        name: 'P20 sports live',
        url: 'https://ready.test/sports.ts',
        contentType: 'live',
        group: 'Sports',
      );
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: channel.url,
            title: channel.name,
            iptvChannels: [channel],
            iptvStartIndex: 0,
            iptvSelectedCategory: 'News',
          ),
        );
        final open = playerControls(t).onShowIptvChannels;
        expect(open, isNotNull);
        open!();
        await d.f.advance(t, const Duration(milliseconds: 350));
        final sheet = t.widget<IptvChannelSheet>(find.byType(IptvChannelSheet));
        expect(sheet.selectedCategory, 'Sports');
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 the launch ready edge arms zap paging with one anchored browse request',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final requests = <Map<String, dynamic>>[];
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: _live.url,
            title: _live.name,
            iptvChannels: [_live],
            iptvStartIndex: 0,
            iptvSourceId: 'p20-ready-source',
            iptvBrowseProvider: (request) async {
              requests.add(Map<String, dynamic>.from(request));
              return null;
            },
          ),
        );
        await d.f.actions.settle(t);
        expect(requests.where((r) => r.containsKey('anchorUrl')), hasLength(1));
      } finally {
        await d.close();
      }
    },
  );
}
