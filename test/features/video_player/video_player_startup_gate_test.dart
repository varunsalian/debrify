import 'dart:async';
import 'package:debrify/widgets/playback_startup_view.dart';
import 'package:flutter/widgets.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/local_completion_driver.dart';
import 'support/secondary_tracker_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';
import 'support/startup_driver.dart';
import 'support/trakt_transport.dart';

void main() {
  TraktTestTransport.install();
  for (final mode in [
    'start',
    'watched stop',
    'disabled',
    'paused',
    'zero duration',
    'disposed',
  ]) {
    testWidgets(
      'P16 final gate release distinguishes attempted start, resulting action and heartbeat: $mode',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        TraktTestTransport.instance.attach(d.f);
        final cipher = (await t.runAsync(
          () => seedTrakt(target: mode != 'disabled'),
        ))!;
        cipher.hold = true;
        d.f.network.handler = traktReply;
        final tracks = CompletionDelivery(
          'restoreTrackPreferences',
          (v) => v == null,
        );
        final a = startupSource('gate-$mode');
        try {
          await tracks.run(
            () => d.begin(
              d.screen(
                sources: [a],
                id: 'tt5100000',
                trakt: true,
                startAtPercent: mode == 'watched stop' ? .81 : null,
              ),
            ),
          );
          await d.openEntered();
          expect(find.byType(PlaybackStartupView), findsOneWidget);
          d.frame();
          await d.f.until(t, () => tracks.pending.isNotEmpty);
          cipher.releaseAll();
          await d.settle();
          final requests = d.f.network.requests
              .where((r) => r.url.path.startsWith('/scrobble/'))
              .toList();
          expect(
            requests,
            isEmpty,
            reason:
                'Auth resolution while the gate is active must not dispatch',
          );
          expect(
            d.periodic.where((v) => v.$1 == const Duration(minutes: 2)),
            isEmpty,
          );
          if (mode == 'paused') {
            await d.player.pause();
            await d.tick();
          } else if (mode == 'zero duration') {
            d.player.state = d.player.state.copyWith(duration: Duration.zero);
            d.player.emit('duration', Duration.zero);
            await d.tick();
          } else if (mode == 'disposed') {
            await t.pumpWidget(const SizedBox.shrink());
            await d.f.until(t, () => d.player.disposed.isCompleted);
          }
          expect(
            tracks.pending,
            isNotEmpty,
            reason: 'Assert the gate boundary while restoration is still held',
          );
          tracks.release();
          await d.settle();
          final sent = d.f.network.requests
              .where((r) => r.url.path.startsWith('/scrobble/'))
              .toList();
          final active = d.periodic
              .where((v) => v.$1 == const Duration(minutes: 2) && v.$2.isActive)
              .toList();
          if (mode == 'start') {
            expect(sent.map((r) => r.url.path), ['/scrobble/start']);
            expect(active, hasLength(1));
            await d.tick(const Duration(minutes: 2));
            await d.f.until(
              t,
              () =>
                  d.f.network.requests
                      .where((r) => r.url.path == '/scrobble/start')
                      .length ==
                  2,
            );
          } else if (mode == 'watched stop') {
            expect(sent.map((r) => r.url.path), ['/scrobble/stop']);
            expect(
              active,
              isEmpty,
              reason:
                  'Dispatching start can produce stop; it must not create a start heartbeat',
            );
            expect(d.player.state.position, const Duration(seconds: 972));
          } else {
            expect(sent, isEmpty);
            expect(active, isEmpty);
          }
          expect(find.byType(PlaybackStartupView), findsNothing);
          if (mode == 'disposed') {
            final leaked = d.periodic
                .where(
                  (v) => v.$1 == const Duration(seconds: 6) && v.$2.isActive,
                )
                .toList();
            expect(
              leaked,
              hasLength(1),
              reason:
                  'Preserve the original late autosave registration after track restoration resumes past disposal',
            );
            for (final timer in leaked) {
              timer.$2.cancel();
            }
          }
        } finally {
          tracks.release();
          cipher.releaseAll();
          await d.close();
          TraktTestTransport.instance.recorder = null;
        }
      },
    );
  }
  for (final playlist in [false, true]) {
    testWidgets(
      'P16 a paused outgoing session resumes Simkl and MDBList checkpoints only when explicit ${playlist ? 'playlist' : 'direct'} source validation releases',
      (t) async {
        final f = VideoPlayerEnvironment();
        final d = SecondaryTrackerDriver(t, f);
        await d.initialize();
        final a = startupSource('paused-gate-a'),
            b = startupSource('paused-gate-b');
        try {
          await d.mount(
            VideoPlayerScreen(
              videoUrl: a.directUrl!,
              title: 'P16 paused release',
              contentType: 'movie',
              contentImdbId: 'tt5100000',
              simklScrobble: true,
              mdblistScrobble: true,
              stremioSources: [a, b],
              resolveStremioSource: (s) async => s.directUrl,
              resolveSourceToPlaylist: playlist
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(url: s.directUrl!, title: s.name),
                    ]
                  : null,
            ),
          );
          await d.waitCheckpoint('mdblist', 1);
          await d.position(300000);
          playerControls(t).onPlayPause();
          await d.drain();
          expect(f.player.state.playing, isFalse);
          await d.waitCheckpoint('simkl', 1);
          await d.waitCheckpoint('mdblist', 2);
          final ack = Completer<void>();
          f.player.delays['open'] = ack;
          try {
            playerControls(t).onShowStremioSources!();
            await f.advance(t, const Duration(milliseconds: 300));
            final sheet = t.widget<SourceSheet>(find.byType(SourceSheet));
            final selectedUrl = (await f.finish(t, sheet.resolveSource(b)))!;
            final action = f.actions.start(
              'paused source validation',
              () async {
                final dynamic pick = sheet.onSourceSelected;
                final dynamic result = pick(1, selectedUrl);
                if (result is Future) await result;
              },
              held: true,
            );
            await f.until(
              t,
              () => f.player.calls.where((v) => v.$1 == 'open').length == 2,
            );
            expect(d.forTracker('simkl'), hasLength(1));
            expect(d.forTracker('mdblist'), hasLength(2));
            expect(action.isCompleted, isFalse);
            ack.complete();
            f.player.delays.remove('open');
            await f.finish(t, action.future);
            expect(
              d.forTracker('mdblist'),
              hasLength(2),
              reason: 'Identical 25% release checkpoint is deduplicated',
            );
            expect(f.player.state.playing, isTrue);
            expect(
              d.forTracker('simkl'),
              hasLength(1),
              reason:
                  'Simkl release stamps playing locally; it does not POST start',
            );
            await d.position(360000);
            await d.tick(const Duration(minutes: 2));
            await d.waitCheckpoint('simkl', 2);
            await d.waitCheckpoint('mdblist', 3);
            d.expectCheckpoint('simkl', 1, 'pause', 30, movie: true);
            d.expectCheckpoint('mdblist', 2, 'pause', 30, movie: true);
          } finally {
            if (!ack.isCompleted) ack.complete();
            f.player.delays.remove('open');
          }
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P16 a startup seek rejection clears the gate then re-arms Trakt from the retained catch in that order',
    (t) async {
      final d = StartupDriver(t);
      await d.initialize();
      TraktTestTransport.instance.attach(d.f);
      final cipher = (await t.runAsync(() => seedTrakt()))!;
      cipher.hold = true;
      d.f.network.handler = traktReply;
      final a = startupSource('seek-rejected-release');
      final ack = d.openGates[a.directUrl!] = Completer<void>();
      try {
        await d.begin(
          d.screen(
            sources: [a],
            id: 'tt5100000',
            trakt: true,
            startAtPercent: .25,
          ),
        );
        await d.openEntered();
        d.frame();
        await d.result();
        cipher.releaseAll();
        await d.settle();
        expect(
          d.f.network.requests.where(
            (r) => r.url.path.startsWith('/scrobble/'),
          ),
          isEmpty,
        );
        expect(ack.isCompleted, isFalse);
        d.player.failures['seek'] = StateError('fixture startup seek failed');
        ack.complete();
        await d.initialized();
        await d.settle();
        expect(find.byType(PlaybackStartupView), findsNothing);
        expect(
          d.logs.any(
            (s) => s.contains(
              'initial open failed: Bad state: fixture startup seek failed',
            ),
          ),
          isTrue,
        );
        expect(
          d.f.network.requests
              .where((r) => r.url.path.startsWith('/scrobble/'))
              .map((r) => r.url.path),
          ['/scrobble/start'],
        );
        expect(
          d.periodic.where(
            (r) => r.$1 == const Duration(minutes: 2) && r.$2.isActive,
          ),
          hasLength(1),
        );
        await d.tick(const Duration(minutes: 2));
        await d.f.until(
          t,
          () =>
              d.f.network.requests
                  .where((r) => r.url.path == '/scrobble/start')
                  .length ==
              2,
        );
      } finally {
        ack.completeIfPending();
        cipher.releaseAll();
        await d.close();
        TraktTestTransport.instance.recorder = null;
      }
    },
  );
}
