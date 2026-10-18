import 'package:debrify/models/torrent.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:debrify/widgets/playback_startup_view.dart';

import 'support/startup_driver.dart';

void main() {
  for (final duration in [1, 179999, 180000, 180001]) {
    testWidgets(
      'P16 AIOStreams candidate duration $duration preserves the exact slate boundary',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        final a = startupSource('aio-$duration', addon: 'org.aiostreams');
        try {
          await d.begin(d.screen(sources: [a]));
          await d.openEntered();
          d.frame(duration: Duration(milliseconds: duration));
          await d.result();
          if (duration < 180000) {
            expect(
              d.event('candidate_result').singleOrNull,
              contains('ok=false reason=aiostreams_error_slate'),
            );
            expect(d.commits, isEmpty);
            expect(d.player.calls.where((c) => c.$1 == 'stop'), hasLength(1));
          } else {
            await d.committed();
            expect(
              d.event('candidate_result').singleOrNull,
              contains('ok=true reason=decoded_video'),
            );
            expect(d.commits, [a]);
            expect(d.player.calls.where((c) => c.$1 == 'stop'), isEmpty);
          }
          expect(d.activeProbes, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final metadata in ['missing', 'slate', 'real']) {
    testWidgets(
      'P16 AIOStreams one-second duration grace: $metadata metadata',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        final a = startupSource('aio-grace', addon: 'AIOStreams');
        try {
          await d.begin(d.screen(sources: [a]));
          await d.openEntered();
          d.frame(duration: Duration.zero);
          await d.tick();
          final grace = d.timers
              .where((row) => row.$1 == const Duration(seconds: 1))
              .map((row) => row.$2)
              .toList();
          expect(grace, hasLength(1));
          expect(grace.single.isActive, isTrue);
          d.player.emit<int?>('width', 1290);
          d.player.emit('position', const Duration(milliseconds: 90));
          await d.tick(const Duration(milliseconds: 800));
          expect(d.event('candidate_result'), isEmpty);
          expect(
            d.timers.where((row) => row.$1 == const Duration(seconds: 1)),
            hasLength(1),
            reason: 'Evidence updates do not restart the grace timer',
          );
          if (metadata != 'missing') {
            d.player.emit(
              'duration',
              Duration(seconds: metadata == 'slate' ? 20 : 200),
            );
            await d.result();
            expect(grace.single.isActive, isFalse);
          } else {
            await d.tick(const Duration(milliseconds: 200));
            await d.result();
          }
          expect(
            d.event('candidate_result').singleOrNull,
            contains(
              metadata == 'slate'
                  ? 'ok=false reason=aiostreams_error_slate'
                  : 'ok=true reason=decoded_video',
            ),
          );
          if (metadata != 'slate') {
            await d.committed();
            d.frame();
            await d.settle();
          }
          await d.tick(const Duration(milliseconds: 1100));
          expect(d.event('candidate_result'), hasLength(1));
          expect(d.activeProbes, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }

  for (final debrid in [false, true]) {
    for (final cause in ['error', 'timeout', 'stop throws']) {
      testWidgets(
        'P16 ${debrid ? 'debrid' : 'VOD'} $cause rejects once and cancels all candidate streams',
        (t) async {
          final d = StartupDriver(t);
          await d.initialize();
          final a = startupSource(
            'failure',
            type: debrid ? StreamType.torrent : StreamType.directUrl,
          );
          try {
            await d.begin(d.screen(sources: [a]));
            await d.openEntered();
            if (cause == 'stop throws') {
              d.player.failures['stop'] = StateError('fixture stop failure');
            }
            if (cause == 'timeout') {
              await d.tick(const Duration(seconds: 11));
              expect(d.event('candidate_result'), isEmpty);
              await d.tick(const Duration(milliseconds: 1100));
              expect(d.event('candidate_result'), hasLength(1));
            } else {
              d.player.emit('error', 'fixture ordinary source error');
            }
            await d.result();
            await d.f.until(t, () => d.activeProbes.isEmpty);
            expect(
              d.event('candidate_result').singleOrNull,
              contains(
                cause == 'timeout'
                    ? 'ok=false reason=timeout'
                    : 'ok=false reason=player_error',
              ),
            );
            expect(d.player.calls.where((c) => c.$1 == 'stop'), hasLength(1));
            expect(d.commits, isEmpty);
            final delivered = d.probeSubscriptions.fold(
              0,
              (int n, s) => n + s.deliveries,
            );
            d.player.emit('error', 'late source error');
            d.frame();
            d.player.emit('buffer', const Duration(minutes: 3));
            await d.tick();
            expect(
              d.probeSubscriptions.fold(0, (int n, s) => n + s.deliveries),
              delivered,
              reason: 'Cancelled listeners receive no later delivery',
            );
            expect(d.event('candidate_result'), hasLength(1));
            await d.f.until(t, () => d.event('exhausted').isNotEmpty);
            expect(find.byType(PlaybackStartupView), findsNothing);
            expect(
              find.text('No playable source could be started.'),
              cause == 'timeout' ? findsOneWidget : findsNWidgets(2),
            );
          } finally {
            await d.close();
          }
        },
      );
    }
  }

  for (final debrid in [false, true]) {
    testWidgets(
      'P16 growing ${debrid ? 'debrid ' : ''}download extends after the real base deadline, then rejects unchanged buffer after the three-second step',
      (t) async {
        final d = StartupDriver(t);
        await d.initialize();
        final a = startupSource(
          'growing',
          type: debrid ? StreamType.torrent : StreamType.directUrl,
        );
        try {
          await d.begin(d.screen(sources: [a]));
          await d.openEntered();
          d.player.emit('buffer', const Duration(seconds: 10));
          await d.tick();
          final clock = Stopwatch()..start();
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 12200)),
          );
          expect(clock.elapsed, greaterThan(const Duration(seconds: 12)));
          expect(
            clock.elapsed,
            lessThan(const Duration(seconds: 35)),
            reason: 'The real-time witness has a bounded wall-clock budget',
          );
          await d.tick(const Duration(seconds: 12));
          await d.f.until(t, () => d.event('watchdog_extend').isNotEmpty);
          expect(d.event('candidate_result'), isEmpty);
          expect(
            d.event('watchdog_extend').singleOrNull,
            contains('bufferedMs=10000'),
          );
          expect(
            d.timers.where(
              (v) => v.$1 == const Duration(seconds: 3) && v.$2.isActive,
            ),
            hasLength(1),
          );
          await d.tick(const Duration(milliseconds: 2500));
          expect(d.commits, isEmpty);
          await d.tick(const Duration(milliseconds: 500));
          await d.result();
          expect(
            d.event('candidate_result').singleOrNull,
            contains('ok=false reason=timeout'),
          );
          expect(
            d.event('watchdog_extend'),
            hasLength(1),
            reason:
                'No second extension is allowed without newer buffered evidence',
          );
          expect(d.commits, isEmpty);
          expect(d.player.calls.where((c) => c.$1 == 'stop'), hasLength(1));
          expect(d.activeProbes, isEmpty);
        } finally {
          await d.close();
        }
      },
    );
  }
}
