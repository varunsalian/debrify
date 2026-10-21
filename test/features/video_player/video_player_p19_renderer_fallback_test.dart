import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/subtitle_apply_driver.dart' show applyScreen;

const _snack = 'Direct Surface was unavailable. Using Automatic renderer.';
const _failure = 'synthetic MediaCodec video output failure';

final _live = IptvChannel(
  name: 'Fallback live',
  url: 'https://fallback.test/live/1.ts',
  contentType: 'live',
);

/// The S2b error-driven path: Android override on, renderer validation off.
Future<EngineDriver> _mount(
  WidgetTester t, {
  VideoPlayerScreen screen = applyScreen,
  AndroidVideoRendererMode mode = AndroidVideoRendererMode.directSurface,
  bool android = true,
  void Function(FakePlayer)? configure,
}) async {
  final d = EngineDriver(t, configurePlayer: configure);
  await d.initialize();
  if (android) VpS2Hooks.install(VpS2Hooks(android: () => true));
  await d.f.finish<void>(
    t,
    PlayerSettingsStorage.setAndroidVideoRendererMode(mode),
  );
  await d.mount(screen: screen);
  return d;
}

/// Puts the old player at [position] (state and stream) before the failure.
Future<FakePlayer> _at(EngineDriver d, Duration position) async {
  final old = d.player;
  old.state = old.state.copyWith(position: position);
  old.emit('position', position);
  await d.f.advance(d.t);
  return old;
}

Future<FakePlayer> _rebuilt(EngineDriver d) async {
  await d.f.until(d.t, () => d.f.players.length == 2);
  if (!d.player.readyDelivered) d.player.deliverReady();
  await d.f.advance(d.t, const Duration(seconds: 2));
  return d.player;
}

List<String> _names(FakePlayer p) => [for (final c in p.calls) c.$1];

/// The first [name] call on [p]; its absence is an expectation failure.
(String, Object?) _firstCall(FakePlayer p, String name) {
  expect(_names(p), contains(name));
  return p.calls.firstWhere((c) => c.$1 == name);
}

List<Object?> _seeks(FakePlayer p) => [
  for (final c in p.calls)
    if (c.$1 == 'seek') c.$2,
];

List<String> _fallbackLines(EngineDriver d) =>
    d.decoderLines.where((l) => l.contains(' phase=fallback ')).toList();

void main() {
  tearDown(() => VpS2Hooks.install(null));

  testWidgets(
    'P19 a renderer error tears the old player down, persists Automatic and plays the rebuilt one on open',
    (t) async {
      final d = await _mount(t);
      try {
        final old = await _at(d, Duration.zero);
        final before = old.calls.length;
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(_names(old).skip(before), ['pause', 'dispose']);
        expect(_fallbackLines(d), [
          'DEBRIFY_PLAYER_DECODER generation=1 phase=fallback '
              'status=renderer_startup_failed platform=android backend=libmpv '
              'requested_renderer=direct_surface fallback=automatic '
              'reason=renderer_error',
        ]);
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
        final opens = [
          for (final c in rebuilt.calls)
            if (c.$1 == 'open') c.$2 as (mk.Playable, bool),
        ];
        expect(opens, hasLength(1));
        expect((opens.single.$1 as mk.Media).uri, applyScreen.videoUrl);
        expect(opens.single.$2, isTrue);
        expect(_names(rebuilt), isNot(contains('seek')));
        expect(_names(rebuilt), isNot(contains('play')));
        expect(find.text(_snack), findsOneWidget);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 the rebuilt player restores rate and volume after the reopen',
    (t) async {
      final d = await _mount(t);
      try {
        final old = await _at(d, Duration.zero);
        old.state = old.state.copyWith(rate: 1.5, volume: 70);
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        final names = _names(rebuilt);
        expect(
          [
            for (final c in rebuilt.calls)
              if (c.$1 == 'rate' || c.$1 == 'volume') c,
          ],
          [('rate', 1.5), ('volume', 70.0)],
        );
        expect(names.indexOf('rate'), greaterThan(names.indexOf('open')));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a carried position reopens paused, lands the resume, then plays',
    (t) async {
      final d = await _mount(t);
      try {
        final old = await _at(d, const Duration(minutes: 2));
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        final names = _names(rebuilt);
        final open = _firstCall(rebuilt, 'open');
        expect((open.$2 as (mk.Playable, bool)).$2, isFalse);
        expect(_seeks(rebuilt).take(1), [const Duration(minutes: 2)]);
        expect(names.indexOf('volume'), lessThan(names.indexOf('seek')));
        expect(names.lastIndexOf('play'), greaterThan(names.indexOf('seek')));
        expect(rebuilt.state.playing, isTrue);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a live channel reopens playing with its live options and no resume',
    (t) async {
      final d = await _mount(
        t,
        screen: VideoPlayerScreen(
          videoUrl: _live.url,
          title: _live.name,
          iptvChannels: [_live],
        ),
      );
      try {
        final old = await _at(d, const Duration(minutes: 2));
        final liveOptions =
            (old.platform! as FakeNativePlayer).properties['stream-lavf-o'];
        expect(liveOptions, isNotEmpty);
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        final open = _firstCall(rebuilt, 'open');
        expect((open.$2 as (mk.Playable, bool)).$2, isTrue);
        expect(_names(rebuilt), isNot(contains('seek')));
        expect(
          (rebuilt.platform! as FakeNativePlayer).properties['stream-lavf-o'],
          liveOptions,
        );
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 external audio reopens paused, re-adds the track, then plays',
    (t) async {
      const audio = 'https://fallback.test/dub.m4a';
      final d = await _mount(
        t,
        screen: const VideoPlayerScreen(
          videoUrl: 'https://fallback.test/video.mkv',
          title: 'Fallback audio',
          audioUrl: audio,
        ),
      );
      try {
        final old = await _at(d, Duration.zero);
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        final names = _names(rebuilt);
        final open = _firstCall(rebuilt, 'open');
        expect((open.$2 as (mk.Playable, bool)).$2, isFalse);
        final track = _firstCall(rebuilt, 'audio');
        expect((track.$2 as mk.AudioTrack).id, audio);
        expect(names.indexOf('audio'), greaterThan(names.indexOf('open')));
        expect(names.lastIndexOf('play'), greaterThan(names.indexOf('audio')));
        expect(_names(rebuilt), isNot(contains('seek')));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 the rebuild keeps the video-output claim instead of re-queuing',
    (t) async {
      final d = await _mount(t);
      try {
        final old = await _at(d, Duration.zero);
        var granted = false;
        unawaited(
          VideoOutputLease.acquire(debugLabel: 'probe').then((h) {
            granted = true;
            h.release();
          }),
        );
        old.emit('error', _failure);
        await _rebuilt(d);
        expect(granted, isFalse, reason: 'the slot never changed hands');
        expect(VideoOutputLease.isHeld, isTrue);
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.until(t, () => granted);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 an old player that fails to dispose reports the failed fallback and is disposed again at close',
    (t) async {
      final d = await _mount(t);
      late FakePlayer old;
      try {
        old = await _at(d, Duration.zero);
        old.failures['dispose'] = StateError('native dispose failed');
        old.emit('error', _failure);
        await d.f.advance(t, const Duration(seconds: 2));
        expect(_fallbackLines(d), hasLength(2));
        expect(
          _fallbackLines(d).last,
          'DEBRIFY_PLAYER_DECODER generation=1 phase=fallback status=failed '
          'platform=android backend=libmpv requested_renderer=direct_surface '
          'fallback=automatic',
        );
        expect(d.f.players, hasLength(1));
        expect(find.text(_snack), findsNothing);
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
      expect(_names(old).where((n) => n == 'dispose'), hasLength(2));
    },
  );

  for (final (label, mode, android) in [
    ('the Automatic renderer', AndroidVideoRendererMode.automatic, true),
    (
      'a platform without the Android override',
      AndroidVideoRendererMode.directSurface,
      false,
    ),
  ]) {
    testWidgets('P19 $label never falls back on a renderer error', (t) async {
      final d = await _mount(t, mode: mode, android: android);
      try {
        final old = await _at(d, Duration.zero);
        old.emit('error', _failure);
        await d.f.advance(t, const Duration(seconds: 2));
        expect(_fallbackLines(d), isEmpty);
        expect(d.f.players, hasLength(1));
        expect(_names(old), isNot(contains('dispose')));
      } finally {
        await d.close();
      }
    });
  }

  testWidgets('P19 a non-renderer player error keeps the renderer', (t) async {
    final d = await _mount(t);
    try {
      final old = await _at(d, Duration.zero);
      old.emit('error', 'Failed to open https://fallback.test: 404');
      await d.f.advance(t, const Duration(seconds: 2));
      expect(_fallbackLines(d), isEmpty);
      expect(d.f.players, hasLength(1));
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 closing during the old player disposal abandons the rebuild and strands the video-output slot (follow-up)',
    (t) async {
      final d = await _mount(t);
      final disposal = Completer<void>();
      try {
        final old = await _at(d, Duration.zero);
        old.delays['dispose'] = disposal;
        // A second disposal (the closing screen still claiming the player)
        // parks instead of completing the fake's disposal twice.
        var disposals = 0;
        old.beforeOperation = (name, value) =>
            name == 'dispose' && ++disposals > 1
            ? Completer<void>().future
            : null;
        old.emit('error', _failure);
        await d.f.until(t, () => _names(old).contains('dispose'));
        await t.pumpWidget(const SizedBox.shrink());
        await d.f.advance(t);
        expect(
          _names(old).where((n) => n == 'dispose'),
          hasLength(1),
          reason: 'the closing screen no longer owns the old player',
        );
        disposal.complete();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(d.f.players, hasLength(1), reason: 'nothing is rebuilt');
        expect(
          await d.f.finish(
            t,
            PlayerSettingsStorage.getAndroidVideoRendererMode(),
          ),
          AndroidVideoRendererMode.directSurface,
          reason: 'the closed screen never persists the fallback',
        );
        // Pre-existing (P2-1 follow-up): dispose released nothing because
        // _playerCreated was false, and the fallback returns at !mounted.
        expect(VideoOutputLease.isHeld, isTrue);
        VideoOutputLease.debugReset();
      } finally {
        if (!disposal.isCompleted) disposal.complete();
        await d.close();
      }
    },
  );
}
