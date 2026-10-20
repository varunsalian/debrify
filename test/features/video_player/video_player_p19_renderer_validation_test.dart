import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/lease_steps.dart' show elapsedUntil;

/// S2f world (resolution P2-3): Android renderer validation and the Android
/// override both on, so the explicit-renderer path runs on the host; the
/// diagnostics stay on the desktop `print` branch.
Future<EngineDriver> _mount(
  WidgetTester t, {
  required String output,
  AndroidVideoRendererMode mode = AndroidVideoRendererMode.directSurface,
  bool validation = true,
}) async {
  final d = EngineDriver(
    t,
    configurePlayer: (p) {
      (p.platform! as FakeNativePlayer).properties['current-vo'] = output;
    },
  );
  await d.initialize();
  VpS2Hooks.install(
    VpS2Hooks(
      android: () => true,
      androidRendererValidation: validation ? () => true : null,
    ),
  );
  await d.f.finish<void>(
    t,
    PlayerSettingsStorage.setAndroidVideoRendererMode(mode),
  );
  await d.mount();
  return d;
}

const _fallbackLine =
    'DEBRIFY_PLAYER_DECODER generation=1 phase=fallback '
    'status=renderer_startup_failed platform=android backend=libmpv '
    'requested_renderer=direct_surface fallback=automatic '
    'reason=requested_output_not_ready';

List<String> _fallbacks(EngineDriver d) =>
    d.decoderLines.where((l) => l.contains(' phase=fallback ')).toList();

FakeNativePlayer _native(FakePlayer p) => p.platform! as FakeNativePlayer;

void main() {
  tearDown(() => VpS2Hooks.install(null));

  testWidgets(
    'P19 the validation predicate installs both decoder observers; the Android override alone installs none',
    (t) async {
      for (final validation in [true, false]) {
        final d = await _mount(
          t,
          output: AndroidRendererStartupFallbackOutputs.surface,
          validation: validation,
        );
        try {
          expect(
            _native(d.player).observers.keys.toSet(),
            validation ? {'hwdec-current', 'current-vo'} : isEmpty,
          );
        } finally {
          await d.close();
          VpS2Hooks.install(null);
        }
      }
    },
  );

  testWidgets(
    'P19 an observer callback re-arms the decoder probe only for the live instance',
    (t) async {
      final d = await _mount(
        t,
        output: AndroidRendererStartupFallbackOutputs.surface,
      );
      try {
        int probes() => d.timers
            .where((x) => x.stack.contains('scheduleDecoderProbe'))
            .length;
        final before = probes();
        await d.observe(
          () => _native(d.player).observers['current-vo']!('mediacodec_embed'),
        );
        await d.observe(
          () => _native(d.player).observers['hwdec-current']!('mediacodec'),
        );
        expect(probes(), before + 2);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 two matching expected outputs validate the session, so a later renderer error keeps the renderer',
    (t) async {
      final d = await _mount(
        t,
        output: AndroidRendererStartupFallbackOutputs.surface,
      );
      try {
        await d.f.advance(t, const Duration(seconds: 4));
        expect(_fallbacks(d), isEmpty);
        d.player.emit('error', 'synthetic MediaCodec video output failure');
        await d.f.advance(t, const Duration(seconds: 2));
        expect(_fallbacks(d), isEmpty);
        expect(d.f.players, hasLength(1));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 an output that never matches falls back after the twelve-read window',
    (t) async {
      final d = await _mount(t, output: 'gpu');
      try {
        expect(_fallbacks(d), isEmpty, reason: 'mount advances only ~2 s');
        await d.f.until(t, () => d.f.players.length == 2);
        expect(_fallbacks(d), [_fallbackLine]);
        expect(
          await d.f.finish(
            t,
            PlayerSettingsStorage.getAndroidVideoRendererMode(),
          ),
          AndroidVideoRendererMode.automatic,
        );
        expect(
          d.f.controllers.last.configuration.vo,
          AndroidVideoRendererMode.automatic.videoOutput,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 an output that becomes ready inside the window validates without a fallback',
    (t) async {
      final d = await _mount(t, output: 'null');
      try {
        _native(d.player).properties['current-vo'] =
            AndroidRendererStartupFallbackOutputs.surface;
        await d.f.advance(t, const Duration(seconds: 5));
        expect(_fallbacks(d), isEmpty);
        d.player.emit('error', 'synthetic MediaCodec video output failure');
        await d.f.advance(t, const Duration(seconds: 2));
        expect(_fallbacks(d), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 the direct MediaCodec renderer validates on the gpu output',
    (t) async {
      final d = await _mount(
        t,
        output: AndroidRendererStartupFallbackOutputs.mediaCodec,
        mode: AndroidVideoRendererMode.directMediaCodec,
      );
      try {
        await d.f.advance(t, const Duration(seconds: 5));
        expect(_fallbacks(d), isEmpty);
        d.player.emit('error', 'synthetic MediaCodec video output failure');
        await d.f.advance(t, const Duration(seconds: 2));
        expect(_fallbacks(d), isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a zero-sized boundary abandons the window; the next params start a twelve-read window',
    (t) async {
      final d = await _mount(t, output: 'gpu');
      try {
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        await d.f.advance(t, const Duration(seconds: 4));
        expect(_fallbacks(d), isEmpty, reason: 'the old window exited');
        expect(d.f.players, hasLength(1));
        d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
        final window = await elapsedUntil(d, () => d.f.players.length == 2);
        expect(window, greaterThanOrEqualTo(const Duration(seconds: 3)));
        expect(window, lessThan(const Duration(milliseconds: 3400)));
        expect(_fallbacks(d), [_fallbackLine]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 repeated params inside a window neither restart nor extend it',
    (t) async {
      final d = await _mount(t, output: 'gpu');
      try {
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        await d.f.advance(t, const Duration(seconds: 4));
        d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
        await d.f.advance(t, const Duration(milliseconds: 1500));
        d.player.emit('videoParams', const mk.VideoParams(w: 1920, h: 1080));
        final rest = await elapsedUntil(d, () => d.f.players.length == 2);
        expect(rest, lessThan(const Duration(milliseconds: 1900)));
        expect(_fallbacks(d), [_fallbackLine]);
      } finally {
        await d.close();
      }
    },
  );
}

/// The expected outputs, spelled as the policy reports them.
abstract final class AndroidRendererStartupFallbackOutputs {
  static const surface = 'mediacodec_embed';
  static const mediaCodec = 'gpu';
}
