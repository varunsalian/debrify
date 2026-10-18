import 'dart:async';

import 'package:debrify/models/android_video_renderer_mode.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/player_settings_storage.dart';
import 'package:debrify/utils/platform_util.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/startup_driver.dart';

const outputError = 'fixture MediaCodec video output failure';

Future<void> renderer(
  StartupDriver d, {
  bool android = true,
  bool automatic = false,
}) async {
  VpS2Hooks.install(VpS2Hooks(android: () => android));
  await d.f.finish(
    d.t,
    PlayerSettingsStorage.setAndroidVideoRendererMode(
      automatic
          ? AndroidVideoRendererMode.automatic
          : AndroidVideoRendererMode.directSurface,
    ),
  );
}

void main() {
  for (final accepted in [false, true]) {
    testWidgets(
      'P16 renderer listener runs before the pending VOD probe; already accepted=$accepted and late failure stops the live replacement only on rejection',
      (t) async {
        final d = StartupDriver(t, native: true);
        await d.initialize();
        await renderer(d);
        final a = startupSource('renderer-overlap');
        final ack = d.openGates[a.directUrl!] = Completer<void>();
        try {
          await d.begin(d.screen(sources: [a]));
          await d.openEntered();
          final old = d.player;
          if (accepted) {
            d.frame();
            await d.result();
          }
          d.openGates.remove(a.directUrl!);
          old.emit('error', outputError);
          await d.f.until(t, () => d.f.players.length == 2);
          final fresh = d.player;
          fresh.deliverReady();
          await d.openEntered(2);
          d.frame();
          await d.f.until(t, () => fresh.calls.any((c) => c.$1 == 'rate'));
          expect(old.disposed.isCompleted, isTrue);
          expect(old.handleValue, isNot(fresh.handleValue));
          expect(d.activeProbes, hasLength(5));
          expect(d.activeProbes.every((s) => identical(s.player, old)), isTrue);
          expect(
            d.event('candidate_result').singleOrNull,
            contains(
              accepted
                  ? 'ok=true reason=decoded_video'
                  : 'ok=false reason=player_error',
            ),
          );
          expect(
            d.event('candidate_result').singleOrNull,
            isNot(contains('renderer_fallback_deferred')),
            reason:
                'The earlier real renderer listener stamps fallbackInProgress before this probe sees the event',
          );
          expect(ack.isCompleted, isFalse);
          expect(d.commits, isEmpty);
          ack.complete();
          await d.f.until(t, () => d.activeProbes.isEmpty);
          if (accepted) {
            await d.committed();
            expect(fresh.calls.where((c) => c.$1 == 'stop'), isEmpty);
            expect(d.commits, [a]);
          } else {
            await d.f.until(t, () => fresh.calls.any((c) => c.$1 == 'stop'));
            expect(fresh.calls.where((c) => c.$1 == 'stop'), hasLength(1));
            expect(
              old.calls.where((c) => c.$1 == 'stop'),
              isEmpty,
              reason:
                  'The original failure path reads the live _player after its await',
            );
            expect(d.commits, isEmpty);
          }
          expect(d.event('candidate_result'), hasLength(1));
        } finally {
          ack.completeIfPending();
          await d.close();
        }
      },
    );
  }

  testWidgets(
    'P16 transition blocks actual renderer fallback but the explicit VOD probe still defers and commits the errored pick',
    (t) async {
      final d = StartupDriver(t, native: true, autoFrame: true);
      await d.initialize();
      await renderer(d);
      final a = startupSource('transition-a');
      final b = startupSource('transition-b');
      final ack = Completer<void>();
      try {
        await d.begin(
          d.screen(sources: [a, b], resolve: (s) async => s.directUrl),
        );
        await d.committed();
        await d.settle();
        final sheet = await d.sheet();
        d.openGates[b.directUrl!] = ack;
        d.replies[b.directUrl!] = (_) {};
        final action = d.select(sheet, 1, b.directUrl!);
        await d.openEntered(2);
        d.player.emit('error', outputError);
        await d.result(count: 2);
        expect(
          d.event('candidate_result').lastOrNull,
          contains('ok=true reason=renderer_fallback_deferred'),
        );
        expect(
          d.f.players,
          hasLength(1),
          reason:
              '_isTransitioning excludes actual fallback, unlike shouldArm in the probe',
        );
        expect(action.isCompleted, isFalse);
        expect(d.commits, [a]);
        ack.complete();
        await d.f.finish(t, action.future);
        await d.committed(2);
        expect(d.commits, [a, b]);
        expect(d.player.state.playlist.medias.single.uri, b.directUrl);
        expect(d.player.calls.where((c) => c.$1 == 'stop'), isEmpty);
        expect(d.f.players, hasLength(1));
      } finally {
        ack.completeIfPending();
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 debrid pre-open renderer deferral can accept before a media exists for actual fallback',
    (t) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      await renderer(d);
      final a = startupSource('debrid-before-media', type: StreamType.torrent);
      d.prearm = Completer<void>();
      try {
        await d.begin(d.screen(sources: [a]));
        await d.f.until(t, () => d.prearmEntered);
        d.player.emit('error', outputError);
        await d.result();
        expect(
          d.event('candidate_result').singleOrNull,
          contains('ok=true reason=renderer_fallback_deferred'),
        );
        expect(d.opens, isEmpty);
        expect(
          d.f.players,
          hasLength(1),
          reason: 'Actual fallback additionally needs _activeOpenedMedia',
        );
        d.prearm!.complete();
        await d.openEntered();
        await d.committed();
        d.frame();
        await d.settle();
        expect(d.commits, [a]);
        expect(d.f.players, hasLength(1));
      } finally {
        await d.close();
      }
    },
  );

  for (final guard in [
    'Android false',
    'TV became true',
    'automatic',
    'ordinary error',
  ]) {
    testWidgets('P16 renderer candidate deferral preserves $guard guard', (
      t,
    ) async {
      final d = StartupDriver(t, native: true);
      await d.initialize();
      await renderer(d, android: true, automatic: guard == 'automatic');
      final a = startupSource('renderer-guard');
      try {
        await d.begin(d.screen(sources: [a]));
        await d.openEntered();
        if (guard == 'Android false') {
          VpS2Hooks.install(VpS2Hooks(android: () => false));
        }
        if (guard == 'TV became true') {
          PlatformUtil.debugSetAndroidTvCached(true);
        }
        d.player.emit(
          'error',
          guard == 'ordinary error' ? 'fixture HTTP 404' : outputError,
        );
        await d.result();
        expect(
          d.event('candidate_result').singleOrNull,
          contains('ok=false reason=player_error'),
        );
        expect(d.f.players, hasLength(1));
        expect(d.commits, isEmpty);
        expect(d.player.calls.where((c) => c.$1 == 'stop'), hasLength(1));
      } finally {
        PlatformUtil.debugSetAndroidTvCached(false);
        await d.close();
      }
    });
  }
}
