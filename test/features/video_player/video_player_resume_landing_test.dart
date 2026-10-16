import 'dart:async';
import 'package:debrify/screens/video_player_screen.dart';
import 'package:debrify/services/storage/video_resume_storage.dart';
import 'package:debrify/widgets/series_browser.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/resume_driver.dart';
import 'support/player_actions.dart';
import 'support/video_player_environment.dart';

void main() {
  for (final scenario in [
    'stable',
    'tolerance edge',
    'below tolerance',
    'transient',
    'user seek',
    'dispose',
    'dispose during confirmation',
    'episode reset',
  ]) {
    testWidgets(
      'Resume P14 landing $scenario keeps verification owned and drains it',
      (t) async {
        final gate = Completer<void>();
        final f = VideoPlayerEnvironment(
          configurePlayer: (p) {
            p.delays['seek'] = gate;
            if (scenario == 'tolerance edge') {
              p.seekAcknowledgementPosition = const Duration(
                milliseconds: 290000,
              );
            } else if (scenario == 'below tolerance') {
              p.seekAcknowledgementPosition = const Duration(
                milliseconds: 289999,
              );
            } else if (scenario != 'stable' &&
                scenario != 'transient' &&
                scenario != 'dispose during confirmation') {
              p.seekAcknowledgementPosition = Duration.zero;
            }
          },
        );
        await t.runAsync(f.initialize);
        final d = ResumeVerifierDriver(t, f);
        d.captureLogs();
        const url = 'https://player.test/p14-landing-one.mp4';
        const first = PlaylistEntry(url: url, title: 'Landing.Show.S01E01.mkv');
        const second = PlaylistEntry(
          url: 'https://player.test/p14-landing-two.mp4',
          title: 'Landing.Show.S01E02.mkv',
        );
        try {
          final key = scenario == 'episode reset'
              ? 'Landing.Show.S01E01'.hashCode.toString()
              : url;
          await f.finish(
            t,
            VideoResumeStorage.upsertVideoResume(key, {
              'positionMs': 300000,
              'speed': 1.0,
              'aspect': 'contain',
            }),
          );
          await d.observe(
            () => f.mount(
              t,
              VideoPlayerScreen(
                videoUrl: url,
                title: 'Landing fixture',
                playlist: scenario == 'episode reset' ? [first, second] : null,
              ),
            ),
          );
          await f.until(t, () => f.player.calls.any((c) => c.$1 == 'seek'));
          expect(gate.isCompleted, isFalse);
          gate.complete();
          for (var i = 0; i < 20 && !d.pending; i++) {
            await f.advance(t, const Duration(milliseconds: 10));
          }
          expect(
            d.pending,
            isTrue,
            reason:
                'The guarded startup seek must leave an observable verifier await pending',
          );
          expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(1));
          if (scenario == 'stable' ||
              scenario == 'transient' ||
              scenario == 'tolerance edge' ||
              scenario == 'dispose during confirmation') {
            expect(
              d.timers.map((v) => v.$1),
              contains(const Duration(milliseconds: 800)),
            );
            await f.advance(t, const Duration(milliseconds: 200));
            expect(
              d.pending,
              isTrue,
              reason: 'A momentary target position is not a confirmed landing',
            );
            if (scenario == 'transient') {
              f.player.state = f.player.state.copyWith(position: Duration.zero);
              f.player.emit('position', Duration.zero);
            }
            if (scenario == 'dispose during confirmation') {
              await f.until(
                t,
                () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
              );
              expect(d.pending, isTrue);
              f.player.state = f.player.state.copyWith(
                position: const Duration(milliseconds: 289999),
              );
              f.player.emit('position', f.player.state.position);
              await t.pumpWidget(const SizedBox.shrink());
            }
            await f.advance(t, const Duration(milliseconds: 600));
            if (scenario == 'stable' || scenario == 'tolerance edge') {
              await d.drain();
              expect(
                d.logs.where((v) => v.contains('landing was transient')),
                isEmpty,
              );
            } else if (scenario == 'dispose during confirmation') {
              await d.drain();
              expect(f.player.disposed.isCompleted, isTrue);
              expect(
                d.logs.where((v) => v.contains('landing was transient')),
                isEmpty,
                reason:
                    'The post-confirmation lifetime guard returns before inspecting/logging the unwound position',
              );
            } else {
              expect(d.pending, isTrue);
              expect(
                d.logs.where(
                  (v) => v.contains(
                    'landing was transient (masked seek unwound to 0ms)',
                  ),
                ),
                hasLength(1),
              );
              final controls = playerControls(t);
              controls.onSeekBarChanged(0.2);
              controls.onSeekBarChangeEnd();
              await f.advance(t, const Duration(milliseconds: 250));
              await d.drain();
            }
          } else if (scenario == 'below tolerance') {
            expect(
              d.timers.map((v) => v.$1),
              contains(const Duration(milliseconds: 200)),
            );
            expect(
              d.timers.map((v) => v.$1),
              isNot(contains(const Duration(milliseconds: 800))),
            );
            f.player.seekAcknowledgementPosition = null;
            final controls = playerControls(t);
            controls.onSeekBarChanged(0.2);
            controls.onSeekBarChangeEnd();
            await f.advance(t, const Duration(milliseconds: 250));
            await d.drain();
          } else if (scenario == 'user seek') {
            f.player.seekAcknowledgementPosition = null;
            final controls = playerControls(t);
            controls.onSeekBarChanged(0.2);
            controls.onSeekBarChangeEnd();
            await f.advance(t, const Duration(milliseconds: 250));
            await d.drain();
            expect(f.player.state.position, const Duration(minutes: 4));
            expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(2));
          } else if (scenario == 'dispose') {
            await f.until(
              t,
              () => d.periodic.any((v) => v.$1 == const Duration(seconds: 6)),
              reason:
                  'Dispose the armed verifier after real startup registered autosave',
            );
            expect(d.pending, isTrue);
            await t.pumpWidget(const SizedBox.shrink());
            await f.advance(t, const Duration(milliseconds: 250));
            await d.drain();
            expect(f.player.disposed.isCompleted, isTrue);
            expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(1));
          } else {
            playerControls(t).onShowPlaylist();
            await f.until(
              t,
              () => find.byType(SeriesBrowser).evaluate().isNotEmpty,
            );
            final browser = t.widget<SeriesBrowser>(find.byType(SeriesBrowser));
            final pending = browser.onEpisodeSelected(1, 2);
            await f.finish(t, pending);
            await f.advance(t, const Duration(milliseconds: 250));
            await d.drain();
            expect(f.player.calls.where((c) => c.$1 == 'open'), hasLength(2));
            expect(f.player.calls.where((c) => c.$1 == 'seek'), hasLength(1));
          }
          expect(d.logs.where((v) => v.contains('re-issuing')), isEmpty);
        } finally {
          if (!gate.isCompleted) gate.complete();
          await t.pumpWidget(const SizedBox.shrink());
          await f.advance(t, const Duration(milliseconds: 800));
          await d.drain();
          d.restoreLogs();
          await f.close(t);
        }
      },
    );
  }
}
