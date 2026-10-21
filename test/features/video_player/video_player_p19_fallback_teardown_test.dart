import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'package:debrify/screens/video_player/widgets/controls.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/widgets/video_output_lease.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'support/engine_driver.dart';
import 'support/fake_player.dart';
import 'support/lease_steps.dart';

const _failure = 'synthetic MediaCodec video output failure';
const _proceeding = 'VideoOutputLease: player proceeding without the slot';
const _autoSyncSkipped = 'SubtitleAutoSync: not installing';

Future<void> _armErrorPath(EngineDriver d) async {
  VpS2Hooks.install(VpS2Hooks(android: () => true));
  await d.f.finish<void>(
    d.t,
    PlayerSettingsStorage.setAndroidVideoRendererMode(
      AndroidVideoRendererMode.directSurface,
    ),
  );
}

/// The S2b error-driven path: Android override on, validation off.
Future<EngineDriver> _mount(WidgetTester t) async {
  final d = EngineDriver(t);
  await d.initialize();
  await _armErrorPath(d);
  await d.mount();
  return d;
}

List<String> _names(FakePlayer p) => [for (final c in p.calls) c.$1];

double _spinnerOpacity(WidgetTester t) => t
    .widget<AnimatedOpacity>(
      find.ancestor(
        of: find.byType(BufferingIndicator),
        matching: find.byType(AnimatedOpacity),
      ),
    )
    .opacity;

void main() {
  tearDown(() => VpS2Hooks.install(null));

  testWidgets(
    'P19 while the old player tears down the screen drops its video, controls and spinner',
    (t) async {
      final d = await _mount(t);
      final hold = Completer<void>();
      try {
        final old = d.player;
        old.state = old.state.copyWith(playing: true, buffering: true);
        old.emit('playing', true);
        old.emit('buffering', true);
        await d.f.advance(t, const Duration(seconds: 2));
        expect(find.byType(mkv.Video), findsOneWidget);
        expect(find.byType(Controls), findsOneWidget);
        expect(_spinnerOpacity(t), 1);
        old.delays['pause'] = hold;
        old.emit('error', _failure);
        await d.f.until(t, () => _names(old).contains('pause'));
        await d.f.advance(t, const Duration(milliseconds: 500));
        expect(find.byType(mkv.Video), findsNothing);
        expect(find.byType(Controls), findsNothing);
        expect(_spinnerOpacity(t), 0);
        hold.complete();
        await d.f.until(t, () => d.f.players.length == 2);
      } finally {
        if (!hold.isCompleted) hold.complete();
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 the rebuilt player gets its own subtitle auto-sync install',
    (t) async {
      final d = await _mount(t);
      try {
        int installs() =>
            d.logs.where((l) => l.startsWith(_autoSyncSkipped)).length;
        final before = installs();
        expect(before, greaterThan(0));
        d.player.emit('error', _failure);
        await d.f.until(t, () => d.f.players.length == 2);
        d.player.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(installs(), before + 1);
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a carried position waits for the rebuilt media duration before restoring',
    (t) async {
      var created = 0;
      final d = EngineDriver(
        t,
        configurePlayer: (p) {
          // Hold back the rebuilt player's first frame (and its duration).
          if (++created == 2) p.onOpen = () {};
        },
      );
      await d.initialize();
      await _armErrorPath(d);
      await d.mount();
      try {
        final old = d.player;
        old.state = old.state.copyWith(position: const Duration(minutes: 2));
        old.emit('position', const Duration(minutes: 2));
        await d.f.advance(t);
        old.emit('error', _failure);
        await d.f.until(t, () => d.f.players.length == 2);
        final rebuilt = d.player;
        if (!rebuilt.readyDelivered) rebuilt.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(_names(rebuilt), contains('open'));
        expect(_names(rebuilt), isNot(contains('rate')));
        expect(_names(rebuilt), isNot(contains('seek')));
        rebuilt.publishFrame();
        d.f.controllers.last.publishFrame();
        await d.f.advance(t, const Duration(seconds: 2));
        expect(_names(rebuilt), containsAllInOrder(['rate', 'seek']));
      } finally {
        await d.close();
      }
    },
  );

  testWidgets(
    'P19 a rebuild after a timed-out claim waits for the slot again',
    (t) async {
      final d = EngineDriver(t);
      await d.initialize();
      await _armErrorPath(d);
      final trailer = await d.f.finish(
        t,
        VideoOutputLease.acquire(debugLabel: 'trailer'),
      );
      try {
        await pumpScreen(d);
        await elapsedUntil(d, () => d.f.players.isNotEmpty);
        await finishMount(d);
        int waits() => d.logs.where((l) => l.startsWith(_proceeding)).length;
        expect(waits(), 1);
        d.player.emit('error', _failure);
        final rebuild = await elapsedUntil(d, () => d.f.players.length == 2);
        expect(waits(), 2);
        expect(rebuild, greaterThanOrEqualTo(const Duration(seconds: 3)));
        d.player.deliverReady();
        await d.f.advance(t, const Duration(seconds: 2));
      } finally {
        trailer.release();
        await d.close();
      }
    },
  );
}
