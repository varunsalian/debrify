import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/playlist_view_mode.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:shared_preferences/shared_preferences.dart';
// Existing preferences transport, without changing application dependencies.
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/subtitle_apply_driver.dart' show applyScreen;

const _failure = 'synthetic MediaCodec video output failure';
const _surface = 'mediacodec_embed';
const _url = 'https://player.test/apply-original.mp4';
const _next = 'https://player.test/fallback-next.mp4';

const _playlistScreen = VideoPlayerScreen(
  videoUrl: _url,
  title: 'Fallback playlist',
  viewMode: PlaylistViewMode.raw,
  disableAutoResume: true,
  startIndex: 0,
  playlist: [
    PlaylistEntry(url: _url, title: 'first'),
    PlaylistEntry(url: _next, title: 'second'),
  ],
);

/// The S2b error-driven path: Android override on, validation off.
Future<EngineDriver> _mount(
  WidgetTester t, {
  VideoPlayerScreen screen = applyScreen,
  void Function(FakePlayer)? configure,
  Future<void> Function(EngineDriver)? before,
  bool validation = false,
  bool settle = true,
}) async {
  final d = EngineDriver(t, configurePlayer: configure);
  await d.initialize();
  if (before != null) await before(d);
  VpS2Hooks.install(
    VpS2Hooks(
      android: () => true,
      androidRendererValidation: validation ? () => true : null,
    ),
  );
  await d.f.finish<void>(
    t,
    PlayerSettingsStorage.setAndroidVideoRendererMode(
      AndroidVideoRendererMode.directSurface,
    ),
  );
  await d.mount(screen: screen, settleInitialization: settle);
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

List<String> _opened(FakePlayer p) => [
  for (final c in p.calls)
    if (c.$1 == 'open') ((c.$2 as (mk.Playable, bool)).$1 as mk.Media).uri,
];

List<String> _fallbackLines(EngineDriver d) =>
    d.decoderLines.where((l) => l.contains(' phase=fallback ')).toList();

Future<int?> _storedPosition(EngineDriver d) async {
  final row = await d.f.finish(d.t, VideoResumeStorage.getVideoResume(_url));
  return row?['positionMs'] as int?;
}

/// Fails only the renderer-mode preference writes.
class _RendererWriteFailure extends InMemorySharedPreferencesStore {
  _RendererWriteFailure(super.values) : super.withData();
  int failures = 0;
  @override
  Future<bool> setValue(String type, String key, Object value) async {
    if (key.contains('android_video_renderer')) {
      failures++;
      throw StateError('synthetic preferences failure');
    }
    return super.setValue(type, key, value);
  }
}

void main() {
  tearDown(() => VpS2Hooks.install(null));

  testWidgets(
    'P19 a rebuild during an unlanded resume seek reopens at the promised target',
    (t) async {
      var created = 0;
      final held = Completer<void>();
      final d = await _mount(
        t,
        before: (d) => d.f.finish(
          t,
          VideoResumeStorage.upsertVideoResume(_url, {
            'positionMs': 180000,
            'speed': 1.0,
            'aspect': 'contain',
          }),
        ),
        // The startup resume seek never acknowledges on the old player.
        configure: (p) {
          if (++created == 1) p.delays['seek'] = held;
        },
        // The held seek parks startup before its periodic save begins.
        settle: false,
      );
      try {
        final old = d.player;
        await d.f.until(t, () => _seeks(old).isNotEmpty);
        expect(_seeks(old), [const Duration(minutes: 3)]);
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(_seeks(rebuilt).take(1), [const Duration(minutes: 3)]);
      } finally {
        // The old startup chain then finds its media superseded.
        if (!held.isCompleted) held.complete();
        await d.f.advance(t, const Duration(seconds: 2));
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 the rebuilt player re-protects the carried position against a restart at the start',
    (t) async {
      var created = 0;
      final d = await _mount(
        t,
        // The rebuilt stream answers its seek by restarting near the start.
        configure: (p) {
          if (++created == 2) {
            p.seekAcknowledgementPosition = const Duration(seconds: 30);
          }
        },
      );
      try {
        final old = d.player;
        old.state = old.state.copyWith(position: const Duration(minutes: 5));
        old.emit('position', const Duration(minutes: 5));
        await d.f.advance(t);
        old.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(_seeks(rebuilt).take(1), [const Duration(minutes: 5)]);
        expect(rebuilt.state.position, const Duration(seconds: 30));
        // The next autosave tick files the carried target, not the artifact.
        await d.f.advance(t, const Duration(seconds: 7));
        expect(await _storedPosition(d), 300000);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 navigation while the old player is disposing wins over the rebuild',
    (t) async {
      final d = await _mount(t, screen: _playlistScreen);
      final disposing = Completer<void>();
      try {
        final old = d.player;
        old.delays['dispose'] = disposing;
        old.emit('error', _failure);
        await d.f.until(t, () => _names(old).contains('dispose'));
        await d.observe(() => t.sendKeyEvent(LogicalKeyboardKey.keyN));
        await d.f.advance(t, const Duration(milliseconds: 500));
        expect(_opened(old).last, _next, reason: 'Next took the screen');
        disposing.complete();
        final rebuilt = await _rebuilt(d);
        expect(_opened(rebuilt), isNot(contains(_url)));
      } finally {
        if (!disposing.isCompleted) disposing.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a fallback while the app is backgrounded reopens without playing',
    (t) async {
      final d = await _mount(t);
      final disposing = Completer<void>();
      try {
        final old = d.player;
        old.state = old.state.copyWith(playing: true);
        old.emit('playing', true);
        await d.f.advance(t);
        old.delays['dispose'] = disposing;
        old.emit('error', _failure);
        await d.f.until(t, () => _names(old).contains('dispose'));
        for (final state in const [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
        ]) {
          d.observe(() => t.binding.handleAppLifecycleStateChanged(state));
        }
        await d.f.advance(t);
        disposing.complete();
        final rebuilt = await _rebuilt(d);
        expect(_opened(rebuilt), [_url]);
        final open = rebuilt.calls.firstWhere((c) => c.$1 == 'open');
        expect((open.$2 as (mk.Playable, bool)).$2, isFalse);
        expect(_names(rebuilt), isNot(contains('play')));
      } finally {
        if (!disposing.isCompleted) disposing.complete();
        for (final state in const [
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          t.binding.handleAppLifecycleStateChanged(state);
        }
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a failed renderer-setting write still rebuilds on Automatic',
    (t) async {
      final d = await _mount(t);
      final old = SharedPreferencesStorePlatform.instance;
      final store = _RendererWriteFailure(await t.runAsync(old.getAll) ?? {});
      SharedPreferencesStorePlatform.instance = store;
      try {
        d.player.emit('error', _failure);
        final rebuilt = await _rebuilt(d);
        expect(store.failures, 1);
        expect(_opened(rebuilt), [_url]);
        expect(
          _fallbackLines(d).where((l) => l.contains(' status=failed ')),
          isEmpty,
        );
      } finally {
        SharedPreferencesStorePlatform.instance = old;
        SharedPreferences.resetStatic();
        await d.close();
      }
    },
  );

  testWidgets('P19 the rebuilt player restores the track preferences', (
    t,
  ) async {
    final d = await _mount(t);
    try {
      int restores() => d.logs
          .where((l) => l.startsWith('SubAuto: _restoreTrackPreferences '))
          .length;
      await d.f.advance(t, const Duration(seconds: 2));
      final before = restores();
      d.player.emit('error', _failure);
      await _rebuilt(d);
      expect(restores(), before + 1);
    } finally {
      await d.close();
    }
  });

  testWidgets(
    'P19 a failed output read gets the rest of the window, then falls back',
    (t) async {
      var failed = false;
      final d = await _mount(
        t,
        validation: true,
        configure: (p) {
          final native = p.platform! as FakeNativePlayer;
          native.properties['current-vo'] = _surface;
          native.beforeOperation = (name, value) {
            if (name != 'getProperty' || value != 'current-vo') return null;
            if (!failed) {
              failed = true;
              throw StateError('synthetic property failure');
            }
            native.properties['current-vo'] = 'gpu';
            return null;
          };
        },
      );
      try {
        await d.f.until(t, () => d.f.players.length == 2);
        expect(failed, isTrue);
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
}
