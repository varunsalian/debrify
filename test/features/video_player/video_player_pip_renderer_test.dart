import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/pip_service.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_player.dart';
import 'support/pip_lifecycle_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'video_player_pip_lifecycle_test.dart' show background, foreground;

class RendererFixture {
  RendererFixture(this.t, {this.audio = false, this.ios = false}) {
    var created = 0;
    f = VideoPlayerEnvironment(
      native: true,
      configurePlayer: (p) {
        if (++created == 2 && audio) {
          final native = p.platform! as FakeNativePlayer;
          bool held(String name, Object? value) =>
              name == 'setProperty' &&
              (value as (String, String)).$1 == 'alang';
          native.heldOperation = held;
          native.beforeOperation = (name, value) =>
              held(name, value) ? gate.future : null;
        }
      },
    );
    d = PipLifecycleDriver(t, f, ios: ios);
  }
  final WidgetTester t;
  final bool audio;
  final bool ios;
  final gate = Completer<void>();
  late final VideoPlayerEnvironment f;
  late final PipLifecycleDriver d;
  late FakePlayer old;

  Future<void> mount({bool live = false}) async {
    await d.initialize();
    VpS2Hooks.install(VpS2Hooks(ios: () => ios, android: () => true));
    await f.finish<void>(
      t,
      PlayerSettingsStorage.setAndroidVideoRendererMode(
        AndroidVideoRendererMode.directSurface,
      ),
    );
    if (audio) {
      await f.finish<void>(
        t,
        SubtitleSettingsStorage.setDefaultAudioLanguage('eng'),
      );
    }
    final channel = IptvChannel(
      name: 'Renderer live',
      url: 'https://renderer.test/live/1.ts',
      contentType: 'live',
    );
    await d.mount(
      live
          ? VideoPlayerScreen(
              videoUrl: channel.url,
              title: channel.name,
              iptvChannels: [channel],
            )
          : pipScreen,
    );
    old = f.player;
  }

  Future<void> fallback() async {
    if (!audio) old.delays['dispose'] = gate;
    // Keep the carried target out of unrelated resume verification.
    old.state = old.state.copyWith(position: Duration.zero);
    old.emit('position', Duration.zero);
    await f.advance(t);
    old.emit('error', 'synthetic MediaCodec video output failure');
    if (audio) {
      await f.until(t, () => f.players.length == 2);
      f.player.deliverReady();
      await f.until(
        t,
        () => (f.player.platform! as FakeNativePlayer).calls.any(
          (c) =>
              c.$1 == 'setProperty' && (c.$2 as (String, String)).$1 == 'alang',
        ),
      );
    } else {
      await f.until(t, () => d.operations('dispose', old).isNotEmpty);
      expect(f.players, hasLength(1));
    }
    expect(gate.isCompleted, isFalse);
    expect(PipService.isOwner(d.stateOwner!), isTrue);
  }

  Future<void> release() async {
    gate.complete();
    await f.until(t, () => f.players.length == 2);
    if (!f.player.readyDelivered) f.player.deliverReady();
    await f.until(t, () => d.operations('rate', f.player).isNotEmpty);
    await d.settle();
    expect(old.disposed.isCompleted, isTrue);
    expect(f.player.handleValue, isNot(old.handleValue));
  }

  Future<void> close() async {
    if (!gate.isCompleted) gate.complete();
    await d.close();
  }
}

void main() {
  testWidgets(
    'PiP renderer gap suppresses a captured entry while old disposal is held',
    (t) async {
      final h = RendererFixture(t, ios: true);
      try {
        await h.mount();
        final dynamic callback = playerControls(t).onPip;
        expect(callback, isNotNull);
        await h.fallback();
        final pushes = h.d.named('updatePlaybackState').length;
        final native = h.old.platform! as FakeNativePlayer;
        List<(String, Object?)> subtitleWrites() => native.calls
            .where(
              (c) =>
                  c.$1 == 'setProperty' &&
                  (c.$2 as (String, String)).$1 == 'sub-visibility',
            )
            .toList();
        final writes = subtitleWrites().length;
        final pending = h.d.observe<dynamic>(() => callback());
        await h.f.finish<dynamic>(t, pending as Future<dynamic>);
        await h.d.settle();
        expect(h.d.named('enterPip'), isEmpty);
        expect(h.d.named('updatePlaybackState'), hasLength(pushes));
        expect(subtitleWrites(), hasLength(writes));
        expect(h.gate.isCompleted, isFalse);
        await h.release();
        expect(h.d.errors, isEmpty);
      } finally {
        await h.close();
      }
    },
  );

  testWidgets(
    'PiP renderer background before replacement latches a paused open and first live resume keeps the buffer',
    (t) async {
      final h = RendererFixture(t);
      try {
        await h.mount(live: true);
        await h.fallback();
        final pauses = h.d.operations('pause', h.old).length;
        await background(h.d);
        // The renderer gap has removed Video; State has no live player to pause.
        expect(h.d.operations('pause', h.old), hasLength(pauses));
        await h.release();
        expect(h.d.operations('open').single.$2, isA<(Object, bool)>());
        expect(
          (h.d.operations('open').single.$2 as (Object, bool)).$2,
          isFalse,
        );
        expect(h.f.player.state.playing, isFalse);
        await foreground(h.d);
        await h.d.settle();
        expect(h.d.operations('open'), hasLength(1));
        expect(h.d.operations('play'), hasLength(1));
        expect(h.f.player.state.playing, isTrue);
        expect(h.d.errors, isEmpty);
      } finally {
        await h.close();
      }
    },
  );

  testWidgets(
    'PiP renderer audio preparation pauses the created player but foreground does not play before setup completes',
    (t) async {
      final h = RendererFixture(t, audio: true);
      try {
        await h.mount();
        await h.fallback();
        expect(h.d.operations('open'), isEmpty);
        await background(h.d);
        expect(h.d.operations('pause'), hasLength(1));
        await foreground(h.d);
        expect(h.d.operations('play'), isEmpty);
        expect(h.gate.isCompleted, isFalse);
        await h.release();
        expect((h.d.operations('open').single.$2 as (Object, bool)).$2, isTrue);
        expect(h.f.player.state.playing, isTrue);
        expect(h.d.errors, isEmpty);
      } finally {
        await h.close();
      }
    },
  );

  testWidgets(
    'PiP renderer background cannot reuse a consumed long-absence timestamp',
    (t) async {
      final h = RendererFixture(t);
      try {
        await h.mount(live: true);
        await background(h.d);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 31)),
        );
        await foreground(h.d);
        await h.d.settle();
        expect(h.d.operations('open', h.old), hasLength(2));
        expect(h.d.operations('play', h.old), isEmpty);
        await h.fallback();
        await background(h.d);
        await h.release();
        expect(h.f.player.state.playing, isFalse);
        await foreground(h.d);
        await h.d.settle();
        expect(h.d.operations('open'), hasLength(1));
        expect(h.d.operations('play'), hasLength(1));
        expect(h.f.player.state.playing, isTrue);
        expect(h.d.errors, isEmpty);
      } finally {
        await h.close();
      }
    },
  );
}
