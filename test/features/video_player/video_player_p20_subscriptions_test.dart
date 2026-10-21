import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/player_visibility.dart';
import 'package:debrify/services/storage/playback_state_store.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';

const _failure = 'synthetic MediaCodec video output failure';
const _screen = VideoPlayerScreen(
  videoUrl: 'https://subs.test/a.mp4',
  title: 'P20 subscriptions',
);
const _a = PlaylistEntry(url: 'https://subs.test/a.mp4', title: 'Subs A');
const _b = PlaylistEntry(url: 'https://subs.test/b.mp4', title: 'Subs B');
const _playlist = VideoPlayerScreen(
  videoUrl: 'https://subs.test/a.mp4',
  title: 'P20 subscriptions playlist',
  disableAutoResume: true,
  startIndex: 0,
  playlist: [_a, _b],
);

double _spinner(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find
          .ancestor(
            of: find.byType(BufferingIndicator),
            matching: find.byType(AnimatedOpacity),
          )
          .first,
    )
    .opacity;

List<String> _opened(FakePlayer p) => [
  for (final c in p.calls)
    if (c.$1 == 'open') ((c.$2 as (mk.Playable, bool)).$1 as mk.Media).uri,
];

/// Mounts on the S2b error path and rebuilds once, returning the old player.
Future<(EngineDriver, FakePlayer)> _rebuilt(
  WidgetTester t, {
  VideoPlayerScreen screen = _screen,
  void Function(FakePlayer)? configure,
}) async {
  final d = EngineDriver(t, configurePlayer: configure);
  await d.initialize();
  VpS2Hooks.install(VpS2Hooks(android: () => true));
  await d.f.finish<void>(
    t,
    PlayerSettingsStorage.setAndroidVideoRendererMode(
      AndroidVideoRendererMode.directSurface,
    ),
  );
  await d.mount(screen: screen);
  final old = d.player;
  old.emit('error', _failure);
  await d.f.until(t, () => d.f.players.length == 2);
  if (!d.player.readyDelivered) d.player.deliverReady();
  await d.f.advance(t, const Duration(seconds: 2));
  await d.f.actions.settle(t);
  return (d, old);
}

Future<Map?> _saved(EngineDriver d, String key) async {
  final map = await d.f.finish(d.t, PlaybackStateStore.getPlaybackStateMap());
  return map[key] as Map?;
}

void main() {
  tearDown(() {
    VpS2Hooks.install(null);
    PlayerVisibility.settleDuration = const Duration(seconds: 30);
  });

  testWidgets(
    'P20 position and duration from a superseded player never reach the saved resume',
    (t) async {
      final (d, old) = await _rebuilt(t);
      try {
        final current = d.player;
        current.state = current.state.copyWith(
          position: const Duration(minutes: 2),
        );
        current.emit('position', const Duration(minutes: 2));
        await d.f.advance(t);
        old.emit('position', const Duration(minutes: 9));
        old.emit('duration', const Duration(minutes: 3));
        await d.f.advance(t, const Duration(seconds: 7));
        await d.f.actions.settle(t);
        final row = await _saved(d, 'video_p20_subscriptions');
        expect(row?['positionMs'], 120000);
        expect(row?['durationMs'], 1200000);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 a superseded player pausing does not change the play state',
    (t) async {
      final (d, old) = await _rebuilt(t);
      try {
        expect(t.widget<Controls>(find.byType(Controls)).isPlaying, isTrue);
        old.emit('playing', false);
        await d.f.advance(t, const Duration(milliseconds: 100));
        expect(t.widget<Controls>(find.byType(Controls)).isPlaying, isTrue);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 the current player finishing advances the playlist to the next entry',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount(screen: _playlist);
        d.player.emit('completed', true);
        await d.f.advance(t, const Duration(seconds: 2));
        await d.f.actions.settle(t);
        expect(_opened(d.player), [_a.url, _b.url]);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 buffering raises the spinner only after the debounce and clears it at once',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final p = d.player;
        p.state = p.state.copyWith(buffering: true);
        p.emit('buffering', true);
        await d.f.advance(t, const Duration(milliseconds: 700));
        expect(_spinner(t), 0);
        await d.f.advance(t, const Duration(milliseconds: 200));
        expect(_spinner(t), 1);
        p.state = p.state.copyWith(buffering: false);
        p.emit('buffering', false);
        await d.f.advance(t);
        expect(_spinner(t), 0);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 buffering that ends inside the debounce never raises the spinner',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final p = d.player;
        p.state = p.state.copyWith(buffering: true);
        p.emit('buffering', true);
        await d.f.advance(t, const Duration(milliseconds: 400));
        // The native state recovers before the debounce fires.
        p.state = p.state.copyWith(buffering: false);
        await d.f.advance(t, const Duration(milliseconds: 600));
        expect(_spinner(t), 0);
        p.state = p.state.copyWith(buffering: true);
        p.emit('buffering', true);
        await d.f.advance(t, const Duration(milliseconds: 400));
        p.state = p.state.copyWith(buffering: false);
        p.emit('buffering', false);
        await d.f.advance(t, const Duration(milliseconds: 600));
        expect(_spinner(t), 0);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 visibility: buffering, pausing and finishing withdraw the screen from refresh until playback settles again',
    (t) async {
      PlayerVisibility.settleDuration = const Duration(milliseconds: 500);
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final p = d.player;
        await d.f.advance(t, const Duration(seconds: 1));
        expect(PlayerVisibility.refreshAllowed.value, isTrue);
        Future<void> edge(String name, Object value, bool expected) async {
          p.emit(name, value);
          await d.f.advance(t);
          expect(
            PlayerVisibility.refreshAllowed.value,
            expected,
            reason: '$name=$value',
          );
        }

        p.state = p.state.copyWith(buffering: true);
        await edge('buffering', true, false);
        p.state = p.state.copyWith(buffering: false);
        await edge('buffering', false, false);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(PlayerVisibility.refreshAllowed.value, isTrue);
        p.state = p.state.copyWith(playing: false);
        await edge('playing', false, false);
        p.state = p.state.copyWith(playing: true);
        await edge('playing', true, false);
        await d.f.advance(t, const Duration(seconds: 1));
        expect(PlayerVisibility.refreshAllowed.value, isTrue);
        await edge('completed', true, false);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P20 visibility: a nonfatal error while paused withdraws the screen and one while playing keeps it',
    (t) async {
      PlayerVisibility.settleDuration = const Duration(milliseconds: 500);
      final d = EngineDriver(t);
      await d.initialize();
      try {
        await d.mount();
        final p = d.player;
        await d.f.advance(t, const Duration(seconds: 1));
        expect(PlayerVisibility.refreshAllowed.value, isTrue);
        p.emit('error', 'nonfatal demuxer warning');
        await d.f.advance(t);
        expect(PlayerVisibility.refreshAllowed.value, isTrue);
        // Paused natively without a state event: the error re-evaluates.
        p.state = p.state.copyWith(playing: false);
        p.emit('error', 'nonfatal demuxer warning');
        await d.f.advance(t);
        expect(PlayerVisibility.refreshAllowed.value, isFalse);
      } finally {
        await d.close();
      }
    },
  );

  for (final live in [false, true]) {
    testWidgets(
      'P20 an IPTV ${live ? 'live' : 'VOD'} 404 error is reported for the tuned channel',
      (t) async {
        final d = EngineDriver(t);
        await d.initialize();
        final channel = IptvChannel(
          name: 'P20 error channel',
          url: 'https://subs.test/channel.ts',
          contentType: live ? 'live' : 'vod',
          group: 'News',
        );
        try {
          await d.mount(
            screen: VideoPlayerScreen(
              videoUrl: channel.url,
              title: channel.name,
              iptvChannels: [channel],
              iptvStartIndex: 0,
            ),
          );
          d.player.emit('error', 'HTTP error 404 Not Found');
          await d.f.advance(t, const Duration(milliseconds: 100));
          expect(
            find.text(
              "P20 error channel didn't play — HTTP error 404 Not Found",
            ),
            findsOneWidget,
          );
        } finally {
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P20 a rebuild cancels each instance listener once, in order, even when the first cancel throws',
    (t) async {
      final cancels = <String>[];
      var created = 0;
      final (d, old) = await _rebuilt(
        t,
        configure: (p) {
          if (++created != 1) return;
          p.observeStream = (name, source) => _CancelStream(source, () {
            cancels.add(name);
            if (name == 'position') throw StateError('cancel failed');
          });
        },
      );
      try {
        expect(cancels, [
          'position',
          'duration',
          'playing',
          'videoParams',
          'completed',
          'buffering',
          'error',
          'log',
        ]);
        expect(old.disposed.isCompleted, isTrue);
        expect(d.f.players, hasLength(2));
        expect(d.errors, isEmpty);
      } finally {
        await d.close();
      }
    },
  );
}

class _CancelStream<T> extends Stream<T> {
  _CancelStream(this.source, this.onCancel);
  final Stream<T> source;
  final void Function() onCancel;
  @override
  bool get isBroadcast => source.isBroadcast;
  @override
  StreamSubscription<T> listen(
    void Function(T)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
    // Only the instance listeners bound by the screen are observed.
    return StackTrace.current.toString().contains(
          'bindPlayerInstanceSubscriptions',
        )
        ? _CancelSubscription(subscription, onCancel)
        : subscription;
  }
}

class _CancelSubscription<T> implements StreamSubscription<T> {
  _CancelSubscription(this.source, this.onCancel);
  final StreamSubscription<T> source;
  final void Function() onCancel;
  @override
  Future<void> cancel() async {
    await source.cancel();
    onCancel();
  }

  @override
  void onData(void Function(T)? handler) => source.onData(handler);
  @override
  void onError(Function? handler) => source.onError(handler);
  @override
  void onDone(void Function()? handler) => source.onDone(handler);
  @override
  void pause([Future<void>? resumeSignal]) => source.pause(resumeSignal);
  @override
  void resume() => source.resume();
  @override
  bool get isPaused => source.isPaused;
  @override
  Future<E> asFuture<E>([E? futureValue]) => source.asFuture(futureValue);
}
