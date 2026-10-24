import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player/widgets/iptv_zap_banner.dart';
import 'package:debrify/screens/video_player/widgets/tv_controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/engine_driver.dart';
import 'support/lease_steps.dart';

const _failure = 'synthetic MediaCodec video output failure';

Future<void> _mode(EngineDriver d, AndroidVideoRendererMode mode) => d.f
    .finish<void>(d.t, PlayerSettingsStorage.setAndroidVideoRendererMode(mode));

(String?, String?) _output(EngineDriver d, [int index = 0]) {
  final c = d.f.controllers[index].configuration;
  return (c.vo, c.hwdec);
}

/// The touch controls' visibility fade (0 hidden, 1 shown).
double _controlsOpacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byType(Controls),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

void main() {
  tearDown(() {
    VpS2Hooks.install(null);
    PlatformUtil.debugSetAndroidTvCached(false);
  });

  for (final mode in AndroidVideoRendererMode.values) {
    testWidgets(
      'P20 on Android the stored ${mode.storageKey} renderer reaches the controller vo and hwdec',
      (t) async {
        final d = EngineDriver(t);
        await d.initialize();
        VpS2Hooks.install(VpS2Hooks(android: () => true));
        try {
          await _mode(d, mode);
          await d.mount();
          expect(_output(d), (mode.videoOutput, mode.hardwareDecoder));
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P20 off Android the stored renderer is never read and the controller keeps the automatic output',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => false));
      try {
        await _mode(d, AndroidVideoRendererMode.directSurface);
        await d.mount();
        expect(_output(d), (null, null));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P20 on Android TV the phone renderer preference is never read', (
    t,
  ) async {
    final d = EngineDriver(t);
    await d.initialize();
    VpS2Hooks.install(VpS2Hooks(android: () => true));
    try {
      await _mode(d, AndroidVideoRendererMode.directSurface);
      PlatformUtil.debugSetAndroidTvCached(true);
      await d.mount();
      expect(_output(d), (null, null));
    } finally {
      await d.close();
    }
  });

  for (final force in [true, false]) {
    testWidgets(
      'P20 tvOS software decode=$force ${force ? 'outranks the renderer with hwdec=no' : 'keeps the renderer decoder'}',
      (t) async {
        final d = EngineDriver(t, tvos: true);
        await d.initialize();
        try {
          await d.f.finish<void>(
            t,
            PlayerSettingsStorage.setTvosForceSoftwareDecode(force),
          );
          await d.mount();
          expect(_output(d), (null, force ? 'no' : null));
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P20 the player is not presented until its ready callback arrives',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await pumpScreen(d);
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'open'));
        await d.f.advance(t, const Duration(seconds: 2));
        expect(find.byType(mkv.Video), findsNothing);
        expect(find.byType(Controls), findsNothing);
        d.player.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(find.byType(mkv.Video), findsOneWidget);
        expect(find.byType(Controls), findsOneWidget);
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a renderer rebuild hides the player until the new instance is ready and ignores a stale ready',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      try {
        await _mode(d, AndroidVideoRendererMode.directSurface);
        await pumpScreen(d);
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        await d.f.until(t, () => d.player.calls.any((c) => c.$1 == 'open'));
        final old = d.player;
        old.emit('error', _failure);
        await d.f.until(t, () => d.f.players.length == 2);
        final rebuilt = d.player;
        expect(_output(d, 1), (null, null));
        // The superseded instance becomes ready late: ignored.
        old.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(find.byType(mkv.Video), findsNothing);
        expect(find.byType(Controls), findsNothing);
        rebuilt.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(find.byType(mkv.Video), findsOneWidget);
        expect(find.byType(Controls), findsOneWidget);
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a live IPTV launch hides the controls and raises the zap banner once, not again on a renderer rebuild',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => true));
      final channel = IptvChannel(
        name: 'P20 instance live',
        url: 'https://instance.test/live.ts',
        contentType: 'live',
        group: 'News',
      );
      int raises() =>
          d.timers.where((v) => v.stack.contains('raiseIptvZapBanner')).length;
      try {
        await _mode(d, AndroidVideoRendererMode.directSurface);
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: channel.url,
            title: channel.name,
            iptvChannels: [channel],
            iptvStartIndex: 0,
          ),
        );
        expect(raises(), 1);
        expect(find.byType(IptvZapBanner), findsWidgets);
        expect(_controlsOpacity(t), 0);
        d.player.emit('error', _failure);
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(raises(), 1);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 on TV the ready edge moves focus to play/pause after the frame',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      PlatformUtil.debugSetAndroidTvCached(true);
      try {
        await d.mount();
        final node = t
            .widget<TvControls>(find.byType(TvControls))
            .playPauseFocusNode;
        expect(FocusManager.instance.primaryFocus, node);
      } finally {
        await d.close();
      }
    },
  );
}
