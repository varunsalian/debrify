import 'package:debrify/models/tracking_source.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/pip_lifecycle_driver.dart';
import 'dart:async';
import 'package:debrify/services/storage/subtitle_settings_storage.dart';
import 'package:flutter/material.dart';
import 'support/fake_player.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:debrify/models/iptv_playlist.dart';
import 'package:debrify/services/pip_service.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/video_player_environment.dart';
import 'video_player_pip_lifecycle_test.dart' show background, foreground;

void main() {
  testWidgets(
    'PiP seek fans out to Trakt Simkl MDBList in order with the exact rounded target',
    (t) async {
      final f = VideoPlayerEnvironment();
      final tracker = SecondaryTrackerDriver(t, f);
      final d = PipLifecycleDriver(t, f);
      await tracker.initialize(
        targets: {
          TrackingSource.trakt,
          TrackingSource.simkl,
          TrackingSource.mdblist,
        },
      );
      d.installPlatform();
      await d.flushWake();
      try {
        tracker.cipher.hold = true;
        await tracker.observe(() => d.mount(secondaryScreen(trakt: true)));
        tracker.cipher.releaseAll();
        await tracker.drain();
        final timerStart = tracker.heartbeats.length;
        await f.player.pause();
        await d.settle();
        await f.player.play();
        await d.settle();
        expect(tracker.heartbeats.length, timerStart + 3);
        await f.player.seek(const Duration(minutes: 4));
        await d.settle();
        final before = f.network.requests.length;
        tracker.cancellations.clear();
        await d.deliver('onPipAction', 'seek:732.3456');
        await tracker.drain();
        expect(f.player.state.position, const Duration(milliseconds: 972346));
        final checkpoints = f.network.requests
            .skip(before)
            .where((r) => r.url.path.startsWith('/scrobble/'))
            .toList();
        expect(tracker.cancellations, [
          timerStart,
          timerStart + 1,
          timerStart + 2,
        ]);
        expect(checkpoints.map((r) => r.url.host).toSet(), {
          'api.trakt.tv',
          'api.simkl.com',
          'api.mdblist.com',
        });
        tracker.expectRequest(
          tracker.requests.length - 1,
          'stop',
          81.02883333333334,
        );
        tracker.expectCheckpoint(
          'simkl',
          tracker.forTracker('simkl').length - 1,
          'stop',
          81.02883333333334,
        );
        tracker.expectCheckpoint(
          'mdblist',
          tracker.forTracker('mdblist').length - 1,
          'stop',
          81.03,
        );
        expect(d.errors, isEmpty);
      } finally {
        tracker.cipher.releaseAll();
        await d.close();
      }
    },
  );
  for (final (width, height) in [(0, 0), (null, null), (1920, 800)]) {
    testWidgets(
      'PiP Android native aspect payload width=$width height=$height retains zero fallback',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = PipLifecycleDriver(t, f);
        await d.initialize();
        try {
          await d.mount();
          f.player.state = width == null
              ? mk.PlayerState(
                  playing: true,
                  duration: f.player.state.duration,
                  position: f.player.state.position,
                )
              : f.player.state.copyWith(width: width, height: height);
          f.player.configuration.ready?.call();
          await d.settle();
          await d.enter();
          expect(d.named('setAutoEnter').last.arguments, {
            'enabled': true,
            'aspectWidth': width ?? 0,
            'aspectHeight': height ?? 0,
          });
          expect(d.named('enterPip').single.arguments, {
            'aspectWidth': width ?? 0,
            'aspectHeight': height ?? 0,
          });
          expect(d.named('updatePlaybackState').last.arguments, {
            'isPlaying': true,
            'hasNext': false,
            'aspectWidth': width ?? 0,
            'aspectHeight': height ?? 0,
          });
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'PiP iOS plain screen has no session yet restore returns false without platform requests',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      await f.finish(t, SubtitleSettingsStorage.setDefaultAudioLanguage('en'));
      try {
        await d.observe(() => f.mount(t, pipScreen));
        await d.enter();
        final before = f.channels.length;
        expect(
          await f.finish<Object?>(t, d.event('onPipRestore', null)),
          isFalse,
        );
        expect(f.channels.length, before);
        await d.deliver('onPipModeChanged', true);
        expect(f.player.disposed.isCompleted, isFalse);
        expect(
          f.channels
              .skip(before)
              .where(
                (c) => c.$2.method == 'SystemChrome.setPreferredOrientations',
              ),
          isEmpty,
        );
        await d.deliver('onPipModeChanged', false);
        expect(f.player.disposed.isCompleted, isFalse);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP desktop predicate leaves State lifecycle pause and resume inactive',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      VpS2Hooks.install(VpS2Hooks(android: () => false, ios: () => false));
      try {
        await d.mount();
        await background(d);
        expect(d.operations('pause'), hasLength(1));
        await foreground(d);
        expect(d.operations('play'), isEmpty);
        expect(d.named('isSupported'), isEmpty);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP play and pause commands are idempotent at the matching playing state',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      try {
        await d.mount();
        await d.deliver('onPipAction', 'play');
        expect(d.operations('play'), isEmpty);
        expect(d.operations('pause'), isEmpty);
        expect(f.player.state.playing, isTrue);
        await d.deliver('onPipAction', 'pause');
        expect(d.operations('pause'), hasLength(1));
        expect(d.operations('play'), isEmpty);
        expect(f.player.state.playing, isFalse);
        expect(d.named('updatePlaybackState'), isNotEmpty);
        expect(
          (d.named('updatePlaybackState').last.arguments as Map)['isPlaying'],
          isFalse,
        );
        await d.deliver('onPipAction', 'pause');
        expect(d.operations('pause'), hasLength(1));
        expect(d.operations('play'), isEmpty);
        expect(f.player.state.playing, isFalse);
        await d.deliver('onPipAction', 'playpause');
        expect(d.operations('play'), hasLength(1));
        expect(d.operations('pause'), hasLength(1));
        expect(f.player.state.playing, isTrue);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP early audio setup uses false starting and detached defaults before open or readiness',
    (t) async {
      final gate = Completer<void>();
      var held = false;
      final f = VideoPlayerEnvironment(
        native: true,
        configurePlayer: (p) {
          final n = p.platform! as FakeNativePlayer;
          n.heldOperation = (name, v) =>
              !held &&
              name == 'setProperty' &&
              (v as (String, String)).$1 == 'alang';
          n.beforeOperation = (name, v) {
            if (!held &&
                name == 'setProperty' &&
                (v as (String, String)).$1 == 'alang') {
              held = true;
              return gate.future;
            }
            return null;
          };
        },
      );
      final d = PipLifecycleDriver(t, f, ios: true);
      await d.initialize();
      await f.finish(t, SubtitleSettingsStorage.setDefaultAudioLanguage('en'));
      try {
        await d.observe(
          () => t.pumpWidget(
            MaterialApp(navigatorKey: f.navigator, home: pipScreen),
          ),
        );
        await f.until(
          t,
          () => held && find.byType(VideoPlayerScreen).evaluate().isNotEmpty,
        );
        await d.settle();
        d.stateOwner = t.state(find.byType(VideoPlayerScreen));
        expect(d.operations('open'), isEmpty);
        expect(f.player.readyDelivered, isFalse);
        f.player.deliverReady();
        await d.settle();
        await d.enter();
        expect(d.operations('handle'), hasLength(1));
        expect(d.named('enterPip'), hasLength(1));
        PipService.attach(Object(), onMode: (_) {}, onAction: (_) {});
        await d.retire(expectedWake: false);
        gate.complete();
        await d.settle();
        expect(d.errors, isEmpty);
      } finally {
        if (!gate.isCompleted) {
          gate.complete();
        }
        await d.close();
      }
    },
  );
  testWidgets(
    'PiP live background longer than thirty real seconds retunes once instead of playing stale buffer',
    (t) async {
      final f = VideoPlayerEnvironment();
      final d = PipLifecycleDriver(t, f);
      await d.initialize();
      final diagnostics = <String?>[];
      final previousPrint = debugPrint;
      debugPrint = (message, {wrapWidth}) {
        diagnostics.add(message);
        previousPrint(message, wrapWidth: wrapWidth);
      };
      final live = IptvChannel(
        name: 'Lifecycle live',
        url: 'https://live-edge.test/live/1.ts',
        contentType: 'live',
      );
      try {
        await d.mount(
          VideoPlayerScreen(
            videoUrl: live.url,
            title: live.name,
            iptvChannels: [live],
          ),
        );
        await background(d);
        expect(d.operations('open'), hasLength(1));
        // DateTime.now is real wall time in the original: no added clock seam.
        await t.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 31)),
        );
        await foreground(d);
        await d.settle();
        expect(d.operations('open'), hasLength(2));
        expect(
          diagnostics.whereType<String>().any(
            (m) =>
                m.contains('source=lifecycle-rejoin action=retune attempt=1'),
          ),
          isTrue,
        );
        expect(d.operations('play'), isEmpty);
        expect(f.player.state.playlist.medias.single.uri, live.url);
        expect(f.player.state.playing, isTrue);
      } finally {
        debugPrint = previousPrint;
        await d.close();
      }
    },
  );
}
