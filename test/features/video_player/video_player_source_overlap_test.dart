import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:debrify/screens/video_player/widgets/buffering_indicator.dart';
import 'package:debrify/screens/video_player/widgets/source_sheet.dart';
import 'support/local_completion_driver.dart';

import 'package:debrify/services/storage/movie_progress_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/models/torrent.dart';
import 'package:debrify/screens/video_player/widgets/transition_overlay.dart';

import 'support/startup_driver.dart';

void main() {
  testWidgets(
    'P16 an older rejected direct pick restores its captured URL after a newer pick committed',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('overlap-a'),
          b = startupSource('overlap-b'),
          c = startupSource('overlap-c', headers: {'X-Newer': 'c'});
      final ack = d.openGates[b.directUrl!] = Completer<void>();
      d.replies[b.directUrl!] = (_) {};
      try {
        await d.begin(
          d.screen(sources: [a, b, c], resolve: (s) async => s.directUrl),
        );
        await d.initialized();
        final sheet = await d.sheet();
        final older = d.select(sheet, 1, b.directUrl!);
        await d.openEntered(2);
        d.player.emit('error', 'fixture old pick rejected while ack is held');
        await d.result(count: 2);
        final newer = d.select(sheet, 2, c.directUrl!);
        await d.f.finish(t, newer.future);
        expect(d.commits, [a, c]);
        expect(older.isCompleted, isFalse);
        expect(d.player.state.playlist.medias.single.uri, c.directUrl);
        // The old probe is still subscribed to this same player's error stream.
        await d.result(count: 3);
        expect(d.event('candidate_result')[1], contains('reason=player_error'));
        ack.complete();
        await d.f.finish(t, older.future);
        expect(d.opens, [a.directUrl, b.directUrl, c.directUrl, a.directUrl]);
        expect(d.player.state.playlist.medias.single.uri, a.directUrl);
        expect(
          d.player.state.playlist.medias.single.httpHeaders,
          isNull,
          reason:
              'The outgoing header snapshot was null; the newer winner header must not reach its restore',
        );
        expect(d.commits, [a, c]);
        expect(
          find.text('This source is unavailable. Choose another source.'),
          findsOneWidget,
        );
        final restored = await d.sheet();
        expect(restored.currentSourceIndex, 0);
        d.openFailures[c.directUrl!] = StateError(
          'fixture next rejection after stale rollback',
        );
        await d.f.finish(t, d.select(restored, 2, c.directUrl!).future);
        expect(d.opens, [
          a.directUrl,
          b.directUrl,
          c.directUrl,
          a.directUrl,
          c.directUrl,
          a.directUrl,
        ]);
        expect(d.player.state.playlist.medias.single.uri, a.directUrl);
        expect(d.player.state.playlist.medias.single.httpHeaders, isNull);
        expect(d.commits, [a, c]);
      } finally {
        ack.completeIfPending();
        await d.close();
      }
    },
  );

  testWidgets(
    'P16 an older successful pick releases the shared gate while a newer candidate is still pending',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('gate-a'),
          b = startupSource('gate-b'),
          c = startupSource('gate-c');
      final oldAck = d.openGates[b.directUrl!] = Completer<void>();
      final newAck = d.openGates[c.directUrl!] = Completer<void>();
      d.replies[b.directUrl!] = (_) {};
      d.replies[c.directUrl!] = (_) {};
      try {
        await d.begin(
          d.screen(
            sources: [a, b, c],
            resolve: (s) async => s.directUrl,
            id: 'tt9200016',
          ),
        );
        await d.initialized();
        final sheet = await d.sheet();
        final older = d.select(sheet, 1, b.directUrl!);
        await d.openEntered(2);
        d.frame();
        await d.result(count: 2);
        final newer = d.select(sheet, 2, c.directUrl!);
        await d.openEntered(3);
        expect(newer.isCompleted, isFalse);
        // Position dispatch during the newer validation is initially blocked.
        d.player.emit('position', const Duration(minutes: 17));
        await d.tick();
        expect(
          await d.f.finish(
            t,
            MovieProgressStorage.isMovieFinished('tt9200016'),
          ),
          isFalse,
        );
        oldAck.complete();
        await d.f.finish(t, older.future);
        expect(d.commits, [a, b]);
        expect(newAck.isCompleted, isFalse);
        expect(newer.isCompleted, isFalse);
        final intermediate = await d.sheet();
        expect(
          intermediate.currentSourceIndex,
          1,
          reason:
              'The old successful caller writes its index after the newer caller already selected index 2',
        );
        intermediate.onClose();
        await d.tick();
        d.player.emit('position', const Duration(minutes: 17));
        await d.tick();
        await d.settle();
        expect(
          await d.f.finish(
            t,
            MovieProgressStorage.isMovieFinished('tt9200016'),
          ),
          isTrue,
          reason:
              'The original older finally releases the shared validation bool; the new probe is still awaiting its open acknowledgement',
        );
        d.frame();
        await d.result(count: 3);
        newAck.complete();
        await d.f.finish(t, newer.future);
        expect(d.commits, [a, b, c]);
      } finally {
        oldAck.completeIfPending();
        newAck.completeIfPending();
        await d.close();
      }
    },
  );
  for (final playlist in [false, true]) {
    testWidgets(
      'P16 ${playlist ? 'playlist' : 'direct'} source transition cancels its phase-one timers and stops its borrowed animation at 1500ms',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('transition-timer-a'),
            b = startupSource('transition-timer-b');
        try {
          await d.begin(
            d.screen(
              sources: [a, b],
              resolve: (s) async => s.directUrl,
              playlist: playlist
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(url: b.directUrl!, title: 'Incoming'),
                    ]
                  : null,
            ),
          );
          await d.initialized();
          final sheet = await d.sheet();
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          final selected = d.select(sheet, 1, url);
          await d.f.finish(t, selected.future);
          final name = playlist
              ? 'switchToSourcePlaylist'
              : 'switchToStremioSource';
          final finalTimer = d.timers
              .singleWhere(
                (r) =>
                    r.$1 == const Duration(milliseconds: 1500) &&
                    r.$2.isActive &&
                    (d.timerOrigins[r.$2]?.contains(name) ?? false),
              )
              .$2;
          expect(
            d.timers.where(
              (r) =>
                  r.$2.isActive &&
                  (r.$1 == const Duration(milliseconds: 1500) ||
                      r.$1 == const Duration(seconds: 3)) &&
                  (d.timerOrigins[r.$2]?.contains(
                        '_bindPlayerInstanceSubscriptions',
                      ) ??
                      false),
            ),
            isEmpty,
          );
          final overlay = t.widget<TransitionOverlay>(
            find.byType(TransitionOverlay),
          );
          expect(overlay.rainbowController.isAnimating, isTrue);
          final remaining =
              const Duration(milliseconds: 1500) -
              t.binding.clock.now().difference(d.timerCreated[finalTimer]!);
          expect(remaining, greaterThan(Duration.zero));
          await d.tick(remaining - const Duration(milliseconds: 1));
          expect(find.byType(TransitionOverlay), findsOneWidget);
          expect(overlay.rainbowController.isAnimating, isTrue);
          await d.tick(const Duration(milliseconds: 1));
          expect(find.byType(TransitionOverlay), findsNothing);
          expect(overlay.rainbowController.isAnimating, isFalse);
          expect(finalTimer.isActive, isFalse);
          final phases = d.logs
              .where((s) => s.contains('Playback started; overlay phase 1'))
              .length;
          await d.player.pause();
          await d.tick();
          await d.player.play();
          await d.tick();
          expect(
            d.logs.where(
              (s) => s.contains('Playback started; overlay phase 1'),
            ),
            hasLength(phases),
            reason:
                'The finished transition is no longer running when a later play edge arrives',
          );
        } finally {
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P16 a held debrid startup may overwrite a newer explicit direct winner when its old acknowledgement returns',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('debrid-initial', type: StreamType.torrent),
          b = startupSource('debrid-newer');
      final ack = d.openGates[a.directUrl!] = Completer<void>();
      try {
        await d.begin(
          d.screen(sources: [a, b], resolve: (s) async => s.directUrl),
        );
        await d.openEntered();
        d.frame();
        await d.result();
        expect(d.commits, isEmpty);
        expect(
          d.event('candidate_result').singleOrNull,
          contains('reason=duration_known'),
        );
        final sheet = await d.sheet();
        final selected = d.select(sheet, 1, b.directUrl!);
        await d.f.finish(t, selected.future);
        expect(d.commits, [b]);
        expect(d.player.state.playlist.medias.single.uri, b.directUrl);
        expect(ack.isCompleted, isFalse);
        ack.complete();
        await d.initialized();
        expect(d.commits, [b, a]);
        expect(d.opens, [a.directUrl, b.directUrl]);
        expect(d.player.state.playlist.medias.single.uri, a.directUrl);
        final restored = await d.sheet();
        expect(
          restored.currentSourceIndex,
          0,
          reason:
              'The original ladder has no explicit-pick ticket and writes its captured winner after the newer direct selection',
        );
      } finally {
        ack.completeIfPending();
        await d.close();
      }
    },
  );
  for (final playlist in [false, true]) {
    testWidgets(
      'P16 ${playlist ? 'playlist' : 'direct'} choice clears buffering before awaits and preserves pre-validation completion while pause is held',
      (t) async {
        final d = StartupDriver(t, autoFrame: true);
        await d.initialize();
        final a = startupSource('buffering-a'),
            b = startupSource('buffering-b');
        final pause = Completer<void>();
        final checkpoint = CompletionDelivery(
          'switchToSourcePlaylist',
          (v) => v == null,
        )..armed = playlist;
        try {
          await d.begin(
            d.screen(
              id: 'tt9200016',
              sources: [a, b],
              resolve: (s) async => s.directUrl,
              playlist: playlist
                  ? (s, {canContinue}) async => [
                      PlaylistEntry(url: b.directUrl!, title: 'Incoming'),
                    ]
                  : null,
            ),
          );
          await d.initialized();
          final sheet = await d.sheet();
          final url = (await d.f.finish(t, sheet.resolveSource(b)))!;
          d.player.state = d.player.state.copyWith(buffering: true);
          d.player.emit('buffering', true);
          await d.tick(const Duration(seconds: 1));
          double opacity() => t
              .widget<AnimatedOpacity>(
                find
                    .ancestor(
                      of: find.byType(BufferingIndicator),
                      matching: find.byType(AnimatedOpacity),
                    )
                    .first,
              )
              .opacity;
          expect(opacity(), 1);
          d.player.delays['pause'] = pause;
          final before = d.player.calls.where((c) => c.$1 == 'pause').length;
          final action = checkpoint.run(() => d.select(sheet, 1, url));
          await d.f.until(
            t,
            () => playlist
                ? checkpoint.pending.isNotEmpty
                : d.player.calls.where((c) => c.$1 == 'pause').length > before,
          );
          expect(action.isCompleted, isFalse);
          await d.tick();
          expect(find.byType(SourceSheet), findsNothing);
          expect(opacity(), 0);
          checkpoint.release();
          await d.f.until(
            t,
            () => d.player.calls.where((c) => c.$1 == 'pause').length > before,
          );
          expect(pause.isCompleted, isFalse);
          d.player.emit('position', const Duration(minutes: 17));
          await d.settle();
          expect(
            await d.f.finish(
              t,
              MovieProgressStorage.isMovieFinished('tt9200016'),
            ),
            isTrue,
            reason:
                'The original arms validation only after pause returns; the transition itself does not block local completion',
          );
          pause.complete();
          await d.f.finish(t, action.future);
          expect(d.commits, [a, b]);
        } finally {
          checkpoint.release();
          pause.completeIfPending();
          await d.close();
        }
      },
    );
  }
  testWidgets(
    'P16 a rejected direct pick swallows a failed previous-source reopen and leaves playback stopped with its original identity',
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('failed-restore-a', headers: {'X-Original': 'a'}),
          b = startupSource('failed-restore-b');
      try {
        await d.begin(
          d.screen(sources: [a, b], resolve: (s) async => s.directUrl),
        );
        await d.initialized();
        await d.player.seek(const Duration(seconds: 37));
        await d.tick();
        final sheet = await d.sheet();
        d.openFailures[b.directUrl!] = StateError('fixture rejected candidate');
        d.openFailures[a.directUrl!] = StateError(
          'fixture outgoing restore failed',
        );
        final action = d.select(sheet, 1, b.directUrl!);
        Object? error;
        try {
          await d.f.finish(t, action.future);
        } catch (e) {
          error = e;
        }
        expect(error, isNull);
        expect(d.opens, [a.directUrl, b.directUrl, a.directUrl]);
        expect(d.commits, [a]);
        expect(
          d.logs,
          contains('Player: previous source restore failed (StateError)'),
        );
        expect(d.player.state.playlist.medias.single.uri, a.directUrl);
        expect(d.player.state.playing, isFalse);
        expect(d.player.state.position, Duration.zero);
        expect(
          find.text('This source is unavailable. Choose another source.'),
          findsOneWidget,
        );
        final restored = await d.sheet();
        expect(restored.currentSourceIndex, 0);
      } finally {
        await d.close();
      }
    },
  );
  testWidgets(
    "P16 a direct winner becomes the next rejected choice's physical URL, header and source-index rollback target",
    (t) async {
      final d = StartupDriver(t, autoFrame: true);
      await d.initialize();
      final a = startupSource('headers-a', headers: {'X-Source': 'a'}),
          b = startupSource('headers-b', headers: {'X-Source': 'b'}),
          c = startupSource('headers-c', headers: {'X-Source': 'c'});
      try {
        await d.begin(
          VideoPlayerScreen(
            videoUrl: a.directUrl!,
            title: 'P16 header ownership',
            contentType: 'movie',
            httpHeaders: a.httpHeaders,
            stremioSources: [a, b, c],
            resolveStremioSource: (s) async => s.directUrl,
            onStremioSourceCommitted: (s) async => d.commits.add(s),
          ),
        );
        await d.initialized();
        await d.player.seek(const Duration(seconds: 37));
        await d.tick();
        final first = await d.sheet();
        await d.f.finish(t, d.select(first, 1, b.directUrl!).future);
        expect(d.commits, [a, b]);
        expect(
          find.text('This source is unavailable. Choose another source.'),
          findsNothing,
        );
        expect(d.player.state.playlist.medias.single.httpHeaders, {
          'X-Source': 'b',
        });
        final next = await d.sheet();
        d.openFailures[c.directUrl!] = StateError(
          'fixture later choice rejection',
        );
        await d.f.finish(t, d.select(next, 2, c.directUrl!).future);
        expect(
          d.logs.where((line) => line.contains('event=player_switch_rejected')),
          [contains('index=2 previous=1')],
        );
        expect(d.opens, [a.directUrl, b.directUrl, c.directUrl, b.directUrl]);
        expect(d.player.state.playlist.medias.single.uri, b.directUrl);
        expect(d.player.state.playlist.medias.single.httpHeaders, {
          'X-Source': 'b',
        });
        expect(d.player.state.position, const Duration(seconds: 37));
        expect(d.commits, [a, b]);
        final restored = await d.sheet();
        expect(restored.currentSourceIndex, 1);
      } finally {
        await d.close();
      }
    },
  );
}
