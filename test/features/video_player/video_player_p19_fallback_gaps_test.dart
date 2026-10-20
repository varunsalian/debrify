import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/lease_steps.dart' show elapsedUntil;
import 'support/player_actions.dart';

const _failure = 'synthetic MediaCodec video output failure';
const _surface = 'mediacodec_embed';

/// The S2b error-driven path: Android override on, validation off.
Future<EngineDriver> _mountErrorPath(
  WidgetTester t, {
  void Function(FakePlayer)? configure,
  String? audioLanguage,
}) async {
  final d = EngineDriver(t, configurePlayer: configure);
  await d.initialize();
  if (audioLanguage != null) {
    await d.f.finish<void>(
      t,
      SubtitleSettingsStorage.setDefaultAudioLanguage(audioLanguage),
    );
  }
  VpS2Hooks.install(VpS2Hooks(android: () => true));
  await d.f.finish<void>(
    t,
    PlayerSettingsStorage.setAndroidVideoRendererMode(
      AndroidVideoRendererMode.directSurface,
    ),
  );
  await d.mount();
  return d;
}

/// The S2f validation path with every `current-vo` read answering [output].
Future<EngineDriver> _mountValidation(
  WidgetTester t, {
  required String output,
}) async {
  final d = EngineDriver(
    t,
    configurePlayer: (p) {
      (p.platform! as FakeNativePlayer).properties['current-vo'] = output;
    },
  );
  await d.initialize();
  VpS2Hooks.install(
    VpS2Hooks(android: () => true, androidRendererValidation: () => true),
  );
  await d.f.finish<void>(
    t,
    PlayerSettingsStorage.setAndroidVideoRendererMode(
      AndroidVideoRendererMode.directSurface,
    ),
  );
  await d.mount();
  return d;
}

Future<FakePlayer> _rebuilt(EngineDriver d) async {
  await d.f.until(d.t, () => d.f.players.length == 2);
  if (!d.player.readyDelivered) d.player.deliverReady();
  await d.f.advance(d.t, const Duration(seconds: 2));
  return d.player;
}

List<String> _names(FakePlayer p) => [for (final c in p.calls) c.$1];

List<Object?> _seeks(FakePlayer p) => [
  for (final c in p.calls)
    if (c.$1 == 'seek') c.$2,
];

List<String> _fallbackLines(EngineDriver d) =>
    d.decoderLines.where((l) => l.contains(' phase=fallback ')).toList();

int _probes(EngineDriver d) =>
    d.timers.where((x) => x.stack.contains('scheduleDecoderProbe')).length;

void main() {
  tearDown(() => VpS2Hooks.install(null));

  testWidgets(
    'P19 the fallback carries the old player position when the stream never reported one',
    (t) async {
      final d = await _mountErrorPath(t);
      try {
        final old = d.player;
        old.emit('position', Duration.zero);
        await d.f.advance(t);
        // Only the player state moved; no position event reached the screen.
        old.state = old.state.copyWith(position: const Duration(minutes: 3));
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(_seeks(rebuilt).take(1), [const Duration(minutes: 3)]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 the fallback carries the reported position over the player state',
    (t) async {
      final d = await _mountErrorPath(t);
      try {
        final old = d.player;
        old.state = old.state.copyWith(position: const Duration(minutes: 3));
        old.emit('position', const Duration(minutes: 2));
        await d.f.advance(t);
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(_seeks(rebuilt).take(1), [const Duration(minutes: 2)]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a user-paused session reopens paused and is never played by the fallback',
    (t) async {
      final d = await _mountErrorPath(t);
      try {
        final old = d.player;
        old.state = old.state.copyWith(playing: true);
        old.emit('playing', true);
        await d.f.advance(t);
        playerControls(t).onPlayPause();
        await d.f.advance(t);
        expect(_names(old), contains('pause'), reason: 'the user paused');
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(_names(rebuilt), contains('open'));
        final open = rebuilt.calls.firstWhere((c) => c.$1 == 'open');
        expect((open.$2 as (mk.Playable, bool)).$2, isFalse);
        expect(_names(rebuilt), isNot(contains('play')));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 after a fallback the rebuilt player is on Automatic and never falls back again',
    (t) async {
      final d = await _mountErrorPath(t);
      try {
        d.player.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(_fallbackLines(d), hasLength(1));
        rebuilt.emit('error', _failure);
        await d.f.advance(t, const Duration(seconds: 3));
        expect(_fallbackLines(d), hasLength(1));
        expect(d.f.players, hasLength(2));
        expect(_names(rebuilt), isNot(contains('dispose')));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets('P19 the fallback notice is shown for four seconds', (t) async {
    final d = await _mountErrorPath(t);
    try {
      d.player.emit('error', _failure);
      await _rebuilt(d);
      expect(
        t.widget<SnackBar>(find.byType(SnackBar)).duration,
        const Duration(seconds: 4),
      );
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 the rebuilt player receives the audio-output configuration before its open',
    (t) async {
      final writes = <FakePlayer, List<String>>{};
      final d = await _mountErrorPath(
        t,
        audioLanguage: 'es',
        configure: (p) {
          final seq = writes[p] = [];
          p.beforeOperation = (name, value) => seq.add('player:$name');
          (p.platform! as FakeNativePlayer).beforeOperation = (name, value) {
            if (name != 'setProperty') return;
            final (property, v) = value as (String, String);
            if (const {
              'ao',
              'audio-channels',
              'audio-spdif',
              'alang',
            }.contains(property)) {
              seq.add('set:$property=$v');
            }
          };
        },
      );
      try {
        final old = d.player;
        List<String> beforeOpen(FakePlayer p) =>
            writes[p]!.take(writes[p]!.indexOf('player:open')).toList();
        final configured = beforeOpen(old);
        expect(configured, isNotEmpty);
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(beforeOpen(rebuilt), configured);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a single expected output read does not validate the renderer',
    (t) async {
      var reads = 0;
      final d = EngineDriver(
        t,
        configurePlayer: (p) {
          final native = p.platform! as FakeNativePlayer;
          native.properties['current-vo'] = _surface;
          native.beforeOperation = (name, value) {
            if (name == 'getProperty' && value == 'current-vo') {
              // Expected on the first read only.
              if (++reads == 2) native.properties['current-vo'] = 'gpu';
            }
          };
        },
      );
      await d.initialize();
      VpS2Hooks.install(
        VpS2Hooks(android: () => true, androidRendererValidation: () => true),
      );
      try {
        await d.f.finish<void>(
          t,
          PlayerSettingsStorage.setAndroidVideoRendererMode(
            AndroidVideoRendererMode.directSurface,
          ),
        );
        await d.mount();
        await d.f.until(t, () => d.f.players.length == 2);
        expect(_fallbackLines(d), hasLength(1));
        expect(
          _fallbackLines(d).single,
          endsWith('reason=requested_output_not_ready'),
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a boundary followed at once by new params runs one full window from the new params',
    (t) async {
      final d = await _mountValidation(t, output: 'gpu');
      try {
        expect(_fallbackLines(d), isEmpty);
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        d.player.emit('videoParams', const mk.VideoParams(w: 1280, h: 720));
        final window = await elapsedUntil(
          d,
          () => d.f.players.length == 2,
          step: const Duration(milliseconds: 4),
          limit: const Duration(seconds: 5),
        );
        expect(window, greaterThanOrEqualTo(const Duration(seconds: 3)));
        expect(window, lessThan(const Duration(milliseconds: 3008)));
        expect(_fallbackLines(d), hasLength(1));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 an observer callback after a media boundary schedules no probe',
    (t) async {
      final d = await _mountValidation(t, output: _surface);
      try {
        final native = d.player.platform! as FakeNativePlayer;
        d.player.emit('videoParams', const mk.VideoParams(w: 0, h: 0));
        await d.f.advance(t);
        final before = _probes(d);
        await d.observe(() => native.observers['current-vo']!(_surface));
        await d.observe(() => native.observers['hwdec-current']!('mediacodec'));
        expect(_probes(d), before);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 the replaced player observers stop re-arming the probe after a fallback',
    (t) async {
      final d = await _mountValidation(t, output: 'gpu');
      try {
        final old = d.player.platform! as FakeNativePlayer;
        await _rebuilt(d);
        final before = _probes(d);
        await d.observe(() => old.observers['current-vo']!('gpu'));
        await d.observe(() => old.observers['hwdec-current']!('mediacodec'));
        expect(_probes(d), before);
      } finally {
        await d.close();
      }
    },
  );
}
