import 'dart:async';

import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/lease_steps.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

const _a = PlaylistEntry(url: 'https://presentation.test/a.mp4', title: 'A');
const _b = PlaylistEntry(url: 'https://presentation.test/b.mp4', title: 'B');
const _playlist = VideoPlayerScreen(
  videoUrl: 'https://presentation.test/a.mp4',
  title: 'P20 presentation',
  disableAutoResume: true,
  startIndex: 0,
  playlist: [_a, _b],
);

void main() {
  testWidgets(
    'P20 an open while iOS PiP is still starting keeps native subtitles visible',
    (t) async {
      final seq = <String>[];
      final f = VideoPlayerEnvironment(
        native: true,
        configurePlayer: (p) {
          p.beforeOperation = (name, value) {
            if (name == 'open') seq.add('open');
          };
          (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
            if (name != 'setProperty') return;
            final (key, v) = value as (String, String);
            if (key == 'sub-visibility') seq.add(v);
          };
        },
      );
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      final entering = Completer<Object?>();
      try {
        await d.mount(_playlist);
        d.handler = (call) => call.method == 'enterPip'
            ? entering.future
            : call.method == 'isSupported';
        final dynamic enter = playerControls(t).onPip;
        expect(enter, isNotNull);
        d.observe<dynamic>(() => enter());
        await f.until(t, () => d.named('enterPip').isNotEmpty);
        seq.clear();
        f.player.emit('completed', true);
        await f.until(t, () => seq.contains('open'));
        expect(seq.take(seq.indexOf('open') + 1).toList(), ['yes', 'open']);
        entering.complete(false);
        await d.settle();
      } finally {
        if (!entering.isCompleted) entering.complete(false);
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a VOD IPTV launch keeps the controls and raises no zap banner at the ready edge',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      final vod = IptvChannel(
        name: 'P20 presentation VOD',
        url: 'https://presentation.test/vod.mp4',
        contentType: 'vod',
        group: 'Films',
      );
      int raises() =>
          d.timers.where((v) => v.stack.contains('raiseIptvZapBanner')).length;
      try {
        await d.mount(
          screen: VideoPlayerScreen(
            videoUrl: vod.url,
            title: vod.name,
            iptvChannels: [vod],
            iptvStartIndex: 0,
          ),
        );
        expect(raises(), 0);
        final fade = t.widget<AnimatedOpacity>(
          find
              .ancestor(
                of: find.byType(Controls),
                matching: find.byType(AnimatedOpacity),
              )
              .first,
        );
        expect(
          fade.opacity,
          1,
          reason: 'the ready edge leaves VOD controls up',
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 tvOS the first open waits for the player audio configuration',
    (t) async {
      final seq = <String>[];
      final audio = Completer<void>();
      var parked = false;
      bool isAo(String name, Object? value) =>
          name == 'setProperty' && (value as (String, String)).$1 == 'ao';
      final d = EngineDriver(
        t,
        tvos: true,
        configurePlayer: (p) {
          final native = p.platform! as FakeNativePlayer;
          p.beforeOperation = (name, value) {
            if (name == 'open') seq.add('open');
          };
          native.heldOperation = (name, value) =>
              isAo(name, value) && !audio.isCompleted;
          native.beforeOperation = (name, value) async {
            if (isAo(name, value)) {
              seq.add('ao');
              parked = true;
              await audio.future;
            }
          };
        },
      );
      await d.initialize();
      try {
        await pumpScreen(d, _playlist);
        await d.f.until(t, () => d.f.controllers.isNotEmpty);
        d.player.deliverReady();
        await d.f.until(t, () => parked);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(seq, ['ao'], reason: 'nothing opens before audio is set up');
        audio.complete();
        await d.f.until(t, () => seq.contains('open'));
        expect(seq, ['ao', 'open']);
        await d.f.advance(t, const Duration(seconds: 2));
        await d.f.until(
          t,
          () => d.periodic.contains(const Duration(seconds: 6)),
        );
      } finally {
        if (!audio.isCompleted) audio.complete();
        await d.close();
      }
    },
  );
}
